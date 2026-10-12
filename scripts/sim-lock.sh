# shellcheck shell=bash
# Waits and refusals about the host go to the caller's stderr as it was when this was sourced, so they
# reach the agent from inside test-sim.sh's redirected build too.
exec 6>&2
verify_lease_minutes=60

pick_sim() {
  local named=$1 mode=${2:-lookup} device='iPhone 17 Pro' visual_baseline_runtime=27.0 simctl_udid picked
  if [ -n "$named" ]; then
    simctl_udid=$(printf %s "$named" | tr '[:lower:]' '[:upper:]')
    echo "$simctl_udid named"
    return
  fi
  picked=$(available_sim "$device") || return
  if [ -z "$picked" ] && [ "$mode" = create ]; then
    "$(dirname "${BASH_SOURCE[0]}")/ensure-simulator.sh" "$device" "$visual_baseline_runtime" >/dev/null || return
    picked=$(available_sim "$device") || return
  fi
  if [ -z "$picked" ]; then
    echo "no available $device simulator; verify.sh launch or scripts/test-sim.sh creates one" >&2
    return 1
  fi
  echo "$picked"
}

available_sim() {
  xcrun simctl list devices available -j | NAME="$1" python3 -c '
import json, os, sys
def version(runtime): return tuple(int(n) for n in runtime.rsplit("iOS-", 1)[-1].split("-"))
devices = [(version(runtime), d) for runtime, ds in json.load(sys.stdin)["devices"].items()
           for d in ds if d["name"] == os.environ["NAME"]]
booted = [d for d in devices if d[1]["state"] == "Booted"]
if devices:
    pick = max(booted or devices, key=lambda pair: pair[0])[1]
    print(pick["udid"], pick["state"])'
}

sim_available() {
  local listing
  listing=$(xcrun simctl list devices available -j) || return
  printf %s "$listing" | UDID="$1" python3 -c '
import json, os, sys
sys.exit(all(d["udid"] != os.environ["UDID"] for ds in json.load(sys.stdin)["devices"].values() for d in ds))' && return
  echo "no available simulator $1; xcrun simctl list devices available lists them" >&2
  return 2
}

try_flock() {
  python3 -c 'import fcntl, sys, time
for attempt in range(int(sys.argv[3])):
    if attempt: time.sleep(0.05)
    try: fcntl.flock(int(sys.argv[1]), getattr(fcntl, sys.argv[2]) | fcntl.LOCK_NB); break
    except BlockingIOError: pass
else: sys.exit(75)' "$1" "$2" "${3:-10}"
}

sim_flock() {
  local lock=/tmp/workout-verify-$1/lock rc=0
  try_flock 9 "$2" || rc=$?
  [ $rc -ne 75 ] || echo "$1 is held by a $(cat "$lock"); wait for it to finish, or use another simulator (lsof $lock lists every process holding it)" >&2
  [ $rc -eq 0 ] || exit $rc
}

is_fixture_launch() {
  case $(ps -p "$1" -o args= 2>/dev/null) in *-UITEST_FIXTURE*) return 0 ;; esac
  return 1
}

# A verify run's app holds its simulator only while some verify.sh call renewed the run's lease, the
# pid file's mtime, within the last verify_lease_minutes: its launcher is a shell that exits after
# every call, so no process says whether the run is still in use.
renew_lease() {
  local dir=/tmp/workout-verify-$1 run
  [ -f "$dir/pid" ] || return 0
  run=$(cat "$dir/run" 2>/dev/null) || true
  [ -z "${VERIFY_RUN:-}" ] || [ "$VERIFY_RUN" = "$run" ] || return 0
  touch -c "$dir/pid"
}

idle_minutes() {
  python3 -c 'import os, sys, time
try: print(int((time.time() - os.stat(sys.argv[1]).st_mtime) // 60))
except FileNotFoundError: pass' "$1"
}

# With the simulator's flock held, decides what this claim may do with the verify run recorded on UDID.
# A run in use refuses (75). With "take", an abandoned run or the claimer's own (VERIFY_RUN names it)
# gives its app up; without it, nothing changes, so a claim that later fails admission leaves the run
# as it found it.
settle_run() {
  local dir=/tmp/workout-verify-$1 pid run idle stop
  pid=$(cat "$dir/pid" 2>/dev/null) && is_fixture_launch "$pid" || return 0
  idle=$(idle_minutes "$dir/pid")
  [ -n "$idle" ] || return 0
  run=$(cat "$dir/run" 2>/dev/null) || true
  if [ -n "$run" ] && [ "$run" = "${VERIFY_RUN:-}" ]; then
    [ -n "${2:-}" ] || return 0
    echo "taking over the app of your own verify run $run on $1 (pid $pid)" >&2
  elif [ "$idle" -ge "$verify_lease_minutes" ]; then
    [ -n "${2:-}" ] || return 0
    echo "reclaimed $1 from verify run${run:+ $run} (pid $pid): no verify.sh call used it for $idle min, and the lease is $verify_lease_minutes min" >&2
  else
    stop="SIM=$1 ${run:+VERIFY_RUN=$run }$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/.agents/skills/verify/verify.sh stop"
    echo "a verify run${run:+ $run} owns the app on $1 (pid $pid), last used $idle min ago; a claim takes it once it goes $verify_lease_minutes min unused. If it is yours, ${run:+rerun with VERIFY_RUN=$run or }run: $stop, else use another simulator" >&2
    exit 75
  fi
  # A Live Activity outlives its app's process, so a run launched with them on is uninstalled, as stop does.
  if [ -f "$dir/args" ] && ! grep -q -- -UITEST_DISABLE_LIVE_ACTIVITIES "$dir/args"; then
    xcrun simctl uninstall "$1" com.sunnypatel.WorkoutTracker || echo "could not uninstall the app on $1; a Live Activity run $run started may still be on it" >&2
  fi
  rm -f "$dir/pid" "$dir/args"
}

claim_sim() {
  local dir=/tmp/workout-verify-$1
  mkdir -p "$dir"
  exec 9>>"$dir/lock"
  sim_flock "$1" LOCK_EX
  printf '%s (pid %s)\n' "$2" "$$" > "$dir/lock"
  settle_run "$1"
  wait_until_clear "the host before taking $1" host_clear "$1"
  settle_run "$1" take
}

# Sets env knob NAME to its value, else DEFAULT; exits 2 unless that is a whole number of at least MIN.
host_knob() {
  local value
  eval "value=\${$1:-$2}"
  case $value in
    ''|*[!0-9]*) echo "$1 must be a whole number: $value" >&6; exit 2 ;;
  esac
  [ "$value" -ge "$3" ] || { echo "$1 must be at least $3: $value" >&6; exit 2; }
  eval "$1=\$value"
}

# Runs CHECK ARG... in this shell until it returns 0, so a lock CHECK takes stays held. A failing CHECK
# sets busy_reason. Says why on the first wait and once a minute. Every wait in one script shares one
# WORKOUT_ADMIT_WAIT, so the 75 arrives inside the Bash tool's ten minutes, last poll included.
wait_until_clear() {
  local what=$1 waited said=-60
  shift
  : "${host_wait_start:=$(date +%s)}"
  while ! "$@"; do
    waited=$(($(date +%s) - host_wait_start))
    if [ "$waited" -ge "$WORKOUT_ADMIT_WAIT" ]; then
      echo "gave up after $waited s waiting for $what: $busy_reason" >&6
      exit 75
    fi
    if [ $((waited - said)) -ge 60 ]; then
      echo "waiting up to $WORKOUT_ADMIT_WAIT s for $what: $busy_reason" >&6
      said=$waited
    fi
    sleep 2
  done
  [ "$said" -lt 0 ] || echo "went ahead after $(($(date +%s) - host_wait_start)) s" >&6
}

load_clear() {
  local load
  load=$(sysctl -n vm.loadavg 2>/dev/null | awk '{ print $2 }') || true
  [ -n "$load" ] && awk -v load="$load" -v limit="$1" 'BEGIN { exit !(load > limit) }' || return 0
  busy_reason="the 1-minute load is $load, over $1 (WORKOUT_LOAD_LIMIT)"
  return 1
}

# Admits a claim on UDID while the load and the booted count leave room, and boots UDID if it is shut
# down. One claim at a time decides and boots, so the next one counts the simulator this one booted.
host_clear() {
  local listing counts others own rc=1
  load_clear "$WORKOUT_LOAD_LIMIT" || return 1
  exec 7>>"$host_lock_dir/admit"
  if ! try_flock 7 LOCK_EX 20; then
    exec 7>&-
    busy_reason="another claim is being admitted (lsof $host_lock_dir/admit lists it)"
    return 1
  fi
  if ! listing=$(xcrun simctl list devices available -j 2>&1); then
    busy_reason="xcrun simctl list devices failed: $listing"
  elif ! counts=$(printf %s "$listing" | UDID="$1" python3 -c '
import json, os, sys
devices = [d for ds in json.load(sys.stdin)["devices"].values() for d in ds]
mine = [d.get("state") for d in devices if d["udid"] == os.environ["UDID"]]
print(sum(d.get("state") in ("Booted", "Booting") and d["udid"] != os.environ["UDID"] for d in devices), *mine[:1])' 2>&1); then
    busy_reason="xcrun simctl list devices printed no device list: $counts"
  else
    read -r others own <<< "$counts"
    if [ "$others" -ge "$WORKOUT_SIM_CAP" ]; then
      busy_reason="$others other simulators are booted, at the cap of $WORKOUT_SIM_CAP (WORKOUT_SIM_CAP)"
    else
      [ "${own:-}" != Shutdown ] || xcrun simctl boot "$1" 7>&- 9>&- || exit
      rc=0
    fi
  fi
  exec 7>&-
  return $rc
}

take_build_slot() {
  local slot i=0 holders=
  while [ $((i += 1)) -le "$WORKOUT_BUILD_SLOTS" ]; do
    slot=$host_lock_dir/build-$i
    exec 8>>"$slot"
    if try_flock 8 LOCK_EX 1; then
      printf '%s (pid %s)\n' "${0##*/}" "$$" > "$slot"
      return 0
    fi
    exec 8>&-
    holders="$holders${holders:+, }$(cat "$slot")"
  done
  busy_reason="all $WORKOUT_BUILD_SLOTS build slots are taken (WORKOUT_BUILD_SLOTS): $holders; lsof $host_lock_dir/build-* lists every process holding one"
  return 1
}

# Runs COMMAND in one of the host's build slots. The command inherits the slot's fd, so the xcodebuild
# of a killed script keeps loading the host and keeps its slot until it exits.
with_build_slot() {
  local rc=0
  wait_until_clear "a build slot" take_build_slot
  "$@" 6>&- || rc=$?
  exec 8>&-
  return $rc
}

without_sim_lock() { "$@" 9>&-; }

require_sim_free() {
  [ -f "/tmp/workout-verify-$1/lock" ] || return 0
  sim_flock "$1" LOCK_SH 9<"/tmp/workout-verify-$1/lock"
}

host_knob WORKOUT_SIM_CAP 6 1
host_knob WORKOUT_LOAD_LIMIT 50 1
host_knob WORKOUT_ADMIT_WAIT 540 0
host_knob WORKOUT_BUILD_SLOTS 2 1
host_lock_dir=${WORKOUT_HOST_LOCK_DIR:-/tmp/workout-host-locks}
mkdir -p "$host_lock_dir"
