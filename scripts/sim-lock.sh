# shellcheck shell=bash
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

sim_flock() {
  local lock=/tmp/workout-verify-$1/lock rc=0
  python3 -c 'import fcntl, sys, time
for attempt in range(10):
    if attempt: time.sleep(0.05)
    try: fcntl.flock(9, getattr(fcntl, sys.argv[1]) | fcntl.LOCK_NB); break
    except BlockingIOError: pass
else: sys.exit(75)' "$2" || rc=$?
  [ $rc -ne 75 ] || echo "$1 is held by a $(cat "$lock"); wait for it to finish, or use another simulator (lsof $lock lists every process holding it)" >&2
  [ $rc -eq 0 ] || exit $rc
}

is_fixture_launch() {
  case $(ps -p "$1" -o args= 2>/dev/null) in *-UITEST_FIXTURE*) return 0 ;; esac
  return 1
}

claim_sim() {
  local dir=/tmp/workout-verify-$1 pid run stop
  mkdir -p "$dir"
  exec 9>>"$dir/lock"
  sim_flock "$1" LOCK_EX
  printf '%s (pid %s)\n' "$2" "$$" > "$dir/lock"
  pid=$(cat "$dir/pid" 2>/dev/null) && is_fixture_launch "$pid" || return 0
  run=$(cat "$dir/run" 2>/dev/null) || true
  stop="SIM=$1 ${run:+VERIFY_RUN=$run }$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/.claude/skills/verify/verify.sh stop"
  echo "a verify run${run:+ $run} owns the app on $1 (pid $pid); if it is yours, run: $stop, else use another simulator" >&2
  exit 75
}

without_sim_lock() { "$@" 9>&-; }

require_sim_free() {
  [ -f "/tmp/workout-verify-$1/lock" ] || return 0
  sim_flock "$1" LOCK_SH 9<"/tmp/workout-verify-$1/lock"
}
