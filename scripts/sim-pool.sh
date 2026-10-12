#!/bin/bash
set -euo pipefail

usage() {
  cat >&2 <<'EOF'
Usage: scripts/sim-pool.sh create <lane> | boot <lane> | delete <lane> | list

Owns the simulators of parallel lanes. A lane's simulator is the one device named workout-lane-<lane>,
cloned from the template workout-template-v1 (iPhone 17 Pro, iOS 27.0, booted once, keyboard preference
from scripts/sim-keyboard.sh ensure). The script touches no device whose name lacks the workout- prefix.
scripts/lane.sh calls it; call it directly to inspect or repair the pool.

  create <lane>  print the UDID of workout-lane-<lane>, cloning it first if it does not exist. Builds the
                 template on first use. Leaves the clone Shutdown, so it holds no slot of the host cap.
  boot <lane>    boot it within the host cap and print its UDID.
  delete <lane>  shut it down, delete it, and remove /tmp/workout-verify-<UDID>, holding that
                 directory's lock throughout, so no run can claim the simulator meanwhile. A missing
                 device is a note on stderr and exit 0.
  list           TSV, header UDID STATE ROLE NAME, one row per workout-* device (role template, building,
                 newer-template, stale-template, or lane), then `booted: N of cap M` counting every
                 device on the host. A newer-template belongs to a newer copy of this script, which
                 this one never deletes.

A lane name matches ^[A-Za-z0-9][A-Za-z0-9._-]{0,63}$. stdout carries only the output above; progress
goes to stderr. create holds the pool lock, ${WORKOUT_HOST_LOCK_DIR:-/tmp/workout-host-locks}/
sim-pool, and its holder is written in that file.

Environment:
  WORKOUT_SIM_CAP     most simulators booted at once host-wide (default 6)
  WORKOUT_ADMIT_WAIT  seconds to wait for the pool lock or a free cap slot before exit 75 (default 540)

Exit codes: 0 done, 1 no such lane device (boot), 2 usage, 69 iOS 27.0 runtime or iPhone 17 Pro device
type missing, 70 simctl failed or two devices share a name, 75 busy: the pool lock, the host cap, a
test-sim or verify run holding the simulator, or a verify run's app still running on it.
EOF
  exit 2
}

here=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
. "$here/sim-lock.sh"

version=1
template=workout-template-v$version
building=$template-building
# The recipe version a template's name carries, or -1 for a name that carries none.
version_of='function version_of(name, n) {
  if (name !~ /^workout-template-v[0-9]+(-building)?$/) return -1
  n = substr(name, 19); sub(/-building$/, "", n); return n + 0 }'
lock_dir=${WORKOUT_HOST_LOCK_DIR:-/tmp/workout-host-locks}
admit_wait=${WORKOUT_ADMIT_WAIT:-540}
cap=${WORKOUT_SIM_CAP:-6}

die() { echo "sim-pool: $2" >&2; exit "$1"; }

case $admit_wait in '' | *[!0-9]*) die 2 "WORKOUT_ADMIT_WAIT must be a whole number of seconds: $admit_wait" ;; esac
case $cap in '' | *[!0-9]* | 0) die 2 "WORKOUT_SIM_CAP must be a whole number of at least 1: $cap" ;; esac

# A flock is shared by every process holding the fd, so nothing that may outlive this script gets one.
simctl() { xcrun simctl "$@" 4>&- 5>&- 9>&-; }

# Waits on the lock that fd $1 holds open, up to $2 seconds; 75 when the time runs out.
flock_fd() {
  python3 -c 'import fcntl, sys, time
deadline = time.time() + float(sys.argv[2])
while True:
    try: fcntl.flock(int(sys.argv[1]), fcntl.LOCK_EX | fcntl.LOCK_NB); break
    except BlockingIOError:
        if time.time() >= deadline: sys.exit(75)
        time.sleep(0.1)' "$1" "$2"
}

lock_pool() {
  local lock=$lock_dir/sim-pool rc=0
  mkdir -p "$lock_dir"
  exec 4>>"$lock"
  flock_fd 4 "$admit_wait" || rc=$?
  [ $rc -ne 75 ] || die 75 "waited $admit_wait s for the pool lock, held by $(cat "$lock") (lsof $lock lists it)"
  [ $rc -eq 0 ] || exit $rc
  printf 'sim-pool.sh %s (pid %s)\n' "$1" "$$" >"$lock"
}

# Sets $devices to one line per device on the host: UDID, state, name, tab-separated. Call it outside a
# command substitution, so its exit 70 stops the script rather than a subshell.
load_devices() {
  local listing
  listing=$(simctl list devices -j) || die 70 "xcrun simctl list devices failed"
  devices=$(printf %s "$listing" | python3 -c '
import json, sys
for ds in json.load(sys.stdin)["devices"].values():
    for d in ds: print(d["udid"], d["state"], d["name"], sep="\t")') || die 70 "xcrun simctl list devices printed no device list"
}

pick() { printf '%s\n' "$devices" | awk -F '\t' "$@"; }

# Sets $udid and $state to the one device named $1, both empty when there is none; exits 70 on two.
find_named() {
  local found count
  load_devices
  found=$(pick -v n="$1" '$3 == n { print $1 "\t" $2 }')
  count=$(printf '%s' "$found" | grep -c . || true)
  [ "$count" -le 1 ] || die 70 "$count devices are named $1: $(printf '%s' "$found" | cut -f1 | tr '\n' ' ')delete all but one with xcrun simctl delete <UDID>"
  udid=$(printf '%s' "$found" | cut -f1)
  state=$(printf '%s' "$found" | cut -f2)
}

state_of() {
  load_devices
  state=$(pick -v u="$1" '$1 == u { print $2 }')
}

shut_down() {
  local polls=0
  state_of "$1"
  case $state in
    Shutdown) return ;;
    "Shutting Down") ;;
    *) simctl shutdown "$1" >&2 || { state_of "$1"; [ "$state" = Shutdown ]; } || die 70 "could not shut down $1" ;;
  esac
  while state_of "$1" && [ "$state" != Shutdown ]; do
    [ $((polls += 1)) -le 240 ] || die 70 "$1 did not reach Shutdown in 120 s"
    sleep 0.5
  done
}

remove_device() {
  shut_down "$1"
  simctl delete "$1" >&2 || die 70 "could not delete $1"
  rm -rf "/tmp/workout-verify-$1"
}

# Interim host cap until PR #883 lands; then this body becomes its claim_sim. Takes the same admit lock.
boot_capped() {
  local start others reason
  state_of "$1"
  case $state in Booted | Booting) return ;; esac
  mkdir -p "$lock_dir"
  start=$(date +%s)
  while :; do
    exec 5>>"$lock_dir/admit"
    if flock_fd 5 0; then
      load_devices
      others=$(pick -v u="$1" '$1 != u && ($2 == "Booted" || $2 == "Booting")' | grep -c . || true)
      if [ "$others" -lt "$cap" ]; then
        simctl boot "$1" >&2 || { state_of "$1"; [ "$state" = Booted ] || [ "$state" = Booting ]; } || die 70 "could not boot $1"
        exec 5>&-
        return
      fi
      reason="$others other simulators are booted, at the cap of $cap (WORKOUT_SIM_CAP)"
    else
      reason="another claim is booting a simulator (lsof $lock_dir/admit lists it)"
    fi
    exec 5>&-
    [ $(($(date +%s) - start)) -lt "$admit_wait" ] || die 75 "gave up booting $1 after $admit_wait s: $reason"
    echo "sim-pool: waiting to boot $1: $reason" >&2
    sleep 5
  done
}

# Prints the template's UDID. The rename is the commit point: a crash leaves only a -building device,
# which the next run deletes, so a half-built template is never cloned.
ensure_template() {
  local udid state rc=0 doomed
  find_named "$template"
  if [ -n "$udid" ]; then
    printf '%s\n' "$udid"
    return
  fi
  load_devices
  for doomed in $(pick -v n="$building" '$3 == n { print $1 }'); do
    echo "sim-pool: deleting $doomed, a $building a crashed build left" >&2
    remove_device "$doomed"
  done
  echo "sim-pool: building $template" >&2
  udid=$("$here/ensure-simulator.sh" 'iPhone 17 Pro' 27.0 "$building" 4>&- 5>&-) || rc=$?
  case $rc in 0) ;; 1) exit 69 ;; *) exit 70 ;; esac
  boot_capped "$udid"
  simctl bootstatus "$udid" -b >&2 || die 70 "$udid did not finish booting"
  "$here/sim-keyboard.sh" ensure "$udid" >&2 4>&- 5>&- || exit 70
  shut_down "$udid"
  simctl rename "$udid" "$template" >&2 || die 70 "could not rename $udid to $template"
  load_devices
  for doomed in $(pick -v v="$version" "$version_of"'
    $2 == "Shutdown" && $3 !~ /-building$/ && version_of($3) >= 0 && version_of($3) < v { print $1 }'); do
    echo "sim-pool: deleting $doomed, a template of an older recipe" >&2
    remove_device "$doomed"
  done
  printf '%s\n' "$udid"
}

clone_lane() {
  local lane=workout-lane-$1 udid state source err
  find_named "$lane"
  if [ -n "$udid" ]; then
    printf '%s\n' "$udid"
    return
  fi
  source=$(ensure_template)
  shut_down "$source"
  err=$(mktemp)
  if ! udid=$(simctl clone "$source" "$lane" 2>"$err"); then
    grep -q 'current state: Booted' "$err" || die 70 "could not clone $source: $(cat "$err")"
    echo "sim-pool: $source booted before the clone; shutting it down and cloning again" >&2
    shut_down "$source"
    udid=$(simctl clone "$source" "$lane" 2>"$err") || die 70 "could not clone $source: $(cat "$err")"
  fi
  rm -f "$err"
  printf '%s\n' "$udid"
}

# Holds the simulator's verify lock from before the shutdown until its directory is gone, so no
# test-sim or verify run can claim it in between. Not claim_sim, which boots a Shutdown simulator
# once #883 lands.
delete_lane() {
  local lane=workout-lane-$1 doomed found dir pid run stop
  load_devices
  found=$(pick -v n="$lane" '$3 == n { print $1 }')
  if [ -z "$found" ]; then
    echo "sim-pool: no device is named $lane; nothing to delete" >&2
    return
  fi
  for doomed in $found; do
    dir=/tmp/workout-verify-$doomed
    mkdir -p "$dir"
    exec 9>>"$dir/lock"
    sim_flock "$doomed" LOCK_EX
    printf 'sim-pool.sh delete %s (pid %s)\n' "$1" "$$" >"$dir/lock"
    if pid=$(cat "$dir/pid" 2>/dev/null) && is_fixture_launch "$pid"; then
      run=$(cat "$dir/run" 2>/dev/null) || true
      stop="SIM=$doomed ${run:+VERIFY_RUN=$run }$(dirname "$here")/.agents/skills/verify/verify.sh stop"
      die 75 "a verify run${run:+ $run} owns the app on $doomed (pid $pid); if it is yours, run: $stop, and delete again"
    fi
    remove_device "$doomed"
    exec 9>&-
    echo "sim-pool: deleted $doomed ($lane)" >&2
  done
}

boot_lane() {
  local udid state
  find_named "workout-lane-$1"
  [ -n "$udid" ] || die 1 "no device is named workout-lane-$1; run scripts/sim-pool.sh create $1"
  boot_capped "$udid"
  simctl bootstatus "$udid" -b >&2 || die 70 "$udid did not finish booting"
  printf '%s\n' "$udid"
}

list_pool() {
  load_devices
  printf 'UDID\tSTATE\tROLE\tNAME\n'
  pick -v OFS='\t' -v t="$template" -v b="$building" -v v="$version" "$version_of"'
    $3 == t { role = "template" }
    $3 == b { role = "building" }
    $3 != t && $3 != b && index($3, "workout-template-") == 1 { role = version_of($3) > v ? "newer-template" : "stale-template" }
    index($3, "workout-lane-") == 1 { role = "lane" }
    role != "" { print $1, $2, role, $3 }
    { role = "" }' | sort -t "$(printf '\t')" -k4,4
  printf 'booted: %s of cap %s\n' "$(pick '$2 == "Booted" || $2 == "Booting"' | grep -c . || true)" "$cap"
}

[ $# -ge 1 ] || usage
command=$1
if [ "$command" = list ]; then
  [ $# -eq 1 ] || usage
  list_pool
  exit
fi
[ $# -eq 2 ] || usage
lane=$2
[[ $lane =~ ^[A-Za-z0-9][A-Za-z0-9._-]{0,63}$ ]] || usage
case $command in
  create) lock_pool "create $lane"; clone_lane "$lane" ;;
  boot) boot_lane "$lane" ;;
  delete) delete_lane "$lane" ;;
  *) usage ;;
esac
