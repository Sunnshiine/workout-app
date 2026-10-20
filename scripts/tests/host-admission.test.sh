#!/bin/bash
set -uo pipefail

# shellcheck source=scripts/tests/host-admission-harness.sh
. "$(dirname "${BASH_SOURCE[0]}")/host-admission-harness.sh"

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
