#!/bin/bash
set -uo pipefail

script_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
root=$(mktemp -d) || exit 3
sim=HOST-ADMISSION-TEST-$$
sim2=$sim-2
state=/tmp/workout-verify-$sim
apps=()
cleanup() {
    touch "$root/release"
    [ ${#apps[@]} -eq 0 ] || { kill "${apps[@]}"; wait "${apps[@]}"; } 2>/dev/null
    rm -rf "$root" "$state" "/tmp/workout-verify-$sim2"
}
trap cleanup EXIT
repo=$root/repo
products=$root/home/Library/Developer/Xcode/DerivedData/WorkoutTracker-stub/Build/Products
mkdir -p "$repo/scripts" "$repo/.agents/skills/verify" "$root/bin" "$products"
cp "$script_dir/../test-sim.sh" "$script_dir/../sim-lock.sh" "$script_dir/../build-slot.sh" \
    "$script_dir/../test-log-summary.awk" "$repo/scripts/"
cp "$script_dir/../../.agents/skills/verify/verify.sh" "$repo/.agents/skills/verify/"
touch "$products/../../info.plist" "$products/WorkoutTracker_iphonesimulator27.0-arm64.xctestrun"
mkdir -p "$products/Debug-iphonesimulator/WorkoutTracker.app" "$repo/.build/verify/node_modules/xcodebuildmcp/bundled"
printf '#!/bin/sh\n' > "$repo/.build/verify/node_modules/xcodebuildmcp/bundled/axe"
chmod +x "$repo/.build/verify/node_modules/xcodebuildmcp/bundled/axe"
git -C "$repo" init -q && git -C "$repo" add -A && git -C "$repo" -c user.name=test -c user.email=test@example.com commit -qm test
pass=0
fail=0

ok()  { pass=$((pass + 1)); printf '  ok   %s\n' "$1"; }
bad() { fail=$((fail + 1)); printf '  FAIL %s\n' "$1"; }
refusal() { tail -1 "$root/err" | sed 's/^gave up after [0-9]* s/gave up after N s/'; }
expect() { if [ "$2" = "$3" ]; then ok "$1"; else bad "$1"; printf '    got:  %s\n    want: %s\n' "$2" "$3"; fi; }

cat >"$root/bin/plutil" <<STUB
#!/bin/sh
echo "$repo/WorkoutTracker.xcodeproj"
STUB
cat >"$root/bin/npm" <<'STUB'
#!/bin/sh
exit 1
STUB
cat >"$root/bin/xcrun" <<STUB
#!/bin/sh
if [ "\$*" != "simctl list devices available -j" ]; then
    echo "\$*" >> "$root/xcrun-calls"
    case "\$*" in
      "simctl boot "*)
        if [ -n "\${STUB_BOOT_HOLD:-}" ]; then
            touch "$root/boot-holding"
            i=0
            while [ ! -f "$root/release" ] && [ \$i -lt 300 ]; do sleep 0.1; i=\$((i + 1)); done
        fi
        [ -z "\${STUB_BOOT_FAILS:-}" ] || { case \$STUB_BOOT_FAILS in raced) echo "\$3" >> "$root/booted" ;;
            booting) echo "\$3" >> "$root/booting" ;; esac
            echo "Unable to boot device in current state: Booted" >&2; exit 149; }
        echo "\$3" >> "$root/booted" ;;
      "simctl list devices booted") sed 's/.*/    iPhone 17 Pro (&) (Booted)/' "$root/booted" 2>/dev/null ;;
      "simctl launch "*) echo "com.sunnypatel.WorkoutTracker: 999999" ;;
      "simctl get_app_container "*) echo "$products/Debug-iphonesimulator/WorkoutTracker.app" ;;
    esac
    exit 0
fi
[ -z "\${STUB_LIST_WARNING:-}" ] || echo "objc[4242]: Class SimDeviceSet is implemented in both CoreSimulator and CoreSimulatorUtilities" >&2
echo call >> "$root/list-calls"
[ "\$(wc -l < "$root/list-calls")" -lt "\${STUB_LIST_GARBAGE_FROM_CALL:-1000}" ] || { echo "not a device list"; exit 0; }
if [ "\$(wc -l < "$root/list-calls")" -eq "\${STUB_SLOW_LIST_CALL:-0}" ]; then touch "$root/listing-slowly"; sleep 3; fi
if [ "\$(wc -l < "$root/list-calls")" -eq "\${STUB_PROBE_ON_LIST_CALL:-0}" ]; then
    python3 -c 'import fcntl, sys, time
slot = open(sys.argv[1], "a")
fcntl.flock(slot, fcntl.LOCK_SH)
open(sys.argv[2], "w").close()
time.sleep(0.12)' "$root/locks/build-1" "$root/probing" 7>&- 8>&- 9>&- &
    while [ ! -f "$root/probing" ]; do sleep 0.01; done
fi
if [ "\$(wc -l < "$root/list-calls")" -gt "\${STUB_LIST_OK_CALLS:-1000}" ]; then
    echo "An error was encountered processing the command (domain=com.apple.CoreSimulator.SimError, code=405)" >&2
    exit 1
fi
python3 -c 'import json, os, sys
others = [{"udid": "OTHER-%d" % i, "state": "Booted", "name": "iPad Pro"} for i in range(int(sys.argv[1]))]
shut = sys.argv[2].split()
booted = open(sys.argv[3]).read().split() if os.path.exists(sys.argv[3]) else []
booting = open(sys.argv[4]).read().split() if os.path.exists(sys.argv[4]) else []
ours = ["$sim"] + [u for u in shut if u != "$sim"]
stopping = os.environ.get("STUB_SHUTTING_DOWN", "").split()
state = lambda u: "Shutting Down" if u in stopping else "Booting" if u in booting else "Shutdown" if u in shut and u not in booted else "Booted"
print(json.dumps({"devices": {"iOS-27-0": others + [
    {"udid": u, "state": state(u), "name": "iPhone 17 Pro"} for u in ours]}}))' \
    "\${STUB_BOOTED_OTHERS:-0}" "\${STUB_SHUTDOWN:-}" "$root/booted" "$root/booting"
STUB
cat >"$root/bin/sysctl" <<STUB
#!/bin/sh
[ -z "\${STUB_SYSCTL_FAILS:-}" ] || { echo "sysctl: unknown oid '\$2'" >&2; exit 1; }
if [ "\$2" = kern.memorystatus_level ]; then
    echo call >> "$root/mem-calls"
    if [ "\$(wc -l < "$root/mem-calls")" -gt "\${STUB_LOW_MEM_CALLS:-1000}" ]; then echo 80; else echo "\${STUB_MEM_LEVEL:-80}"; fi
    exit 0
fi
echo call >> "$root/sysctl-calls"
if [ "\$(wc -l < "$root/sysctl-calls")" -gt "\${STUB_BUSY_CALLS:-1000}" ]; then echo "{ 1.00 1.00 1.00 }"; else echo "{ \${STUB_LOAD:-1.00} 1.00 1.00 }"; fi
STUB
cat >"$root/bin/xcodebuild" <<STUB
#!/bin/sh
echo "\$1" >> "$root/builds"
if [ -n "\${STUB_HOLD:-}" ]; then
    touch "$root/holding"
    i=0
    while [ ! -f "$root/release" ] && [ \$i -lt 300 ]; do sleep 0.1; i=\$((i + 1)); done
fi
echo "** BUILD FAILED **"
exit 65
STUB
chmod +x "$root/bin/"*
export HOME=$root/home PATH="$root/bin:$PATH" WORKOUT_HOST_LOCK_DIR=$root/locks
# shellcheck disable=SC2046
unset VERIFY_RUN SIM WORKOUT_LOAD_LIMIT $(sed -n 's/^host_knob \([A-Z_]*\) .*/\1/p' "$repo/scripts/sim-lock.sh")

reset() {
    rm -rf "$state" "/tmp/workout-verify-$sim2" "$root/builds" "$root/sysctl-calls" "$root/mem-calls" "$root/xcrun-calls" "$root/list-calls" \
        "$root/booted" "$root/booting" "$root/holding" "$root/boot-holding" "$root/release" "$root/listing-slowly" "$root/probing" \
        "$repo/.claude/work/evidence"
}
leftovers() {
    local file
    for file in "$root/locks"/*; do
        case ${file##*/} in admit|build-[0-9]*) ;; *) printf '%s ' "${file##*/}" ;; esac
    done
}
builds() { cat "$root/builds" 2>/dev/null | tr '\n' ' ' | sed 's/ $//'; }
test_sim() { "$repo/scripts/test-sim.sh" "$@" --sim "$sim" unit >"$root/out" 2>"$root/err"; }
verify() { SIM=$sim "$repo/.agents/skills/verify/verify.sh" "$@"; }
reclaim_note() { tail -1 "$root/err" | sed -E 's/\(pid [0-9]+\) at [0-9-]+ [0-9:]+;/(pid N) at T;/'; }
age_minutes() { python3 -c 'import os, sys, time; t = time.time() - int(sys.argv[2]) * 60; os.utime(sys.argv[1], (t, t))' "$1" "$2"; }
minutes_old() { python3 -c 'import os, sys, time; print(int((time.time() - os.stat(sys.argv[1]).st_mtime) // 60))' "$1"; }

own_the_app() {
    python3 -c 'import time; time.sleep(120)' -UITEST_FIXTURE &
    app=$!
    apps+=("$app")
    mkdir -p "$state"
    echo "$1" > "$state/run"
    echo "$app" > "$state/pid"
    echo "-UITEST_FIXTURE -UITEST_SESSION ${3--UITEST_DISABLE_LIVE_ACTIVITIES}" > "$state/args"
    age_minutes "$state/pid" "$2"
}

echo "lease"
reset; own_the_app abandoned-run 61
test_sim --no-build; status=$?
expect "a run unused for 61 min is reclaimed and the claim goes on" "$status $(builds)" "65 test-without-building"
expect "the reclaim names the run and its idle time" "$(head -1 "$root/err")" \
    "reclaimed $sim from verify run abandoned-run (pid $app): its lease was last renewed 61 min ago, and the lease is 60 min"
expect "the reclaim stops the abandoned run's app" "$(cat "$root/xcrun-calls" 2>/dev/null)" \
    "simctl terminate $sim com.sunnypatel.WorkoutTracker"
rm -f "$root/xcrun-calls"
VERIFY_RUN=abandoned-run verify stop >"$root/out" 2>"$root/err"; status=$?
expect "the reclaimed run's stop says who reclaimed it and when, and touches nothing" \
    "$status $(cat "$root/xcrun-calls" 2>/dev/null)$(cat "$root/out")$(reclaim_note)" \
    "75 run abandoned-run was reclaimed by test-sim.sh run (pid N) at T; launch again: SIM=$sim VERIFY_RUN=abandoned-run $repo/.agents/skills/verify/verify.sh launch <fixture>"
went=
for verb in doctor tree "find x" "tap --id x" "hold x" "type x" "swipe up" "shot s" "burst b" "axe describe-ui"; do
    read -ra argv <<< "$verb"
    VERIFY_RUN=abandoned-run verify "${argv[@]}" >/dev/null 2>"$root/err"; status=$?
    [ "$status $(reclaim_note)" = "75 run abandoned-run was reclaimed by test-sim.sh run (pid N) at T; launch again: SIM=$sim VERIFY_RUN=abandoned-run $repo/.agents/skills/verify/verify.sh launch <fixture>" ] \
        || went="$went${went:+, }$verb"
done
expect "every command that acts on the reclaimed run's app refuses the same way" "${went:-none went on}" "none went on"
verify shot s >/dev/null 2>"$root/err"; status=$?
expect "a command that names no run is the recorded run, so it refuses too and files no evidence" \
    "$status $(ls "$repo/.claude/work/evidence" 2>/dev/null)" "75 "
expect "and is told to launch a run of its own, not to take the reclaimed run's name" "$(reclaim_note)" \
    "run abandoned-run was reclaimed by test-sim.sh run (pid N) at T; launch again: SIM=$sim $repo/.agents/skills/verify/verify.sh launch <fixture>"
VERIFY_RUN=abandoned-run verify build >/dev/null 2>"$root/err"; status=$?
expect "build acts on no run's app, so the reclaimed run may still build" "$status $(builds)" "65 test-without-building build"

reset; own_the_app abandoned-run 61
echo "$sim" > "$root/booted"
VERIFY_RUN=lane-new verify launch session >/dev/null 2>"$root/err"; status=$?
expect "a launch reclaims the run's simulator, then starts its own run" "$status $(cat "$state/run")" "70 lane-new"
VERIFY_RUN=abandoned-run verify tree >/dev/null 2>"$root/err"; status=$?
expect "the reclaimed run is told which run reclaimed it" "$status $(reclaim_note)" \
    "75 run abandoned-run was reclaimed by verify.sh launch of run lane-new (pid N) at T; launch again: SIM=$sim VERIFY_RUN=abandoned-run $repo/.agents/skills/verify/verify.sh launch <fixture>"
VERIFY_RUN=lane-new verify tree >/dev/null 2>"$root/err"
expect "the reclaiming run goes on" "$(grep -c reclaimed "$root/err")" "0"
VERIFY_RUN=abandoned-run verify launch session >/dev/null 2>"$root/err"
VERIFY_RUN=abandoned-run verify tree >/dev/null 2>"$root/err"
expect "a launch of the reclaimed run takes its name back" "$(grep -c reclaimed "$root/err")" "0"

reset; own_the_app live-activity-run 61 ""
test_sim --no-build; status=$?
expect "a reclaimed run that had Live Activities on is uninstalled, as stop does" "$status $(cat "$root/xcrun-calls" | tr '\n' ' ')" \
    "65 simctl terminate $sim com.sunnypatel.WorkoutTracker simctl uninstall $sim com.sunnypatel.WorkoutTracker "

reset; own_the_app lane-short 2
WORKOUT_LEASE_MINUTES=1 test_sim --no-build; status=$?
expect "WORKOUT_LEASE_MINUTES sets the lease" "$status $(head -1 "$root/err")" \
    "65 reclaimed $sim from verify run lane-short (pid $app): its lease was last renewed 2 min ago, and the lease is 1 min"

reset; own_the_app active-run 59
test_sim --no-build; status=$?
expect "a run used 59 min ago refuses, before any xcodebuild" "$status $(builds)" "75 "
expect "the refusal says when it frees and how its owner takes it" "$(cat "$root/err")" \
    "a verify run active-run owns the app on $sim (pid $app), last used 59 min ago; a claim takes it once it goes 60 min unused. If it is yours, rerun with VERIFY_RUN=active-run or run: SIM=$sim VERIFY_RUN=active-run $repo/.agents/skills/verify/verify.sh stop, else use another simulator"

reset; own_the_app lane-812 5
VERIFY_RUN=lane-812 test_sim --no-build; status=$?
expect "the run's own owner takes its live app" "$status $(builds)" "65 test-without-building"
expect "the takeover says so" "$(head -1 "$root/err")" \
    "taking over the app of your own verify run lane-812 on $sim (pid $app)"

reset; own_the_app lane-812 5
VERIFY_RUN=lane-812 STUB_MEM_LEVEL=12 WORKOUT_ADMIT_WAIT=0 test_sim --no-build; status=$?
expect "a takeover the host refuses leaves the run's app recorded and announces nothing" \
    "$status $(ls "$state" | tr '\n' ' ')$(grep -c "taking over" "$root/err")" "75 args lock pid run 0"
reset; own_the_app lane-812 5 ""
SIM=$sim2 STUB_SHUTDOWN=$sim2 WORKOUT_BUILD_SLOTS=1 STUB_HOLD=1 "$repo/.agents/skills/verify/verify.sh" build >/dev/null 2>&1 &
first=$!
for _ in $(seq 1 100); do [ -f "$root/holding" ] && break; sleep 0.1; done
STUB_SHUTDOWN=$sim VERIFY_RUN=lane-812 WORKOUT_BUILD_SLOTS=1 WORKOUT_ADMIT_WAIT=0 test_sim; status=$?
touch "$root/release"; wait "$first"
expect "a takeover refused at the build slot boots, uninstalls and announces nothing, and keeps the record" \
    "$status $(cat "$root/xcrun-calls" 2>/dev/null)$(grep -c "taking over" "$root/err") $(ls "$state" | tr '\n' ' ')" \
    "75 0 args lock pid run "
reset; own_the_app abandoned-run 61
STUB_MEM_LEVEL=12 WORKOUT_ADMIT_WAIT=0 test_sim --no-build; status=$?
expect "a reclaim the host refuses leaves the abandoned run recorded" "$status $(ls "$state" | tr '\n' ' ')" "75 args lock pid run "
reset; own_the_app abandoned-run 61
SIM=$sim2 STUB_SHUTDOWN=$sim2 WORKOUT_BUILD_SLOTS=1 STUB_HOLD=1 "$repo/.agents/skills/verify/verify.sh" build >/dev/null 2>&1 &
first=$!
for _ in $(seq 1 100); do [ -f "$root/holding" ] && break; sleep 0.1; done
WORKOUT_BUILD_SLOTS=1 WORKOUT_ADMIT_WAIT=0 test_sim; status=$?
touch "$root/release"; wait "$first"
SIM=$sim "$repo/.agents/skills/verify/verify.sh" tree >/dev/null 2>&1
test_sim --no-build; status="$status $?"
expect "a reclaim refused at the build slot stays reclaimed, though a verify.sh call that names no run follows" \
    "$status $(grep -c 'owns the app' "$root/err")" "75 65 0"

reset; own_the_app lane-812 59
SIM=$sim VERIFY_RUN=lane-813 "$repo/.agents/skills/verify/verify.sh" tree >/dev/null 2>&1
expect "a verify.sh call for another run does not renew the lease" "$(minutes_old "$state/pid")" "59"
SIM=$sim VERIFY_RUN=lane-812 "$repo/.agents/skills/verify/verify.sh" tree >/dev/null 2>&1
expect "a verify.sh call for the run renews its lease" "$(minutes_old "$state/pid")" "0"
age_minutes "$state/pid" 59
SIM=$sim "$repo/.agents/skills/verify/verify.sh" tree >/dev/null 2>&1
expect "a verify.sh call that names no run renews the recorded one" "$(minutes_old "$state/pid")" "0"
age_minutes "$state/pid" 61
SIM=$sim "$repo/.agents/skills/verify/verify.sh" tree >/dev/null 2>"$root/err"
expect "a verify.sh call that names no run does not revive an expired lease" "$(minutes_old "$state/pid")" "61"
expect "and says how to renew it" "$(head -1 "$root/err")" \
    "the lease of verify run lane-812 on $sim expired: last renewed 61 min ago, and the lease is 60 min, so a claim may take its app; if the run is yours, name it with VERIFY_RUN=lane-812 to keep it"
rm "$state/pid"
SIM=$sim "$repo/.agents/skills/verify/verify.sh" tree >/dev/null 2>&1
expect "renewing never recreates a stopped run's pid file" "$(ls "$state" | tr '\n' ' ')" "args run "

echo "admission"
reset
STUB_LOAD=212.40 WORKOUT_ADMIT_WAIT=0 test_sim --no-build; status=$?
expect "a 1-minute load of 212.40 holds no claim, and the claim prints nothing" "$status $(builds) $(grep -c . "$root/err")" \
    "65 test-without-building 1"
reset
STUB_LOAD=212.40 WORKOUT_ADMIT_WAIT=0 SIM=$sim "$repo/.agents/skills/verify/verify.sh" build >"$root/out" 2>"$root/err"; status=$?
expect "a 1-minute load of 212.40 holds no build" "$status $(builds)" "65 build"

reset
STUB_MEM_LEVEL=12 WORKOUT_ADMIT_WAIT=0 test_sim --no-build; status=$?
expect "free memory under the floor refuses after the max wait, before any xcodebuild" "$status $(builds)" "75 "
expect "the refusal names the free memory and the knob" "$(refusal)" \
    "gave up after N s waiting for the host before taking $sim: free memory is 12%, under the floor of 25% (WORKOUT_MEM_FLOOR)"

reset
STUB_MEM_LEVEL=12 STUB_LOW_MEM_CALLS=2 WORKOUT_ADMIT_WAIT=30 test_sim --no-build; status=$?
expect "a claim waits for memory to free, then goes on" "$status $(builds)" "65 test-without-building"
expect "the wait is announced, then its end" "$(sed -n '1p;2s/[0-9]* s$/N s/p' "$root/err")" \
    "waiting up to 30 s for the host before taking $sim: free memory is 12%, under the floor of 25% (WORKOUT_MEM_FLOOR)
went ahead after N s"

reset
STUB_MEM_LEVEL=12 STUB_LOW_MEM_CALLS=1 WORKOUT_ADMIT_WAIT=3 bash -c '. "$1/scripts/sim-lock.sh"; sleep 4; wait_until_clear "memory" mem_clear' _ "$repo" 2>"$root/err"; status=$?
expect "a wait's budget starts when the wait does, so time spent before it, as on a cache build, is not counted" \
    "$status $(sed -n '2s/[0-9]* s$/N s/p' "$root/err")" "0 went ahead after N s"

reset
STUB_MEM_LEVEL=25 WORKOUT_ADMIT_WAIT=0 test_sim --no-build; status=$?
expect "free memory exactly at the floor is admitted" "$status $(builds)" "65 test-without-building"
reset
STUB_MEM_LEVEL=12 WORKOUT_MEM_FLOOR=10 test_sim --no-build; status=$?
expect "WORKOUT_MEM_FLOOR lowers the floor, and a clear claim prints nothing" "$status $(builds) $(grep -c . "$root/err")" \
    "65 test-without-building 1"
reset
STUB_SYSCTL_FAILS=1 WORKOUT_MEM_FLOOR=0 test_sim --no-build; status=$?
expect "a floor of 0 never reads memory, so even a failing sysctl holds nothing" "$status $(builds) $(cat "$root/mem-calls" 2>/dev/null)" \
    "65 test-without-building "
reset
STUB_SYSCTL_FAILS=1 WORKOUT_ADMIT_WAIT=0 test_sim --no-build; status=$?
expect "on macOS a sysctl that fails holds the claim" "$status $(refusal)" \
    "75 gave up after N s waiting for the host before taking $sim: sysctl -n kern.memorystatus_level failed: sysctl: unknown oid 'kern.memorystatus_level'"
reset
STUB_MEM_LEVEL=n/a WORKOUT_ADMIT_WAIT=0 test_sim --no-build; status=$?
expect "a memory reading that is not a whole number holds the claim" "$status $(refusal)" \
    "75 gave up after N s waiting for the host before taking $sim: sysctl -n kern.memorystatus_level printed no free-memory percent: n/a"
reset
WORKOUT_MEM_FLOOR=-1 test_sim --no-build; status=$?
expect "a negative floor is a usage error" "$status $(cat "$root/err")" "2 WORKOUT_MEM_FLOOR must be a whole number: -1"

reset
STUB_SHUTDOWN=$sim STUB_BOOTED_OTHERS=10 WORKOUT_ADMIT_WAIT=0 test_sim --no-build; status=$?
expect "ten other booted simulators refuse a claim that would boot an eleventh" "$status $(builds)" "75 "
expect "the refusal names the count and the knob" "$(refusal)" \
    "gave up after N s waiting for the host before taking $sim: 10 other simulators are booted, at the cap of 10 (WORKOUT_SIM_CAP)"

reset
STUB_BOOTED_OTHERS=10 WORKOUT_ADMIT_WAIT=0 test_sim --no-build; status=$?
expect "a claim on a simulator already booted boots nothing, so the cap does not hold it" "$status $(builds)" "65 test-without-building"

reset
for verb in "launch session" install; do
    read -ra argv <<< "$verb"
    STUB_SHUTDOWN=$sim STUB_BOOTED_OTHERS=10 WORKOUT_ADMIT_WAIT=0 verify "${argv[@]}" >"$root/out" 2>"$root/err"; status=$?
    expect "verify.sh $verb boots a shut-down simulator only through admission" \
        "$status $(cat "$root/xcrun-calls" 2>/dev/null | grep -c 'simctl boot') $(grep '^gave up' "$root/err" | sed 's/^gave up after [0-9]* s/gave up after N s/')" \
        "75 0 gave up after N s waiting for the host before taking $sim: 10 other simulators are booted, at the cap of 10 (WORKOUT_SIM_CAP)"
done
STUB_SHUTDOWN=$sim STUB_BOOTED_OTHERS=10 WORKOUT_ADMIT_WAIT=0 verify build >"$root/out" 2>"$root/err"; status=$?
expect "verify.sh build boots nothing, so the cap does not hold it" "$status $(cat "$root/xcrun-calls" 2>/dev/null | grep -c 'simctl boot') $(builds)" "65 0 build"

reset
STUB_SHUTTING_DOWN=$sim WORKOUT_ADMIT_WAIT=0 test_sim --no-build; status=$?
expect "a simulator still shutting down waits, so the cap counts its boot" "$status $(refusal)" \
    "75 gave up after N s waiting for the host before taking $sim: $sim is shutting down"

reset
STUB_SHUTDOWN=$sim2 STUB_BOOTED_OTHERS=10 WORKOUT_BUILD_SLOTS=1 WORKOUT_ADMIT_WAIT=4 \
    "$repo/scripts/test-sim.sh" --sim "$sim2" unit >/dev/null 2>"$root/err2" &
first=$!
for _ in $(seq 1 100); do grep -q "waiting up to" "$root/err2" 2>/dev/null && break; sleep 0.1; done
STUB_SHUTDOWN=$sim2 STUB_BOOTED_OTHERS=10 WORKOUT_BUILD_SLOTS=1 WORKOUT_ADMIT_WAIT=0 test_sim; status=$?
wait "$first"
expect "a build claim waiting at the cap holds no build slot" "$status $(builds)" "65 build-for-testing"

reset
mkdir -p "$root/locks"
python3 -c 'import fcntl, sys, time
slot = open(sys.argv[1], "a")
fcntl.flock(slot, fcntl.LOCK_EX)
open(sys.argv[2], "w").close()
time.sleep(30)' "$root/locks/build-1" "$root/holding" &
building=$!
for _ in $(seq 1 100); do [ -f "$root/holding" ] && break; sleep 0.1; done
STUB_SHUTDOWN=$sim2 WORKOUT_BUILD_SLOTS=1 WORKOUT_ADMIT_WAIT=8 \
    "$repo/scripts/test-sim.sh" --sim "$sim2" unit >/dev/null 2>"$root/err2" &
first=$!
for _ in $(seq 1 100); do grep -q "waiting up to" "$root/err2" 2>/dev/null && break; sleep 0.1; done
held=$(python3 -c 'import fcntl, sys, time
admit, held = open(sys.argv[1], "a"), 0
for _ in range(500):
    try: fcntl.flock(admit, fcntl.LOCK_EX | fcntl.LOCK_NB); fcntl.flock(admit, fcntl.LOCK_UN)
    except BlockingIOError: held += 1
    time.sleep(0.01)
print(held)' "$root/locks/admit")
kill "$building"; wait "$building" "$first" 2>/dev/null
expect "a build claim waiting for a slot never takes the admit lock" "$held" "0"

reset
STUB_SHUTDOWN=$sim STUB_BOOT_FAILS=raced test_sim --no-build; status=$?
expect "a boot that fails because another process booted the simulator goes on" "$status $(builds)" "65 test-without-building"
reset
STUB_SHUTDOWN=$sim STUB_BOOT_FAILS=booting test_sim --no-build; status=$?
expect "a boot that fails because another process is booting the simulator goes on" "$status $(builds)" "65 test-without-building"
reset
STUB_SHUTDOWN=$sim STUB_BOOT_FAILS=1 test_sim --no-build; status=$?
expect "a boot that fails leaves it shut down, exits 70, and says why" "$status $(builds) $(cat "$root/err")" \
    "70  could not boot $sim: Unable to boot device in current state: Booted"

reset
STUB_SHUTDOWN=$sim STUB_BOOT_HOLD=1 WORKOUT_BUILD_SLOTS=1 "$repo/scripts/test-sim.sh" --sim "$sim" unit >/dev/null 2>&1 &
first=$!
for _ in $(seq 1 100); do [ -f "$root/boot-holding" ] && break; sleep 0.1; done
kill -9 "$first"; wait "$first" 2>/dev/null
WORKOUT_BUILD_SLOTS=1 WORKOUT_ADMIT_WAIT=0 test_sim; status=$?
touch "$root/release"
expect "a claimer killed during its boot frees the simulator, the admit lock and its build slot at once" "$status $(builds)" \
    "65 build-for-testing"
expect "and leaves nothing but lock files in the host lock directory" "$(leftovers)" ""

reset
STUB_LIST_WARNING=1 WORKOUT_ADMIT_WAIT=0 test_sim --no-build; status=$?
expect "a warning simctl prints beside a good listing does not hold the claim" "$status $(builds)" "65 test-without-building"

reset
STUB_SHUTDOWN=$sim STUB_BOOTED_OTHERS=10 WORKOUT_ADMIT_WAIT=0 "$repo/scripts/test-sim.sh" --no-build unit >"$root/out" 2>"$root/err"; status=$?
expect "a claim the host refuses boots nothing" "$status $(cat "$root/xcrun-calls" 2>/dev/null)" "75 "
reset
STUB_SHUTDOWN=$sim STUB_BOOTED_OTHERS=9 test_sim --no-build; status=$?
expect "an admitted claim boots its shut-down simulator before the run" "$status $(cat "$root/xcrun-calls") $(builds)" \
    "65 simctl boot $sim test-without-building"
STUB_SHUTDOWN="$sim $sim2" STUB_BOOTED_OTHERS=9 WORKOUT_ADMIT_WAIT=0 \
    "$repo/scripts/test-sim.sh" --no-build --sim "$sim2" unit >"$root/out" 2>"$root/err"; status=$?
expect "the next claim counts a simulator the last claim booted" "$status $(refusal)" \
    "75 gave up after N s waiting for the host before taking $sim2: 10 other simulators are booted, at the cap of 10 (WORKOUT_SIM_CAP)"

reset
mkdir -p "$root/herd"
cat >"$root/herd/xcrun" <<STUB
#!/bin/sh
[ "\$*" = "simctl list devices available -j" ] || exec "$root/bin/xcrun" "\$@"
echo listed >> "$root/herd-listed"
[ "\$(wc -l < "$root/herd-listed")" -eq 2 ] || exec "$root/bin/xcrun" "\$@"
listing=\$("$root/bin/xcrun" "\$@")
touch "$root/release"
i=0
while [ ! -f "$root/booted" ] && [ \$i -lt 100 ]; do sleep 0.1; i=\$((i + 1)); done
printf '%s\\n' "\$listing"
STUB
chmod +x "$root/herd/xcrun"
rm -f "$root/herd-listed"
STUB_SHUTDOWN="$sim $sim2" STUB_BOOTED_OTHERS=9 STUB_BOOT_HOLD=1 test_sim --no-build &
first=$!
for _ in $(seq 1 100); do [ -f "$root/boot-holding" ] && break; sleep 0.1; done
PATH="$root/herd:$PATH" STUB_SHUTDOWN="$sim $sim2" STUB_BOOTED_OTHERS=9 WORKOUT_ADMIT_WAIT=0 \
    "$repo/scripts/test-sim.sh" --no-build --sim "$sim2" unit >/dev/null 2>"$root/err2"; status=$?
wait "$first"; status="$? $status"
expect "two claims that both counted 5 booted boot one simulator between them, not two" \
    "$status $(grep -c 'simctl boot' "$root/xcrun-calls")" "65 75 1"

reset; rm -f "$root/herd-listed"
STUB_SHUTDOWN="$sim $sim2" STUB_BOOTED_OTHERS=9 STUB_BOOT_HOLD=1 test_sim --no-build &
first=$!
for _ in $(seq 1 100); do [ -f "$root/boot-holding" ] && break; sleep 0.1; done
PATH="$root/herd:$PATH" STUB_SHUTDOWN="$sim $sim2" STUB_BOOTED_OTHERS=9 WORKOUT_BUILD_SLOTS=1 WORKOUT_ADMIT_WAIT=5 \
    "$repo/scripts/test-sim.sh" --sim "$sim2" unit >/dev/null 2>"$root/err2" &
second=$!
wait "$first"; rm -f "$root/builds"
for _ in $(seq 1 100); do grep -q "waiting up to" "$root/err2" 2>/dev/null && break; sleep 0.1; done
STUB_SHUTDOWN="$sim $sim2" STUB_BOOTED_OTHERS=9 WORKOUT_BUILD_SLOTS=1 WORKOUT_ADMIT_WAIT=0 test_sim; status=$?
wait "$second"
expect "a build claim the recount turns away gives its build slot back" "$status $(builds)" "65 build-for-testing"

reset
STUB_SHUTDOWN="$sim $sim2" STUB_BOOTED_OTHERS=9 STUB_BOOT_HOLD=1 test_sim --no-build &
first=$!
for _ in $(seq 1 100); do [ -f "$root/boot-holding" ] && break; sleep 0.1; done
STUB_SHUTDOWN="$sim $sim2" STUB_BOOTED_OTHERS=9 WORKOUT_ADMIT_WAIT=0 \
    "$repo/scripts/test-sim.sh" --no-build --sim "$sim2" unit >/dev/null 2>"$root/err2"; status=$?
touch "$root/release"; wait "$first"
expect "a claim holds the admit lock through its boot, so no other boot starts meanwhile" \
    "$status $(grep -c 'simctl boot' "$root/xcrun-calls") $(tail -1 "$root/err2" | sed 's/^gave up after [0-9]* s/gave up after N s/')" \
    "75 1 gave up after N s waiting for the host before taking $sim2: another claim is booting a simulator (lsof $root/locks/admit lists it)"

reset
mkdir -p "$root/locks"
python3 -c 'import fcntl, sys, time
admit = open(sys.argv[1], "a")
fcntl.flock(admit, fcntl.LOCK_EX)
open(sys.argv[2], "w").close()
time.sleep(30)' "$root/locks/admit" "$root/holding" &
admitting=$!
for _ in $(seq 1 100); do [ -f "$root/holding" ] && break; sleep 0.1; done
STUB_SHUTDOWN=$sim2 WORKOUT_BUILD_SLOTS=1 WORKOUT_ADMIT_WAIT=25 \
    "$repo/scripts/test-sim.sh" --sim "$sim2" unit >/dev/null 2>"$root/err2" &
first=$!
for _ in $(seq 1 100); do grep -q "waiting up to" "$root/err2" 2>/dev/null && break; sleep 0.1; done
held=$(python3 -c 'import fcntl, sys, time
slot, held = open(sys.argv[1], "a"), 0
for _ in range(400):
    try: fcntl.flock(slot, fcntl.LOCK_EX | fcntl.LOCK_NB); fcntl.flock(slot, fcntl.LOCK_UN)
    except BlockingIOError: held += 1
    time.sleep(0.01)
print(held)' "$root/locks/build-1")
kill "$admitting"; wait "$admitting" "$first" 2>/dev/null
expect "a build claim waiting for the admit lock holds its build slot for no more than a probe" \
    "$([ "$held" -lt 20 ] && echo "under 20 of 400 samples" || echo "$held of 400 samples")" "under 20 of 400 samples"

reset
STUB_SHUTDOWN=$sim2 STUB_SLOW_LIST_CALL=3 WORKOUT_BUILD_SLOTS=1 WORKOUT_ADMIT_WAIT=0 \
    "$repo/scripts/test-sim.sh" --sim "$sim2" unit >/dev/null 2>"$root/err2" &
first=$!
for _ in $(seq 1 100); do [ -f "$root/listing-slowly" ] && break; sleep 0.1; done
STUB_HOLD=1 WORKOUT_BUILD_SLOTS=1 WORKOUT_ADMIT_WAIT=0 test_sim &
second=$!
wait "$first"; status=$?
touch "$root/release"; wait "$second"; status="$status $?"
expect "a build claim takes its slot under the admit lock before it boots, so a build that starts meanwhile waits" \
    "$status $(grep -c 'simctl boot' "$root/xcrun-calls" 2>/dev/null)" "65 75 1"

reset
mkdir -p "$root/locks"
python3 -c 'import fcntl, sys, time
admit, build = open(sys.argv[1], "a"), open(sys.argv[2], "a")
fcntl.flock(admit, fcntl.LOCK_EX)
fcntl.flock(build, fcntl.LOCK_SH)
open(sys.argv[3], "w").close()
time.sleep(30)' "$root/locks/admit" "$root/locks/build-1" "$root/holding" &
admitting=$!
for _ in $(seq 1 100); do [ -f "$root/holding" ] && break; sleep 0.1; done
STUB_SHUTDOWN=$sim WORKOUT_BUILD_SLOTS=1 WORKOUT_ADMIT_WAIT=0 test_sim; status=$?
kill "$admitting"; wait "$admitting" 2>/dev/null
expect "a build claim waiting on a boot blames the boot, never another claim's slot probe" "$status $(refusal)" \
    "75 gave up after N s waiting for the host before taking $sim: another claim is booting a simulator (lsof $root/locks/admit lists it)"

went=0
for _ in 1 2 3 4 5; do
    reset
    STUB_PROBE_ON_LIST_CALL=2 WORKOUT_BUILD_SLOTS=1 WORKOUT_ADMIT_WAIT=0 test_sim
    [ $? != 65 ] || went=$((went + 1))
done
expect "a build on a booted simulator outlasts another claim's shared probe of its slot" "$went of 5" "5 of 5"

reset
STUB_SHUTDOWN=$sim STUB_SLOW_LIST_CALL=3 "$repo/scripts/test-sim.sh" --no-build --sim "$sim" unit >/dev/null 2>&1 &
first=$!
for _ in $(seq 1 100); do [ -f "$root/listing-slowly" ] && break; sleep 0.1; done
kill -9 "$first"; wait "$first" 2>/dev/null
STUB_SHUTDOWN="$sim $sim2" WORKOUT_ADMIT_WAIT=0 "$repo/scripts/test-sim.sh" --no-build --sim "$sim2" unit >/dev/null 2>"$root/err2"; status=$?
expect "a claimer killed during its listing under the admit lock frees it at once" "$status $(grep -c 'simctl boot' "$root/xcrun-calls")" "65 1"
expect "and leaves nothing but lock files in the host lock directory" "$(leftovers)" ""
sleep 3

reset
mkdir -p "$root/locks"
python3 -c 'import fcntl, sys, time
admit = open(sys.argv[1], "a")
fcntl.flock(admit, fcntl.LOCK_EX)
open(sys.argv[2], "w").close()
time.sleep(30)' "$root/locks/admit" "$root/holding" &
admitting=$!
for _ in $(seq 1 100); do [ -f "$root/holding" ] && break; sleep 0.1; done
STUB_SHUTDOWN=$sim WORKOUT_ADMIT_WAIT=0 test_sim --no-build; status=$?
expect "claims that boot a simulator are admitted one at a time" "$status $(refusal)" \
    "75 gave up after N s waiting for the host before taking $sim: another claim is booting a simulator (lsof $root/locks/admit lists it)"
WORKOUT_ADMIT_WAIT=0 test_sim --no-build; status=$?
expect "a claim on a booted simulator does not wait behind another claim's boot" "$status $(builds)" "65 test-without-building"
STUB_SHUTDOWN=$sim STUB_BOOTED_OTHERS=10 WORKOUT_ADMIT_WAIT=0 test_sim --no-build; status=$?
expect "a claim the cap refuses never waits for the admit lock" "$status $(refusal)" \
    "75 gave up after N s waiting for the host before taking $sim: 10 other simulators are booted, at the cap of 10 (WORKOUT_SIM_CAP)"
kill "$admitting"; wait "$admitting" 2>/dev/null

reset
STUB_LIST_GARBAGE_FROM_CALL=2 WORKOUT_ADMIT_WAIT=0 test_sim --no-build; status=$?
expect "a simulator listing that is no device list holds the claim" "$status $(refusal | sed 's/device list: .*/device list: .../')" \
    "75 gave up after N s waiting for the host before taking $sim: xcrun simctl list devices printed no device list: ..."
reset
PYTHONPROFILEIMPORTTIME=1 STUB_SHUTDOWN=$sim STUB_BOOTED_OTHERS=10 WORKOUT_ADMIT_WAIT=0 test_sim --no-build; status=$?
expect "what python prints on stderr never reaches the booted count, so the cap still holds" "$status $(refusal)" \
    "75 gave up after N s waiting for the host before taking $sim: 10 other simulators are booted, at the cap of 10 (WORKOUT_SIM_CAP)"
reset
STUB_LIST_OK_CALLS=1 WORKOUT_ADMIT_WAIT=0 test_sim --no-build; status=$?
expect "a simulator listing that fails holds the claim" "$status $(refusal)" \
    "75 gave up after N s waiting for the host before taking $sim: xcrun simctl list devices failed: An error was encountered processing the command (domain=com.apple.CoreSimulator.SimError, code=405)"

reset
WORKOUT_SIM_CAP=six test_sim --no-build; status=$?
expect "a knob that is not a whole number is a usage error" "$status $(cat "$root/err")" "2 WORKOUT_SIM_CAP must be a whole number: six"
reset
WORKOUT_BUILD_SLOTS=0 test_sim; status=$?
expect "zero build slots is a usage error, before any build" "$status $(builds) $(cat "$root/err")" "2  WORKOUT_BUILD_SLOTS must be at least 1: 0"

echo "build slots"
verify_build() { SIM=$sim "$repo/.agents/skills/verify/verify.sh" build; }
reset
SIM=$sim WORKOUT_BUILD_SLOTS=1 STUB_HOLD=1 "$repo/.agents/skills/verify/verify.sh" build >/dev/null 2>&1 &
first=$!
for _ in $(seq 1 100); do [ -f "$root/holding" ] && break; sleep 0.1; done
WORKOUT_BUILD_SLOTS=1 WORKOUT_ADMIT_WAIT=0 test_sim; status=$?
expect "a build waits while every slot is taken, and gives up with 75, not a build failure" "$status $(builds)" "75 build"
expect "the claim names the slot holders" "$(refusal)" \
    "gave up after N s waiting for the host before taking $sim: all 1 build slots are taken (WORKOUT_BUILD_SLOTS): verify.sh (pid $first); lsof $root/locks/build-* lists every process holding one"
WORKOUT_BUILD_SLOTS=1 WORKOUT_ADMIT_WAIT=0 verify_build >"$root/out" 2>"$root/err"
expect "verify.sh build's slot refusal reaches stderr through the build log's redirect" "$(refusal)" \
    "gave up after N s waiting for a build slot: all 1 build slots are taken (WORKOUT_BUILD_SLOTS): verify.sh (pid $first); lsof $root/locks/build-* lists every process holding one"
kill -9 "$first"; wait "$first" 2>/dev/null
WORKOUT_BUILD_SLOTS=1 WORKOUT_ADMIT_WAIT=0 test_sim; status=$?
expect "the xcodebuild of a killed run keeps its slot until it exits" "$status $(builds)" "75 build"
touch "$root/release"
for _ in $(seq 1 50); do
    WORKOUT_BUILD_SLOTS=1 WORKOUT_ADMIT_WAIT=0 test_sim; status=$?
    [ $status = 75 ] || break
    sleep 0.1
done
expect "the slot frees when that xcodebuild exits, and the next build runs" "$status $(builds)" "65 build build-for-testing"

reset
WORKOUT_BUILD_SLOTS=2 STUB_HOLD=1 test_sim &
first=$!
for _ in $(seq 1 100); do [ -f "$root/holding" ] && break; sleep 0.1; done
WORKOUT_BUILD_SLOTS=2 WORKOUT_ADMIT_WAIT=0 verify_build >"$root/out" 2>"$root/err"; status=$?
expect "verify.sh build takes the second slot beside a test-sim.sh build" "$status $(builds)" "65 build-for-testing build"
touch "$root/release"; wait "$first"

reset
STUB_MEM_LEVEL=12 WORKOUT_ADMIT_WAIT=0 verify_build >"$root/out" 2>"$root/err"; status=$?
expect "verify.sh build waits for memory as a claim does, and gives up with 75 before any xcodebuild" "$status $(builds) $(refusal)" \
    "75  gave up after N s waiting for a build slot: free memory is 12%, under the floor of 25% (WORKOUT_MEM_FLOOR)"
reset
STUB_MEM_LEVEL=12 STUB_LOW_MEM_CALLS=1 WORKOUT_ADMIT_WAIT=30 verify_build >"$root/out" 2>"$root/err"; status=$?
expect "and builds once memory frees" "$status $(builds)" "65 build"

echo "build-slot.sh"
build_slot() { "$repo/scripts/build-slot.sh" "$@" >"$root/out" 2>"$root/err"; }
reset
build_slot sh -c 'echo ran; exit 3'; status=$?
expect "it runs the command and exits with the command's status, saying nothing" "$status $(cat "$root/out") $(cat "$root/err")" "3 ran "
reset
WORKOUT_BUILD_SLOTS=1 "$repo/scripts/build-slot.sh" sh -c 'touch "$1/holding"; while [ ! -f "$1/release" ]; do sleep 0.1; done' _ "$root" &
first=$!
for _ in $(seq 1 100); do [ -f "$root/holding" ] && break; sleep 0.1; done
WORKOUT_BUILD_SLOTS=1 WORKOUT_ADMIT_WAIT=0 test_sim; status=$?
expect "the command holds a build slot that test-sim.sh builds wait for" "$status $(builds) $(refusal)" \
    "75  gave up after N s waiting for the host before taking $sim: all 1 build slots are taken (WORKOUT_BUILD_SLOTS): build-slot.sh (pid $first); lsof $root/locks/build-* lists every process holding one"
WORKOUT_BUILD_SLOTS=1 WORKOUT_ADMIT_WAIT=0 build_slot touch "$root/ran"; status=$?
expect "with every slot taken it exits 75 after the max wait, without running the command" "$status $([ -f "$root/ran" ] && echo ran) $(refusal)" \
    "75  gave up after N s waiting for a build slot: all 1 build slots are taken (WORKOUT_BUILD_SLOTS): build-slot.sh (pid $first); lsof $root/locks/build-* lists every process holding one"
touch "$root/release"; wait "$first"
rm -f "$root/ran"
STUB_MEM_LEVEL=12 WORKOUT_ADMIT_WAIT=0 build_slot touch "$root/ran"; status=$?
expect "with free memory under the floor it exits 75 without running the command" "$status $([ -f "$root/ran" ] && echo ran) $(refusal)" \
    "75  gave up after N s waiting for a build slot: free memory is 12%, under the floor of 25% (WORKOUT_MEM_FLOOR)"
STUB_LOAD=212.40 WORKOUT_ADMIT_WAIT=0 build_slot true; status=$?
expect "the 1-minute load holds nothing" "$status" "0"
build_slot; status=$?
expect "with no command it prints the usage and exits 2" "$status $(head -1 "$root/err")" "2 Usage: scripts/build-slot.sh <command> [arg...]"
build_slot --help; status=$?
expect "--help prints the usage on stdout and exits 0" "$status $(head -1 "$root/out")" "0 Usage: scripts/build-slot.sh <command> [arg...]"

echo "load_clear, which judges a verify.sh record take"
load_wait() { WORKOUT_ADMIT_WAIT=0 bash -c '. "$1/scripts/sim-lock.sh"; wait_until_clear "the load" load_clear "$2"' _ "$repo" "$1" 2>"$root/err"; }
reset
STUB_LOAD=80.00 load_wait 50; status=$?
expect "a load over the limit holds" "$status $(refusal)" \
    "75 gave up after N s waiting for the load: the 1-minute load is 80.00, over 50 (WORKOUT_LOAD_LIMIT)"
STUB_LOAD=50.00 load_wait 50; status=$?
expect "a load exactly at the limit is under it" "$status $(cat "$root/err")" "0 "
mkdir -p "$root/broken-awk"
printf '#!/bin/sh\necho "awk: cannot run" >&2\nexit 2\n' > "$root/broken-awk/awk"
chmod +x "$root/broken-awk/awk"
PATH="$root/broken-awk:$PATH" STUB_LOAD=1.00 load_wait 50; status=$?
expect "an awk that cannot compare the load holds, it never clears" "$status $(refusal)" \
    "75 gave up after N s waiting for the load: awk could not compare the 1-minute load 1.00 with 50 (exit 2)"
STUB_LOAD=n/a load_wait 50; status=$?
expect "a load reading that is not a number holds" "$status $(refusal)" \
    "75 gave up after N s waiting for the load: sysctl -n vm.loadavg printed no 1-minute load: { n/a 1.00 1.00 }"
STUB_SYSCTL_FAILS=1 load_wait 50; status=$?
expect "on macOS a sysctl that fails holds" "$status $(refusal)" \
    "75 gave up after N s waiting for the load: sysctl -n vm.loadavg failed: sysctl: unknown oid 'vm.loadavg'"
if gawk=$(command -v gawk); then
    mkdir -p "$root/gawk"
    ln -s "$gawk" "$root/gawk/awk"
    PATH="$root/gawk:$PATH" STUB_LOAD=80.00 load_wait 50; status=$?
    expect "under gawk, a load over the limit holds" "$status $(refusal)" \
        "75 gave up after N s waiting for the load: the 1-minute load is 80.00, over 50 (WORKOUT_LOAD_LIMIT)"
    PATH="$root/gawk:$PATH" STUB_LOAD=80.00 load_wait 100; status=$?
    expect "under gawk, a load under the limit clears and says nothing" "$status $(cat "$root/err")" "0 "
else
    echo "  skip the gawk checks: no gawk on PATH (brew install gawk)"
fi

echo "help"
missing=
for knob in $(sed -n 's/^host_knob \([A-Z_]*\) .*/\1/p' "$repo/scripts/sim-lock.sh"); do
    for script in "$repo/.agents/skills/verify/verify.sh" "$repo/scripts/test-sim.sh"; do
        case $("$script" --help 2>&1) in *"$knob"*) ;; *) missing="$missing${missing:+, }$knob in ${script##*/}" ;; esac
    done
done
expect "verify.sh --help and test-sim.sh --help name every host knob sim-lock.sh reads" "${missing:-none missing}" "none missing"

printf '\npassed %d, failed %d\n' "$pass" "$fail"
[ "$fail" = 0 ]
