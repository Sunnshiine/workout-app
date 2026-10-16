# shellcheck shell=bash
exec 6>&2

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

# A Live Activity outlives its app's process, so only an uninstall ends one from outside the app.
launched_with_live_activities() {
  [ -f "$1/args" ] && ! grep -q -- -UITEST_DISABLE_LIVE_ACTIVITIES "$1/args"
}

is_fixture_launch() {
  case $(ps -p "$1" -o args= 2>/dev/null) in *-UITEST_FIXTURE*) return 0 ;; esac
  return 1
}

require_lease() {
  local dir=/tmp/workout-verify-$1 owner run reclaimer idle
  owner=$(cat "$dir/run" 2>/dev/null) || true
  run=${VERIFY_RUN:-$owner}
  if [ -n "$run" ] && reclaimer=$(cat "$dir/reclaimed.$run" 2>/dev/null); then
    echo "run $run was reclaimed by $reclaimer; launch again: SIM=$1 ${VERIFY_RUN:+VERIFY_RUN=$run }$0 launch <fixture>" >&2
    exit 75
  fi
  [ -f "$dir/pid" ] && [ "$run" = "$owner" ] || return 0
  if [ -z "${VERIFY_RUN:-}" ]; then
    idle=$(idle_minutes "$dir/pid")
    [ -n "$idle" ] || return 0
    if [ "$idle" -ge "$WORKOUT_LEASE_MINUTES" ]; then
      is_fixture_launch "$(cat "$dir/pid" 2>/dev/null)" \
        && echo "the lease of verify run${run:+ $run} on $1 expired: last renewed $idle min ago, and the lease is $WORKOUT_LEASE_MINUTES min, so a claim may take its app${run:+; if the run is yours, name it with VERIFY_RUN=$run to keep it}" >&2
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
  elif [ "$idle" -ge "$WORKOUT_LEASE_MINUTES" ]; then
    [ -n "${2:-}" ] || return 0
    echo "reclaimed $1 from verify run${run:+ $run} (pid $pid): its lease was last renewed $idle min ago, and the lease is $WORKOUT_LEASE_MINUTES min" >&2
    abandoned=1
  else
    stop="SIM=$1 ${run:+VERIFY_RUN=$run }$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/.agents/skills/verify/verify.sh stop"
    echo "a verify run${run:+ $run} owns the app on $1 (pid $pid), last used $idle min ago; a claim takes it once it goes $WORKOUT_LEASE_MINUTES min unused. If it is yours, ${run:+rerun with VERIFY_RUN=$run or }run: $stop, else use another simulator" >&2
    exit 75
  fi
  if [ -n "$abandoned" ]; then
    [ -z "$run" ] || printf '%s%s (pid %s) at %s\n' "$2" "${VERIFY_RUN:+ of run $VERIFY_RUN}" "$$" "$(date '+%Y-%m-%d %H:%M:%S')" \
      > "$dir/reclaimed.$run"
    xcrun simctl terminate "$1" com.sunnypatel.WorkoutTracker 8>&- 9>&- 2>/dev/null || true
  fi
  if launched_with_live_activities "$dir"; then
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
  settle_run "$udid" "$who"
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

wait_until_clear() {
  local what=$1 start waited said=-60
  shift
  start=$(date +%s)
  while ! "$@"; do
    waited=$(($(date +%s) - start))
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
  [ "$said" -lt 0 ] || echo "went ahead after $(($(date +%s) - start)) s" >&6
}

# Linux has neither kern.memorystatus_level nor vm.loadavg, so there neither holds anything.
mem_clear() {
  local reading
  [ "$WORKOUT_MEM_FLOOR" -gt 0 ] || return 0
  if ! reading=$(PATH=$PATH:/usr/sbin sysctl -n kern.memorystatus_level 2>&1); then
    [ "$(uname)" = Darwin ] || return 0
    busy_reason="sysctl -n kern.memorystatus_level failed: $reading"
    return 1
  fi
  case $reading in
    ''|*[!0-9]*) busy_reason="sysctl -n kern.memorystatus_level printed no free-memory percent: $reading" ;;
    *) [ "$reading" -lt "$WORKOUT_MEM_FLOOR" ] || return 0
      busy_reason="free memory is $reading%, under the floor of $WORKOUT_MEM_FLOOR% (WORKOUT_MEM_FLOOR)" ;;
  esac
  return 1
}

load_clear() {
  local reading now rc=0
  if ! reading=$(PATH=$PATH:/usr/sbin sysctl -n vm.loadavg 2>&1); then
    [ "$(uname)" = Darwin ] || return 0
    busy_reason="sysctl -n vm.loadavg failed: $reading"
    return 1
  fi
  read -r _ now _ <<< "$reading"
  awk -v now="$now" -v limit="$1" 'BEGIN { if (now !~ /^[0-9]+(\.[0-9]+)?$/) exit 3; exit (now + 0 > limit + 0) }' || rc=$?
  case $rc in
    0) return 0 ;;
    1) busy_reason="the 1-minute load is $now, over $1 (WORKOUT_LOAD_LIMIT)" ;;
    3) busy_reason="sysctl -n vm.loadavg printed no 1-minute load: $reading" ;;
    *) busy_reason="awk could not compare the 1-minute load $now with $1 (exit $rc)" ;;
  esac
  return 1
}

sim_states() {
  local counts
  if ! counts=$(exec 7>&- 8>&- 9>&-; UDID="$1" exec python3 -c '
import json, os, subprocess, sys
def fail(reason):
    print(reason)
    sys.exit(1)
listing = subprocess.run(["xcrun", "simctl", "list", "devices", "available", "-j"], capture_output=True, text=True)
if listing.returncode:
    fail("xcrun simctl list devices failed: " + listing.stderr.strip())
try:
    devices = [d for ds in json.loads(listing.stdout)["devices"].values() for d in ds]
except Exception as error:
    fail("xcrun simctl list devices printed no device list: %r" % error)
mine = [d.get("state") for d in devices if d["udid"] == os.environ["UDID"]]
print(sum(d.get("state") in ("Booted", "Booting") and d["udid"] != os.environ["UDID"] for d in devices), *mine[:1])' \
    2>/dev/null); then
    busy_reason=${counts:-python3 could not count the booted simulators}
    return 1
  fi
  read -r others own <<< "$counts"
}

admit_claim() {
  local udid=$1 build=$2 others own rc=1
  mem_clear || return 1
  host_room "$udid" || return 1
  if [ "$own" != Shutdown ]; then
    [ "$build" = 0 ] || take_build_slot
    return
  fi
  [ "$build" = 0 ] || build_slot_free || return 1
  exec 7>>"$host_lock_dir/admit"
  if ! try_flock 7 LOCK_EX 1; then
    busy_reason="another claim is booting a simulator (lsof $host_lock_dir/admit lists it)"
  elif { [ "$build" = 0 ] || take_build_slot; } && host_room "$udid"; then
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
# them all at once. simctl boot fails on a device another claim already started, so a failed boot
# rereads the state.
boot_sim() {
  local err
  err=$(exec 7>&- 8>&- 9>&-; exec xcrun simctl boot "$1" 2>&1 >/dev/null) && return
  if sim_states "$1"; then
    case ${own:-} in Booted|Booting) return ;; esac
  fi
  echo "could not boot $1: $err" >&6
  exit 70
}

take_build_slot() {
  local slot i=0 tries_past_a_probe=3
  while [ $((i += 1)) -le "$WORKOUT_BUILD_SLOTS" ]; do
    slot=$host_lock_dir/build-$i
    exec 8>>"$slot"
    if try_flock 8 LOCK_EX "$tries_past_a_probe"; then
      printf '%s (pid %s)\n' "${0##*/}" "$$" > "$slot"
      build_slot=$slot
      return 0
    fi
    exec 8>&-
  done
  slots_taken
}

build_slot_free() {
  local i=0
  while [ $((i += 1)) -le "$WORKOUT_BUILD_SLOTS" ]; do
    exec 8>>"$host_lock_dir/build-$i"
    try_flock 8 LOCK_SH 1 && { exec 8>&-; return 0; }
    exec 8>&-
  done
  slots_taken
}

slots_taken() {
  local i=0 holders=
  while [ $((i += 1)) -le "$WORKOUT_BUILD_SLOTS" ]; do
    holders="$holders${holders:+, }$(cat "$host_lock_dir/build-$i")"
  done
  busy_reason="all $WORKOUT_BUILD_SLOTS build slots are taken (WORKOUT_BUILD_SLOTS): $holders; lsof $host_lock_dir/build-* lists every process holding one"
  return 1
}

drop_build_slot() {
  exec 8>&-
  build_slot=
}

admit_build() { mem_clear && take_build_slot; }

with_build_slot() {
  local rc=0
  [ -n "${build_slot:-}" ] || wait_until_clear "a build slot" admit_build
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
host_knob WORKOUT_MEM_FLOOR 25 0
host_knob WORKOUT_ADMIT_WAIT 540 0
host_knob WORKOUT_BUILD_SLOTS 2 1
host_knob WORKOUT_LEASE_MINUTES 60 1
host_lock_dir=${WORKOUT_HOST_LOCK_DIR:-/tmp/workout-host-locks}
mkdir -p "$host_lock_dir"
