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
cp "$script_dir/../test-sim.sh" "$script_dir/../sim-lock.sh" "$script_dir/../wait-load.sh" \
    "$script_dir/../test-log-summary.awk" "$repo/scripts/"
cp "$script_dir/../../.agents/skills/verify/verify.sh" "$repo/.agents/skills/verify/"
touch "$products/../../info.plist" "$products/WorkoutTracker_iphonesimulator27.0-arm64.xctestrun"
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
    esac
    exit 0
fi
[ -z "\${STUB_LIST_WARNING:-}" ] || echo "objc[4242]: Class SimDeviceSet is implemented in both CoreSimulator and CoreSimulatorUtilities" >&2
echo call >> "$root/list-calls"
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
unset VERIFY_RUN SIM WORKOUT_LOAD_LIMIT WORKOUT_SIM_CAP WORKOUT_ADMIT_WAIT WORKOUT_BUILD_SLOTS

reset() {
    rm -rf "$state" "/tmp/workout-verify-$sim2" "$root/builds" "$root/sysctl-calls" "$root/xcrun-calls" "$root/list-calls" \
        "$root/booted" "$root/booting" "$root/holding" "$root/boot-holding" "$root/release"
}
builds() { cat "$root/builds" 2>/dev/null | tr '\n' ' ' | sed 's/ $//'; }
test_sim() { "$repo/scripts/test-sim.sh" "$@" --sim "$sim" unit >"$root/out" 2>"$root/err"; }
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
expect "a reclaim drops the abandoned run's record, so no later call renews it" "$(ls "$state" | tr '\n' ' ')" "lock run "
expect "an app launched without Live Activities is left for the next install to replace" "$(cat "$root/xcrun-calls" 2>/dev/null)" ""

reset; own_the_app live-activity-run 61 ""
test_sim --no-build; status=$?
expect "a reclaimed run that had Live Activities on is uninstalled, as stop does" "$status $(cat "$root/xcrun-calls")" \
    "65 simctl uninstall $sim com.sunnypatel.WorkoutTracker"

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
VERIFY_RUN=lane-812 STUB_LOAD=212.40 WORKOUT_ADMIT_WAIT=0 test_sim --no-build; status=$?
expect "a takeover the host refuses leaves the run's app recorded and announces nothing" \
    "$status $(ls "$state" | tr '\n' ' ')$(grep -c "taking over" "$root/err")" "75 args lock pid run 0"
reset; own_the_app lane-812 5 ""
SIM=$sim2 WORKOUT_BUILD_SLOTS=1 STUB_HOLD=1 "$repo/.agents/skills/verify/verify.sh" build >/dev/null 2>&1 &
first=$!
for _ in $(seq 1 100); do [ -f "$root/holding" ] && break; sleep 0.1; done
STUB_SHUTDOWN=$sim VERIFY_RUN=lane-812 WORKOUT_BUILD_SLOTS=1 WORKOUT_ADMIT_WAIT=0 test_sim; status=$?
touch "$root/release"; wait "$first"
expect "a takeover refused at the build slot boots, uninstalls and announces nothing, and keeps the record" \
    "$status $(cat "$root/xcrun-calls" 2>/dev/null)$(grep -c "taking over" "$root/err") $(ls "$state" | tr '\n' ' ')" \
    "75 0 args lock pid run "
reset; own_the_app abandoned-run 61
STUB_LOAD=212.40 WORKOUT_ADMIT_WAIT=0 test_sim --no-build; status=$?
expect "a reclaim the host refuses leaves the abandoned run recorded" "$status $(ls "$state" | tr '\n' ' ')" "75 args lock pid run "
reset; own_the_app abandoned-run 61
SIM=$sim2 WORKOUT_BUILD_SLOTS=1 STUB_HOLD=1 "$repo/.agents/skills/verify/verify.sh" build >/dev/null 2>&1 &
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
    "the lease of verify run lane-812 on $sim lapsed 61 min ago, so a claim may take its app; name it with VERIFY_RUN=lane-812 to renew it"
rm "$state/pid"
SIM=$sim "$repo/.agents/skills/verify/verify.sh" tree >/dev/null 2>&1
expect "renewing never recreates a stopped run's pid file" "$(ls "$state" | tr '\n' ' ')" "args run "

echo "admission"
reset
STUB_LOAD=212.40 WORKOUT_ADMIT_WAIT=0 test_sim --no-build; status=$?
expect "a load over the limit refuses after the max wait, before any xcodebuild" "$status $(builds)" "75 "
expect "the refusal names the load and the knob" "$(refusal)" \
    "gave up after N s waiting for the host before taking $sim: the 1-minute load is 212.40, over 50 (WORKOUT_LOAD_LIMIT)"

reset
STUB_LOAD=212.40 STUB_BUSY_CALLS=1 WORKOUT_ADMIT_WAIT=30 test_sim --no-build; status=$?
expect "a claim waits for the load to fall, then goes on" "$status $(builds)" "65 test-without-building"
expect "the wait is announced, then its end" "$(sed -n '1p;2s/[0-9]* s$/N s/p' "$root/err")" \
    "waiting up to 30 s for the host before taking $sim: the 1-minute load is 212.40, over 50 (WORKOUT_LOAD_LIMIT)
went ahead after N s"

reset
STUB_LOAD=212.40 WORKOUT_LOAD_LIMIT=300 test_sim --no-build; status=$?
expect "WORKOUT_LOAD_LIMIT raises the limit, and a clear claim prints nothing" "$status $(builds) $(grep -c . "$root/err")" \
    "65 test-without-building 1"

reset
STUB_SHUTDOWN=$sim STUB_BOOTED_OTHERS=6 WORKOUT_ADMIT_WAIT=0 test_sim --no-build; status=$?
expect "six other booted simulators refuse a claim that would boot a seventh" "$status $(builds)" "75 "
expect "the refusal names the count and the knob" "$(refusal)" \
    "gave up after N s waiting for the host before taking $sim: 6 other simulators are booted, at the cap of 6 (WORKOUT_SIM_CAP)"

reset
STUB_BOOTED_OTHERS=6 WORKOUT_ADMIT_WAIT=0 test_sim --no-build; status=$?
expect "a claim on a simulator already booted boots nothing, so the cap does not hold it" "$status $(builds)" "65 test-without-building"

reset
STUB_SHUTDOWN=$sim STUB_BOOTED_OTHERS=6 WORKOUT_ADMIT_WAIT=0 "$repo/.agents/skills/verify/verify.sh" build >"$root/out" 2>"$root/err"; status=$?
expect "verify.sh boots a shut-down simulator only through admission" "$status $(cat "$root/xcrun-calls" 2>/dev/null | grep -c 'simctl boot') $(builds)" "75 0 "

reset
STUB_SHUTTING_DOWN=$sim WORKOUT_ADMIT_WAIT=0 test_sim --no-build; status=$?
expect "a simulator still shutting down waits, so the cap counts its boot" "$status $(refusal)" \
    "75 gave up after N s waiting for the host before taking $sim: $sim is shutting down"

reset
STUB_SHUTDOWN=$sim2 STUB_BOOTED_OTHERS=6 WORKOUT_BUILD_SLOTS=1 WORKOUT_ADMIT_WAIT=4 \
    "$repo/scripts/test-sim.sh" --sim "$sim2" unit >/dev/null 2>&1 &
first=$!
sleep 1
STUB_SHUTDOWN=$sim2 STUB_BOOTED_OTHERS=6 WORKOUT_BUILD_SLOTS=1 WORKOUT_ADMIT_WAIT=0 test_sim; status=$?
wait "$first"
expect "a build claim waiting at the cap holds no build slot" "$status $(builds)" "65 build-for-testing"

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

reset
STUB_LIST_WARNING=1 WORKOUT_ADMIT_WAIT=0 test_sim --no-build; status=$?
expect "a warning simctl prints beside a good listing does not hold the claim" "$status $(builds)" "65 test-without-building"

reset
STUB_SHUTDOWN=$sim STUB_BOOTED_OTHERS=6 WORKOUT_ADMIT_WAIT=0 "$repo/scripts/test-sim.sh" --no-build unit >"$root/out" 2>"$root/err"; status=$?
expect "a claim the host refuses boots nothing" "$status $(cat "$root/xcrun-calls" 2>/dev/null)" "75 "
reset
STUB_SHUTDOWN=$sim STUB_BOOTED_OTHERS=5 test_sim --no-build; status=$?
expect "an admitted claim boots its shut-down simulator before the run" "$status $(cat "$root/xcrun-calls") $(builds)" \
    "65 simctl boot $sim test-without-building"
STUB_SHUTDOWN="$sim $sim2" STUB_BOOTED_OTHERS=5 WORKOUT_ADMIT_WAIT=0 \
    "$repo/scripts/test-sim.sh" --no-build --sim "$sim2" unit >"$root/out" 2>"$root/err"; status=$?
expect "the next claim counts a simulator the last claim booted" "$status $(refusal)" \
    "75 gave up after N s waiting for the host before taking $sim2: 6 other simulators are booted, at the cap of 6 (WORKOUT_SIM_CAP)"

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
STUB_SHUTDOWN=$sim STUB_BOOTED_OTHERS=6 WORKOUT_ADMIT_WAIT=0 test_sim --no-build; status=$?
expect "a claim the cap refuses never waits for the admit lock" "$status $(refusal)" \
    "75 gave up after N s waiting for the host before taking $sim: 6 other simulators are booted, at the cap of 6 (WORKOUT_SIM_CAP)"
kill "$admitting"; wait "$admitting" 2>/dev/null

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

echo "wait-load.sh"
reset
STUB_LOAD=80.00 "$repo/scripts/wait-load.sh" 50 0 2>"$root/err"; status=$?
expect "a load over the limit exits 75 after the max wait" "$status $(refusal)" \
    "75 gave up after N s waiting for the load to fall to 50: the 1-minute load is 80.00, over 50 (WORKOUT_LOAD_LIMIT)"
reset
STUB_LOAD=80.00 "$repo/scripts/wait-load.sh" 100 0 2>"$root/err"; status=$?
expect "a load under the limit exits 0 and says nothing" "$status $(cat "$root/err")" "0 "
reset
STUB_LOAD=80.00 WORKOUT_LOAD_LIMIT=100 "$repo/scripts/wait-load.sh" 2>"$root/err"; status=$?
expect "with no arguments the limit is WORKOUT_LOAD_LIMIT" "$status" "0"
STUB_LOAD=80.00 WORKOUT_LOAD_LIMIT=0 "$repo/scripts/wait-load.sh" 100 0 2>"$root/err"; status=$?
expect "an argument overrides WORKOUT_LOAD_LIMIT before it is checked" "$status $(cat "$root/err")" "0 "
"$repo/scripts/wait-load.sh" fifty 2>"$root/err"; status=$?
expect "a limit that is not a whole number is a usage error" "$status $(cat "$root/err")" "2 WORKOUT_LOAD_LIMIT must be a whole number: fifty"
"$repo/scripts/wait-load.sh" --help 2>"$root/err"; status=$?
expect "--help prints the usage" "$status $(head -1 "$root/err")" "2 Usage: scripts/wait-load.sh [limit] [max-wait]"

printf '\npassed %d, failed %d\n' "$pass" "$fail"
[ "$fail" = 0 ]
