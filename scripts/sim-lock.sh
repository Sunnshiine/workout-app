# shellcheck shell=bash
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

renew_lease() {
  local dir=/tmp/workout-verify-$1 run idle
  [ -f "$dir/pid" ] || return 0
  run=$(cat "$dir/run" 2>/dev/null) || true
  if [ -n "${VERIFY_RUN:-}" ]; then
    [ "$VERIFY_RUN" = "$run" ] || return 0
  else
    idle=$(idle_minutes "$dir/pid")
    [ -n "$idle" ] || return 0
    if [ "$idle" -ge "$verify_lease_minutes" ]; then
      is_fixture_launch "$(cat "$dir/pid" 2>/dev/null)" \
        && echo "the lease of verify run${run:+ $run} on $1 expired: last renewed $idle min ago, and the lease is $verify_lease_minutes min, so a claim may take its app${run:+; if the run is yours, name it with VERIFY_RUN=$run to keep it}" >&2
      return 0
    fi
  fi
  touch -c "$dir/pid"
}

idle_minutes() {
  python3 -c 'import os, sys, time
try: print(int((time.time() - os.stat(sys.argv[1]).st_mtime) // 60))
except FileNotFoundError: pass' "$1"
}

settle_run() {
  local dir=/tmp/workout-verify-$1 pid run idle stop abandoned=
  pid=$(cat "$dir/pid" 2>/dev/null) && is_fixture_launch "$pid" || return 0
  idle=$(idle_minutes "$dir/pid")
  [ -n "$idle" ] || return 0
  run=$(cat "$dir/run" 2>/dev/null) || true
  if [ -n "$run" ] && [ "$run" = "${VERIFY_RUN:-}" ]; then
    [ -n "${2:-}" ] || return 0
    echo "taking over the app of your own verify run $run on $1 (pid $pid)" >&2
  elif [ "$idle" -ge "$verify_lease_minutes" ]; then
    [ -n "${2:-}" ] || return 0
    echo "reclaimed $1 from verify run${run:+ $run} (pid $pid): its lease was last renewed $idle min ago, and the lease is $verify_lease_minutes min" >&2
    abandoned=1
  else
    stop="SIM=$1 ${run:+VERIFY_RUN=$run }$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/.agents/skills/verify/verify.sh stop"
    echo "a verify run${run:+ $run} owns the app on $1 (pid $pid), last used $idle min ago; a claim takes it once it goes $verify_lease_minutes min unused. If it is yours, ${run:+rerun with VERIFY_RUN=$run or }run: $stop, else use another simulator" >&2
    exit 75
  fi
  # A Live Activity outlives its app's process, so a run launched with them on is uninstalled, as stop does.
  if [ -f "$dir/args" ] && ! grep -q -- -UITEST_DISABLE_LIVE_ACTIVITIES "$dir/args"; then
    xcrun simctl uninstall "$1" com.sunnypatel.WorkoutTracker 8>&- 9>&- || echo "could not uninstall the app on $1; a Live Activity run $run started may still be on it" >&2
  fi
  [ -z "$abandoned" ] || rm -f "$dir/pid" "$dir/args"
}

claim_sim() {
  local udid=$1 who=$2 build=${3:-0} dir=/tmp/workout-verify-$1
  mkdir -p "$dir"
  exec 9>>"$dir/lock"
  sim_flock "$udid" LOCK_EX
  printf '%s (pid %s)\n' "$who" "$$" > "$dir/lock"
  settle_run "$udid"
  wait_until_clear "the host before taking $udid" admit_claim "$udid" "$build"
  settle_run "$udid" take
}

host_knob() {
  local name=$1 default=$2 min=$3 value
  eval "value=\${$name:-$default}"
  case $value in
    ''|*[!0-9]*) echo "$name must be a whole number: $value" >&6; exit 2 ;;
  esac
  [ "$value" -ge "$min" ] || { echo "$name must be at least $min: $value" >&6; exit 2; }
  eval "$name=\$value"
}

# Every wait in one script shares one WORKOUT_ADMIT_WAIT, so the 75 arrives inside the Bash tool's
# ten-minute timeout.
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
    sleep 2 7>&- 8>&- 9>&-
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

sim_states() {
  local listing=$host_lock_dir/list-$$.json counts err=$host_lock_dir/list-$$.err rc=0
  if ! xcrun simctl list devices available -j 7>&- 8>&- 9>&- >"$listing" 2>"$err"; then
    busy_reason="xcrun simctl list devices failed: $(cat "$err")"
    rc=1
  elif ! counts=$(UDID="$1" python3 -c '
import json, os, sys
devices = [d for ds in json.load(sys.stdin)["devices"].values() for d in ds]
mine = [d.get("state") for d in devices if d["udid"] == os.environ["UDID"]]
print(sum(d.get("state") in ("Booted", "Booting") and d["udid"] != os.environ["UDID"] for d in devices), *mine[:1])' <"$listing" 2>"$err"); then
    busy_reason="xcrun simctl list devices printed no device list: $(tail -1 "$err")"
    rc=1
  else
    read -r others own <<< "$counts"
  fi
  rm -f "$listing" "$err"
  return $rc
}

admit_claim() {
  local udid=$1 build=$2 others own rc=1
  load_clear "$WORKOUT_LOAD_LIMIT" || return 1
  host_room "$udid" || return 1
  [ "$build" = 0 ] || take_build_slot || return 1
  [ "$own" = Shutdown ] || return 0
  exec 7>>"$host_lock_dir/admit"
  if ! try_flock 7 LOCK_EX 20; then
    busy_reason="another claim is booting a simulator (lsof $host_lock_dir/admit lists it)"
  elif host_room "$udid"; then
    [ "$own" != Shutdown ] || boot_sim "$udid"
    rc=0
  fi
  exec 7>&-
  [ $rc = 0 ] || drop_build_slot
  return $rc
}

host_room() {
  sim_states "$1" || return 1
  case ${own:-} in
    "Shutting Down") busy_reason="$1 is shutting down" ;;
    Shutdown) [ "$others" -ge "$WORKOUT_SIM_CAP" ] || return 0
      busy_reason="$others other simulators are booted, at the cap of $WORKOUT_SIM_CAP (WORKOUT_SIM_CAP)" ;;
    *) return 0 ;;
  esac
  return 1
}

# A flock is held by every process sharing its fd, so simctl gets no lock fd and a killed claimer frees
# them all at once. simctl boot exits 149 on a device another booter already started.
boot_sim() {
  local err=$host_lock_dir/boot-$$.err
  xcrun simctl boot "$1" 7>&- 8>&- 9>&- 2>"$err" && { rm -f "$err"; return; }
  if sim_states "$1"; then
    case ${own:-} in Booted|Booting) rm -f "$err"; return ;; esac
  fi
  echo "could not boot $1: $(cat "$err")" >&6
  rm -f "$err"
  exit 70
}

take_build_slot() {
  local slot i=0 holders=
  while [ $((i += 1)) -le "$WORKOUT_BUILD_SLOTS" ]; do
    slot=$host_lock_dir/build-$i
    exec 8>>"$slot"
    if try_flock 8 LOCK_EX 1; then
      printf '%s (pid %s)\n' "${0##*/}" "$$" > "$slot"
      build_slot=$slot
      return 0
    fi
    exec 8>&-
    holders="$holders${holders:+, }$(cat "$slot")"
  done
  busy_reason="all $WORKOUT_BUILD_SLOTS build slots are taken (WORKOUT_BUILD_SLOTS): $holders; lsof $host_lock_dir/build-* lists every process holding one"
  return 1
}

drop_build_slot() {
  exec 8>&-
  build_slot=
}

with_build_slot() {
  local rc=0
  [ -n "${build_slot:-}" ] || wait_until_clear "a build slot" take_build_slot
  "$@" 6>&- || rc=$?
  drop_build_slot
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
