# shellcheck shell=bash
exec 6>&2

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

# Simulators come only from a Simlock lease (ADR-0024). The grant's empty environment puts the device in
# Xcode's own set, so xcodebuild and xcrun simctl reach it by UDID.
need_simlock() {
  command -v simlock >/dev/null && return
  echo "simlock is not on PATH, and every simulator here comes from a Simlock lease; see .agents/skills/simlock/SKILL.md" >&6
  exit 78
}

# Prints "UDID LEASE-ID TTL-MS SECONDS-LEFT" for the lease the caller's Simlock identity holds, or
# nothing. With a UDID, exits 2 unless that lease is on that device; 78 without simlock, 70 when it fails.
own_lease() {
  local who status
  need_simlock
  who=$(simlock whoami 7>&- 8>&- 9>&-) && status=$(simlock status --json 7>&- 8>&- 9>&-) \
    || { echo "simlock whoami or status failed; run simlock doctor" >&6; exit 70; }
  printf '%s' "$status" | WHO="$who" UDID=$(printf %s "${1:-}" | tr '[:lower:]' '[:upper:]') python3 -c '
import json, os, sys, time
who = next(line.split(":", 1)[1].strip() for line in os.environ["WHO"].splitlines() if line.startswith("Principal:"))
status = json.load(sys.stdin)
udids = {d["id"]: d.get("driverDeviceId", "").upper() for d in status["devices"]}
mine = [(udids.get(l["deviceId"], "?"), l) for l in status["leases"] if l["requesterId"] == who]
want = os.environ["UDID"]
for udid, lease in mine:
    if not want or udid == want:
        print(udid, lease["id"], lease["ttlMs"], int(lease["ttlDeadline"] / 1000 - time.time()))
        sys.exit(0)
if want:
    held = mine[0][0] if mine else "none"
    print(f"{want} is not the simulator of a Simlock lease you hold (yours: {held}); lease one first, see .agents/skills/simlock/SKILL.md", file=sys.stderr)
    sys.exit(2)'
}

# A device a lease hands over may have served another agent, so its run state is not ours.
forget_runs() {
  rm -f "/tmp/workout-verify-$1"/{pid,args,run,unnamed} "/tmp/workout-verify-$1"/refused.* "/tmp/workout-verify-$1"/reclaimed.*
}

simlock_refusal() {
  local code=$1 said=$2
  case $code in
    10|11) echo "Simlock had no free $sim_device simulator within WORKOUT_ADMIT_WAIT ($WORKOUT_ADMIT_WAIT s); the host is full, so retry later" >&6; exit 75 ;;
    13) echo "your Simlock identity already holds a lease ($(own_lease | awk '{print "simulator " $1 ", lease " $2}')); pass that simulator with --sim or SIM=, or simlock release its lease first" >&6; exit 75 ;;
    14) echo "Simlock took the lease back, so the simulator is gone; rerun to lease another" >&6; exit 69 ;;
    *) echo "simlock lease exited $code: ${said:-no message}" >&6; exit 70 ;;
  esac
}

# Takes a lease of its own, tied to this script's pid, so it ends with the script even under SIGKILL.
lease_sim() {
  local grant wait=(--timeout "${WORKOUT_ADMIT_WAIT}s") code
  need_simlock
  [ "$WORKOUT_ADMIT_WAIT" -gt 0 ] || wait=(--no-wait)
  lease_dir=$(mktemp -d "${TMPDIR:-/tmp}/workout-lease.XXXXXX")
  echo "leasing an $sim_device simulator on iOS $sim_runtime from Simlock" >&6
  (exec 7>&- 8>&- 9>&-; exec simlock lease --platform ios --device "$sim_device" --os "$sim_runtime" \
    "${wait[@]}" --bind-pid $$ >"$lease_dir/grant" 2>"$lease_dir/err") &
  lease_pid=$!
  until [ "$(wc -l < "$lease_dir/grant")" -ge 1 ]; do
    if ! kill -0 "$lease_pid" 2>/dev/null; then
      code=0
      wait "$lease_pid" || code=$?
      lease_pid=
      simlock_refusal "$code" "$(tail -n 1 "$lease_dir/err")"
    fi
    sleep 0.2
  done
  grant=$(python3 -c 'import json, sys; g = json.loads(open(sys.argv[1]).readline()); print(g["device"]["driverDeviceId"], g["lease"]["id"])' \
    "$lease_dir/grant") || { echo "simlock lease printed a grant this script cannot read: $(head -c 300 "$lease_dir/grant")" >&6; exit 70; }
  read -r sim lease_id <<< "$grant"
  forget_runs "$sim"
  echo "simulator $sim (Simlock lease $lease_id)" >&6
}

# Exits 69 when Simlock took the lease back while the script ran.
lease_kept() {
  local code=0
  [ -n "${lease_pid:-}" ] && ! kill -0 "$lease_pid" 2>/dev/null || return 0
  wait "$lease_pid" || code=$?
  lease_pid=
  simlock_refusal "$code" "$(tail -n 1 "$lease_dir/err")"
}

end_lease() {
  [ -z "${lease_dir:-}" ] || rm -rf "$lease_dir"
  [ -n "${lease_pid:-}" ] || return 0
  kill "$lease_pid" 2>/dev/null || true
  wait "$lease_pid" 2>/dev/null || true
  lease_pid=
}

# A verify run spans many calls, so its lease is detached, with a TTL of WORKOUT_LEASE_MINUTES that each
# call renews once half of it has passed. Sets sim to the lease's UDID, or to $1's, which must be the
# caller's own lease. With take, a caller holding no lease gets one; without, it is refused.
hold_lease() {
  local named=$1 take=${2:-} held id ttl left grant
  held=$(own_lease "$named") || exit
  if [ -n "$held" ]; then
    read -r sim id ttl left <<< "$held"
    [ $((left * 2000)) -ge "$ttl" ] || simlock lease renew "$id" >/dev/null 7>&- 8>&- 9>&- \
      || { echo "could not renew Simlock lease $id on $sim; lease again" >&6; exit 75; }
    return 0
  fi
  [ -n "$take" ] || { echo "you hold no Simlock lease; verify.sh launch <fixture> takes one" >&6; exit 2; }
  echo "leasing an $sim_device simulator on iOS $sim_runtime from Simlock for $WORKOUT_LEASE_MINUTES min, renewed by each verify call" >&6
  lease_dir=$(mktemp -d "${TMPDIR:-/tmp}/workout-lease.XXXXXX")
  simlock lease --platform ios --device "$sim_device" --os "$sim_runtime" --timeout "${WORKOUT_ADMIT_WAIT}s" \
    --detach --ttl "${WORKOUT_LEASE_MINUTES}m" >"$lease_dir/grant" 2>"$lease_dir/err" 7>&- 8>&- 9>&- \
    || simlock_refusal $? "$(tail -n 1 "$lease_dir/err")"
  grant=$(python3 -c 'import json, sys; g = json.loads(open(sys.argv[1]).readline()); print(g["device"]["driverDeviceId"], g["lease"]["id"])' \
    "$lease_dir/grant") || { echo "simlock lease printed a grant this script cannot read: $(head -c 300 "$lease_dir/grant")" >&6; exit 70; }
  read -r sim id <<< "$grant"
  rm -rf "$lease_dir"
  forget_runs "$sim"
  echo "simulator $sim (Simlock lease $id); verify.sh release gives it back" >&6
}

release_lease() {
  local held udid id
  held=$(own_lease "$1") || exit
  [ -n "$held" ] || { echo "you hold no Simlock lease"; return 0; }
  read -r udid id _ <<< "$held"
  simlock release "$id" >/dev/null 7>&- 8>&- 9>&- && echo "released Simlock lease $id on $udid"
}

# The simulator a run drives: the named one, which must be the caller's own lease, else a lease of its own.
claim_sim() {
  local named=$1 who=$2 build=${3:-0} dir
  if [ -n "$named" ]; then
    sim=$(own_lease "$named" | awk '{print $1}') || exit
  else
    lease_sim
  fi
  dir=/tmp/workout-verify-$sim
  mkdir -p "$dir"
  exec 9>>"$dir/lock"
  sim_flock "$sim" LOCK_EX
  claimed_sim=$sim
  printf '%s (pid %s)\n' "$who" "$$" > "$dir/lock"
  settle_run "$sim"
  wait_until_clear "the host before running on $sim" admit_claim "$build"
  settle_run "$sim" "$who"
  simlock simctl bootstatus "$sim" -b >/dev/null 7>&- 8>&- 9>&- || { echo "simulator $sim did not boot" >&6; exit 69; }
}

admit_claim() { mem_clear && { [ "$1" = 0 ] || admit_build; }; }

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

# For the claimer's EXIT trap.
end_claim() { end_lease; }

host_knob() {
  local name=$1 default=$2 min=$3 value
  eval "value=\${$name:-$default}"
  case $value in
    ''|*[!0-9]*) echo "$name must be a whole number: $value" >&6; exit 2 ;;
  esac
  [ "$value" -ge "$min" ] || { echo "$name must be at least $min: $value" >&6; exit 2; }
  eval "$name=\$value"
}

# A build queue that moves is not stuck: the budget restarts each time a build slot changes hands.
wait_until_clear() {
  local what=$1 begun start waited said=-60 holders_seen=
  shift
  begun=$(date +%s) start=$begun
  while slot_holders=; ! "$@"; do
    if [ -n "$slot_holders" ] && [ "$slot_holders" != "$holders_seen" ]; then
      [ -z "$holders_seen" ] || start=$(date +%s)
      holders_seen=$slot_holders
    fi
    waited=$(($(date +%s) - begun))
    if [ $(($(date +%s) - start)) -ge "$WORKOUT_ADMIT_WAIT" ]; then
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

# The volumes a build writes: the checkout's .build and, under HOME, DerivedData and the simulators.
disk_clear() {
  local reading free path
  [ "$WORKOUT_DISK_FLOOR" -gt 0 ] || return 0
  for path in "$sim_lock_checkout" "$HOME"; do
    if ! reading=$(df -Pk "$path" 2>&1); then
      busy_reason="df -Pk $path failed: $reading"
      return 1
    fi
    free=$(awk 'NR == 2 && $4 ~ /^[0-9]+$/ { print int($4 / 1024) }' <<< "$reading")
    [ -n "$free" ] || { busy_reason="df -Pk $path printed no free space: $reading"; return 1; }
    [ "$free" -lt "$WORKOUT_DISK_FLOOR" ] || continue
    busy_reason="free disk is $free MB on the volume holding $path, under the floor of $WORKOUT_DISK_FLOOR MB (WORKOUT_DISK_FLOOR) a build needs"
    return 1
  done
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

slots_taken() {
  local i=0 holders=
  while [ $((i += 1)) -le "$WORKOUT_BUILD_SLOTS" ]; do
    holders="$holders${holders:+, }$(cat "$host_lock_dir/build-$i")"
  done
  slot_holders=$holders
  busy_reason="all $WORKOUT_BUILD_SLOTS build slots are taken (WORKOUT_BUILD_SLOTS): $holders; lsof $host_lock_dir/build-* lists every process holding one"
  return 1
}

drop_build_slot() {
  exec 8>&-
  build_slot=
}

admit_build() { mem_clear && disk_clear && take_build_slot; }

with_build_slot() {
  local rc=0
  [ -n "${build_slot:-}" ] || wait_until_clear "a build slot" admit_build
  "$@" 6>&- || rc=$?
  drop_build_slot
  return $rc
}

require_sim_free() {
  [ -f "/tmp/workout-verify-$1/lock" ] || return 0
  sim_flock "$1" LOCK_SH 9<"/tmp/workout-verify-$1/lock"
}

host_knob WORKOUT_MEM_FLOOR 25 0
host_knob WORKOUT_DISK_FLOOR 5120 0
host_knob WORKOUT_ADMIT_WAIT 540 0
host_knob WORKOUT_BUILD_SLOTS 2 1
host_knob WORKOUT_LEASE_MINUTES 60 1
sim_device='iPhone 17 Pro'
sim_runtime=27.0
sim_lock_checkout=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
host_lock_dir=${WORKOUT_HOST_LOCK_DIR:-/tmp/workout-host-locks}
mkdir -p "$host_lock_dir"
