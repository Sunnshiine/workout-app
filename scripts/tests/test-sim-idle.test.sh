#!/usr/bin/env bash
set -uo pipefail

# shellcheck source=scripts/tests/test-sim-harness.sh
. "$(dirname "${BASH_SOURCE[0]}")/test-sim-harness.sh"

# xcodebuild prints its log, then sleeps STUB_HANG seconds and exits 0, as one that never exits after its
# last test does until something stops it.
export WORKOUT_TEST_IDLE_SECONDS=1 WORKOUT_TEST_IDLE_POLL_SECONDS=1 HOME=$root/home
export STUB_LOG=$root/xcodebuild.log STUB_OUT=$root/out STUB_SEEN=$root/seen STUB_RC=0
stopped="stopped xcodebuild test-without-building: no output and almost no CPU for 1 s after its last test finished (WORKOUT_TEST_IDLE_SECONDS)"
expect() { if [ "$2" = "$3" ]; then ok "$1"; else bad "$1"; printf '    got:\n%s\n    want:\n%s\n    stderr:\n%s\n' "$2" "$3" "$(cat "$root/err")"; fi; }
hang() {
    local seconds=$1 began=$SECONDS
    shift
    rm -f "$root/seen" "$root/load-read"
    STUB_HANG=$seconds PATH="$root/bin:$PATH" "$repo/scripts/test-sim.sh" --no-build --sim "$sim" "$@" >"$root/out" 2>"$root/err"
    status=$?
    took=$((SECONDS - began))
}
last() { tail -1 "$root/out" | sed 's/.* exit=\([0-9]*\) .*/exit=\1/'; }

zwsp=$'\xe2\x80\x8b'
printf '%s\n' "◇ Test run started." "${zwsp}Test Suite 'All tests' passed at 2026-11-10 10:00:00.000." \
    $'\e[32m✔\e[0m Test run with 2 tests in 1 suite passed after 0.100 seconds.' >"$root/xcodebuild.log"
hang 120 unit
expect "a unit run whose bundle printed both end lines, then sat silent and idle, is stopped within the bound and exits 0" \
    "$status $(cat "$root/err") | $(last) $([ "$took" -lt 120 ] && echo before-it-exited-itself)" \
    "0 $stopped | exit=0 before-it-exited-itself"

printf '%s\n' "◇ Test run started." "✘ Test logsASet() failed after 0.100 seconds with 1 issue." \
    "Test Suite 'All tests' failed at 2026-11-10 10:00:00.000." "✘ Test run with 2 tests in 1 suite failed after 0.100 seconds with 1 issue." >"$root/xcodebuild.log"
hang 120 unit
expect "a stopped run whose log names a failing test exits 65, as xcodebuild does on failing tests" \
    "$status $(cat "$root/err") | $(last)" "65 $stopped | exit=65"

printf '%s\n' "Test Suite 'Selected tests' passed at 2026-11-10 10:00:00.000." \
    "	 Executed 1 test, with 0 failures (0 unexpected) in 0.100 (0.100) seconds" >"$root/xcodebuild.log"
hang 120 WorkoutTrackerUITests/WorkoutTrackerUISmokeTests
expect "a UI selection, XCTest alone, is stopped after its XCTest end line" "$status $(cat "$root/err" | grep -v '^keyboard:')" "0 $stopped"

printf '%s\n' "◇ Test run started." >"$root/xcodebuild.log"
hang 4 unit
expect "a silent run that printed no end line is not stopped, and exits on its own" \
    "$status $(grep -c '^stopped xcodebuild' "$root/err")" "65 0"

printf '%s\n' "Test Suite 'All tests' passed at 2026-11-10 10:00:00.000." \
    "	 Executed 1 test, with 0 failures (0 unexpected) in 0.100 (0.100) seconds" >"$root/xcodebuild.log"
hang 4 unit
expect "a unit run that printed its XCTest end line but not Swift Testing's is not stopped" \
    "$status $(grep -c '^stopped xcodebuild' "$root/err")" "0 0"

printf '%s\n' "Test Suite 'Selected tests' passed at 2026-11-10 10:00:00.000." \
    "✔ Test run with 2 tests in 1 suite passed after 0.100 seconds." >"$root/xcodebuild.log"
hang 4 unit WorkoutTrackerUITests/WorkoutTrackerUISmokeTests
expect "a unit and UI run with one XCTest end line of the two it needs is not stopped" \
    "$status $(grep -c '^stopped xcodebuild' "$root/err")" "0 0"

hang 120 unit
expect "a stopped run keeps the lease its simulator is on" "$status $(PATH="$root/bin:$PATH" simlock list --leases | grep -c "dev_$sim")" "0 1"

printf '%s\n' "◇ Test run started." "Test Suite 'All tests' passed at 2026-11-10 10:00:00.000." \
    "✔ Test run with 2 tests in 1 suite passed after 0.100 seconds." >"$root/xcodebuild.log"
# A spinning process can be starved below 1% of a CPU for a second or two on a loaded host, so these
# windows are 4 s.
busy() {
    rm -f "$root/seen" "$root/load-read"
    env "$@" WORKOUT_TEST_IDLE_SECONDS=4 PATH="$root/bin:$PATH" "$repo/scripts/test-sim.sh" --no-build --sim "$sim" unit >"$root/out" 2>"$root/err"
}
busy STUB_SPIN=10
expect "a run that prints nothing after its end lines but keeps its CPU busy is not stopped, and exits on its own" \
    "$? $(grep -c '^stopped xcodebuild' "$root/err")" "0 0"

busy STUB_CHILD_SPIN=10
expect "a run whose child keeps its CPU busy while xcodebuild waits on it is not stopped" \
    "$? $(grep -c '^stopped xcodebuild' "$root/err")" "0 0"

busy STUB_BUSY_CHILD_EXITS=1
expect "a busy run is not stopped when a child that used more CPU than the window exits inside it" \
    "$? $(grep -c '^stopped xcodebuild' "$root/err")" "0 0"

# A run stopped by a signal stops its watchers with it, though one would sleep out a 30 s poll. Python resets
# SIGINT, which a background job ignores.
printf '%s\n' "◇ Test run started." >"$root/xcodebuild.log"
for sig in TERM INT HUP ALRM; do
    rm -f "$root/seen" "$root/load-read"
    STUB_SLEEP=40 WORKOUT_TEST_IDLE_POLL_SECONDS=30 PATH="$root/bin:$PATH" python3 -c 'import os, signal, sys; signal.signal(signal.SIGINT, signal.SIG_DFL); os.execvp(sys.argv[1], sys.argv[1:])' \
        "$repo/scripts/test-sim.sh" --no-build --sim "$sim" unit >"$root/out" 2>"$root/err" &
    pid=$!
    born=$(proc_stamp "$pid")
    for _ in $(seq 100); do [ -e "$root/seen" ] && break; sleep 0.1; done
    sleep 1
    signal_same "$sig" "$pid" "$born"
    wait "$pid"
    status=$?
    sleep 2
    expect "a run stopped by SIG$sig leaves no watcher, heartbeat or xcodebuild behind" \
        "$status $(pgrep -f "$repo/scripts/test-sim.sh" | wc -l | tr -d ' ') $(pgrep -f "$root/bin/xcodebuild" | wc -l | tr -d ' ')" \
        "$((128 + $(kill -l "$sig"))) 0 0"
done

# A watcher whose script was SIGKILLed keeps bounding xcodebuild, and stops when xcodebuild has gone. Forcing
# the kernel to hand xcodebuild's pid to another process takes about 100,000 forks, so the harness's ps
# reports a new start time for the pid named in $root/recycled: to the watcher, that pid now belongs to a
# bystander.
killed_run() {
    rm -f "$root/seen" "$root/load-read" "$root/recycled"
    env "$@" WORKOUT_TEST_IDLE_SECONDS=4 WORKOUT_LEASE_RENEW_SECONDS=1 STUB_RECYCLED=$root/recycled PATH="$root/recycled-bin:$root/bin:$PATH" \
        "$repo/scripts/test-sim.sh" --no-build --sim "$sim" unit >"$root/out" 2>"$root/err" &
    pid=$!
    born=$(proc_stamp "$pid")
    for _ in $(seq 100); do [ -e "$root/seen" ] && break; sleep 0.1; done
    sleep 0.5
    target=$(pgrep -f "$root/bin/xcodebuild")
    target_born=$(proc_stamp "$target")
    signal_same KILL "$pid" "$born"
    wait "$pid" 2>/dev/null
}
printf '%s\n' "◇ Test run started." "Test Suite 'All tests' passed at 2026-11-10 10:00:00.000." \
    "✔ Test run with 2 tests in 1 suite passed after 0.100 seconds." >"$root/xcodebuild.log"
killed_run STUB_SLEEP=60
echo "$target" >"$root/recycled"
sleep 8
expect "after test-sim.sh is SIGKILLed, a bystander that took xcodebuild's pid outlives the watcher's ticks" \
    "$(kill -0 "$target" 2>/dev/null && echo alive) $(pgrep -f "$repo/scripts/test-sim.sh" | wc -l | tr -d ' ')" "alive 0"
rm -f "$root/recycled"
signal_same TERM "$target" "$target_born"

killed_run STUB_SLEEP=2
sleep 4
expect "after test-sim.sh is SIGKILLed, its watcher exits within a poll of xcodebuild exiting" \
    "$(pgrep -f "$repo/scripts/test-sim.sh" | wc -l | tr -d ' ') $(pgrep -f "$root/bin/xcodebuild" | wc -l | tr -d ' ')" "0 0"

printf '%s\n' "◇ Test run started." "Test Suite 'All tests' passed at 2026-11-10 10:00:00.000." \
    "✔ Test run with 2 tests in 1 suite passed after 0.100 seconds." >"$root/xcodebuild.log"
killed_run STUB_SLEEP=60
for _ in $(seq 60); do kill -0 "$target" 2>/dev/null || break; sleep 0.5; done
sleep 1
expect "after test-sim.sh is SIGKILLed, its watcher still stops the idle xcodebuild it left behind" \
    "$(kill -0 "$target" 2>/dev/null && echo alive) $(pgrep -f "$repo/scripts/test-sim.sh" | wc -l | tr -d ' ')" " 0"

WORKOUT_TEST_IDLE_SECONDS=0 hang 1 unit
expect "WORKOUT_TEST_IDLE_SECONDS under 1 exits 2" "$status $(cat "$root/err")" "2 WORKOUT_TEST_IDLE_SECONDS must be at least 1: 0"

printf '\npassed %s, failed %s\n' "$pass" "$fail"
[ "$fail" -eq 0 ] || exit 1
