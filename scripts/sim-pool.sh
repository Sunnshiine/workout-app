#!/bin/bash
set -euo pipefail

help() {
  cat <<'EOF'
Usage: scripts/sim-pool.sh create <lane> | boot <lane> | delete <lane> | delete-template | list

Owns the simulators of parallel lanes. A lane's simulator is the one device named workout-lane-<lane>,
cloned from the template workout-template-v1 (iPhone 17 Pro, iOS 27.0, booted once, keyboard preference
from scripts/sim-keyboard.sh ensure). The script touches no device whose name lacks the workout- prefix.
scripts/lane.sh calls it; call it directly to inspect or repair the pool.

  create <lane>  print the UDID of workout-lane-<lane>, cloning it first if it does not exist. Builds the
                 template on first use, and deletes the half-built device when its boot or keyboard
                 step fails. The next create deletes a half-built device a killed build left running,
                 and finishes one left Shutdown, as a build that gave up waiting for the host leaves
                 it. Leaves the clone Shutdown, so it holds no seat of the host cap.
  boot <lane>    boot it and print its UDID. test-sim.sh and verify.sh boot a lane themselves; run
                 this before a raw xcodebuild or XcodeBuildMCP call on a lane.
  delete <lane>  shut it down, delete it, and remove /tmp/workout-verify-<UDID>, holding that
                 directory's lock throughout, so no run can claim the simulator meanwhile. A missing
                 device is a note on stderr and exit 0.
  delete-template
                 delete workout-template-v1, a workout-template-v1-building a crashed build left,
                 and older templates, under the pool lock; lanes cloned from them keep working,
                 and the next create builds the template again. A newer recipe's template stays.
  list           TSV, header UDID STATE ROLE NAME, one row per workout-* device (role template, building,
                 newer-template, stale-template, or lane), then `booted: N of cap M` counting every
                 device on the host. A newer-template belongs to a newer copy of this script, which
                 this one never deletes.

Every boot, the template's and boot's, goes through the host admission test-sim.sh and verify.sh use
(scripts/sim-lock.sh): it waits, saying why once a minute, while free memory is under
WORKOUT_MEM_FLOOR or WORKOUT_SIM_CAP other simulators are booted. A device already booted does not wait.

A lane name matches ^[A-Za-z0-9][A-Za-z0-9._-]{0,63}$. stdout carries only the output above; progress
goes to stderr. create holds the pool lock, <WORKOUT_HOST_LOCK_DIR>/sim-pool, and its holder is
written in that file.

Environment:
  WORKOUT_SIM_CAP        most simulators booted at once host-wide (default 6)
  WORKOUT_MEM_FLOOR      lowest free memory, kern.memorystatus_level in percent, a boot starts at
                         (default 25; 0 turns it off)
  WORKOUT_ADMIT_WAIT     seconds to wait for the pool lock or the host before exit 75 (default 540)
  WORKOUT_HOST_LOCK_DIR  the host-wide lock directory (default /tmp/workout-host-locks)

Exit codes: 0 done, 1 no such lane device (boot), 2 usage or a bad setting, 69 iOS 27.0 runtime or
iPhone 17 Pro device type missing, 70 simctl failed or two devices share a name, 75 busy: the pool
lock, the host's memory floor or cap, a test-sim or verify run holding the simulator, or a verify
run's app still running on it.
EOF
}

usage() { help >&2; exit 2; }

case ${1:-} in -h | --help) help; exit 0 ;; esac

here=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
. "$here/sim-lock.sh"

version=1
template=workout-template-v$version
building=$template-building
version_of='function version_of(name, n) {
  if (name !~ /^workout-template-v[0-9]+(-building)?$/) return -1
  n = substr(name, 19); sub(/-building$/, "", n); return n + 0 }'

die() { echo "sim-pool: $2" >&2; exit "$1"; }

# A flock is shared by every process holding the fd, so nothing that may outlive this script gets one.
simctl() { xcrun simctl "$@" 4>&- 9>&-; }

lock_pool() {
  local lock=$host_lock_dir/sim-pool rc=0
  exec 4>>"$lock"
  try_flock 4 LOCK_EX $((WORKOUT_ADMIT_WAIT * 20 + 1)) || rc=$?
  [ $rc -ne 75 ] || die 75 "waited $WORKOUT_ADMIT_WAIT s for the pool lock, held by $(cat "$lock") (lsof $lock lists it)"
  [ $rc -eq 0 ] || exit $rc
  printf 'sim-pool.sh %s (pid %s)\n' "$1" "$$" >"$lock"
}

load_devices() {
  local listing
  listing=$(simctl list devices -j) || die 70 "xcrun simctl list devices failed"
  devices=$(printf %s "$listing" | python3 -c '
import json, sys
for ds in json.load(sys.stdin)["devices"].values():
    for d in ds: print(d["udid"], d["state"], d["name"], sep="\t")') || die 70 "xcrun simctl list devices printed no device list"
}

pick() { printf '%s\n' "$devices" | awk -F '\t' "$@"; }

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

boot_admitted() {
  state_of "$1"
  case $state in Booted | Booting) return ;; esac
  (exec 4>&- && wait_until_clear "the host before booting $1" admit_claim "$1" 0) || exit
}

abandon_build() {
  echo "sim-pool: $2; deleting $1, the $building that failed, so it holds no seat of the cap" >&2
  remove_device "$1"
  exit 70
}

ensure_template() {
  local udid state rc=0 doomed
  find_named "$template"
  if [ -n "$udid" ]; then
    printf '%s\n' "$udid"
    return
  fi
  load_devices
  for doomed in $(pick -v n="$building" '$3 == n && $2 != "Shutdown" { print $1 }'); do
    echo "sim-pool: deleting $doomed, a $building a killed build left running" >&2
    remove_device "$doomed"
  done
  echo "sim-pool: building $template" >&2
  udid=$("$here/ensure-simulator.sh" 'iPhone 17 Pro' 27.0 "$building" 4>&-) || rc=$?
  case $rc in 0) ;; 1) exit 69 ;; *) exit 70 ;; esac
  boot_admitted "$udid"
  simctl bootstatus "$udid" -b >&2 || abandon_build "$udid" "$udid did not finish booting"
  "$here/sim-keyboard.sh" ensure "$udid" >&2 4>&- || abandon_build "$udid" "scripts/sim-keyboard.sh ensure $udid failed"
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

delete_templates() {
  local doomed udid
  load_devices
  doomed=$(pick -v v="$version" "$version_of"'version_of($3) >= 0 && version_of($3) <= v { print $1 }')
  [ -n "$doomed" ] || { echo "sim-pool: no $template to delete" >&2; return; }
  for udid in $doomed; do
    remove_device "$udid"
    echo "sim-pool: deleted $udid" >&2
  done
}

boot_lane() {
  local udid state
  find_named "workout-lane-$1"
  [ -n "$udid" ] || die 1 "no device is named workout-lane-$1; run scripts/sim-pool.sh create $1"
  boot_admitted "$udid"
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
  printf 'booted: %s of cap %s\n' "$(pick '$2 == "Booted" || $2 == "Booting"' | grep -c . || true)" "$WORKOUT_SIM_CAP"
}

[ $# -ge 1 ] || usage
command=$1
case $command in
  list) [ $# -eq 1 ] || usage; list_pool; exit ;;
  delete-template) [ $# -eq 1 ] || usage; lock_pool delete-template; delete_templates; exit ;;
esac
[ $# -eq 2 ] || usage
lane=$2
[[ $lane =~ ^[A-Za-z0-9][A-Za-z0-9._-]{0,63}$ ]] || usage
case $command in
  create) lock_pool "create $lane"; clone_lane "$lane" ;;
  boot) boot_lane "$lane" ;;
  delete) delete_lane "$lane" ;;
  *) usage ;;
esac
