#!/usr/bin/env bash
set -uo pipefail

# shellcheck source=scripts/tests/test-sim-harness.sh
. "$(dirname "${BASH_SOURCE[0]}")/test-sim-harness.sh"
# stop NAME...: SIGTERM each process this test started and saved as $NAME, with its stamp in $NAME_stamp.
stop() {
    local name pid stamp stamp_var
    for name in "$@"; do
        pid=${!name}
        stamp_var=${name}_stamp
        stamp=${!stamp_var:-}
        signal_same TERM "$pid" "$stamp"
    done
    return 0
}
# kill_script SIG: signals the test-sim.sh this test started, found and stamped at once.
kill_script() {
    local pid
    pid=$(pgrep -f "$repo/scripts/test-sim.sh --no-build" | head -1)
    [ -n "$pid" ] && signal_same "$1" "$pid" "$(proc_stamp "$pid")"
}

passing="✔ Test run with 1 test in 1 suite passed after 0.010 seconds.
** TEST EXECUTE SUCCEEDED **"
printf '%s\n' "$passing" >"$root/xcodebuild.log"

run() {
    STUB_LOG=$root/xcodebuild.log STUB_OUT=$root/out STUB_SEEN=$root/seen HOME=$root/home PATH="$root/bin:$PATH" \
        "$@" "$repo/scripts/test-sim.sh" --no-build --sim "$sim" unit >"$root/out" 2>"$root/err"
    status=$?
    rm -f "$root/load-read"
}

# follows FLAG VALUE: the stub's argument list holds FLAG with VALUE right after it.
follows() { grep -A1 -x -- "$1" "$STUB_ARGS" | sed -n 2p | grep -qx -- "$2"; }

echo "each test gets an execution-time allowance, so one hung test cannot stall the run"
run env STUB_RC=0
if [ "$status" = 0 ] && follows -test-timeouts-enabled YES \
    && follows -default-test-execution-time-allowance 60 && follows -maximum-test-execution-time-allowance 300; then
    ok "the default allowances are 60 s, and 300 s at most"
else
    bad "the default allowances are 60 s, and 300 s at most: exit $status, args:"
    sed 's/^/    /' "$STUB_ARGS"
fi

run env STUB_RC=0 WORKOUT_TEST_ALLOWANCE=7 WORKOUT_TEST_MAX_ALLOWANCE=9
if [ "$status" = 0 ] && follows -default-test-execution-time-allowance 7 && follows -maximum-test-execution-time-allowance 9; then
    ok "WORKOUT_TEST_ALLOWANCE and WORKOUT_TEST_MAX_ALLOWANCE set them"
else
    bad "WORKOUT_TEST_ALLOWANCE and WORKOUT_TEST_MAX_ALLOWANCE set them: exit $status"
fi

run env STUB_RC=0 WORKOUT_TEST_ALLOWANCE=soon
if [ "$status" = 2 ] && grep -q 'WORKOUT_TEST_ALLOWANCE must be a whole number' "$root/err"; then
    ok "an allowance that is not a number is a usage error"
else
    bad "an allowance that is not a number is a usage error: exit $status: $(cat "$root/err")"
fi

echo "a run that outlives WORKOUT_TEST_RUN_LIMIT is stopped and exits 124"
# xcodebuild that never finishes, as one that idled after its last test did. Without the bound
# this release file ends it after 30 s with status 0, so the check fails instead of hanging.
release=$root/release
(sleep 30 && touch "$release") &
releaser=$!
releaser_stamp=$(proc_stamp "$releaser")
run env STUB_RC=0 STUB_RELEASE="$release" WORKOUT_TEST_RUN_LIMIT=1
stop releaser
wait "$releaser" 2>/dev/null
if [ "$status" = 124 ] && [ ! -e "$release" ] \
    && grep -q "the test run outlived WORKOUT_TEST_RUN_LIMIT (1 s), so it was stopped; the log's last lines show where it stood: $repo/.build/test-sim/[0-9-]*-test.log\$" "$root/err" \
    && [ "$(tail -1 "$root/out")" = "$(result unit 124)" ]; then
    ok "the stuck run is stopped, and test-sim says why"
else
    bad "the stuck run is stopped, and test-sim says why: exit $status"
    printf '    stdout:\n%s\n    stderr:\n%s\n' "$(cat "$root/out")" "$(cat "$root/err")"
fi
if [ -z "$(find "$root" -name '*.overran')" ]; then
    ok "the overrun marker is cleaned up"
else
    bad "the overrun marker is cleaned up"
fi

run env STUB_RC=0 WORKOUT_TEST_RUN_LIMIT=0
if [ "$status" = 2 ] && grep -q 'WORKOUT_TEST_RUN_LIMIT must be at least 1' "$root/err"; then
    ok "a run limit of 0 is a usage error"
else
    bad "a run limit of 0 is a usage error: exit $status"
fi

echo "a stub xcodebuild that ignores SIGTERM gets SIGKILL after WORKOUT_TEST_KILL_GRACE"
rm -f "$release"
(sleep 30 && touch "$release") &
releaser=$!
releaser_stamp=$(proc_stamp "$releaser")
run env STUB_RC=0 STUB_DEAF=1 STUB_RELEASE="$release" WORKOUT_TEST_RUN_LIMIT=1 WORKOUT_TEST_KILL_GRACE=1
stop releaser
wait "$releaser" 2>/dev/null
if [ "$status" = 124 ] && [ ! -e "$release" ]; then
    ok "the deaf run is killed, and test-sim exits 124"
else
    bad "the deaf run is killed, and test-sim exits 124: exit $status, released: $([ -e "$release" ] && echo yes || echo no)"
fi

echo "no watchdog outlives test-sim.sh, however it ends"
# GONE_WITHIN bounds how long the checks below wait for a process to quit. STUCK_FOR, well past it, is
# how long a stub xcodebuild that nothing stops runs before it ends itself, so a check fails rather
# than hangs.
gone_within=${GONE_WITHIN:-20}
stuck_for=${STUCK_FOR:-$((gone_within * 4))}
watchdogs() { pgrep -f "$root/repo/.build/test-sim/.*overran" || true; }
runs() { pgrep -f "$root/bin/xcodebuild" || true; }
gone() {
    local deadline=$((SECONDS + gone_within))
    while [ -n "$("$1")" ] && [ $SECONDS -lt $deadline ]; do sleep 0.1; done
    [ -z "$("$1")" ]
}

run env STUB_RC=0
if [ "$status" = 0 ] && [ -z "$(watchdogs)" ] && [ -z "$(runs)" ]; then
    ok "a run that ends on its own leaves no watchdog and no xcodebuild"
else
    bad "a run that ends on its own leaves no watchdog and no xcodebuild: exit $status, left: $(watchdogs) $(runs)"
fi

# ended_by HOW: start a run that never finishes on its own, end test-sim.sh with HOW, and check
# that the watchdog quits and that a pipe on test-sim.sh closes before the stub xcodebuild ends.
ended_by() {
    local how=$1 started=$root/started
    rm -f "$release" "$started"
    (sleep "$stuck_for" && touch "$release") &
    releaser=$!
releaser_stamp=$(proc_stamp "$releaser")
    # A background job starts with SIGINT ignored, and bash cannot trap a signal ignored at entry, so
    # test-sim.sh gets the default back, as it has when run from a terminal.
    (
        STUB_LOG=$root/xcodebuild.log STUB_OUT=$root/out STUB_SEEN=$root/seen STUB_TOUCH=$started STUB_RC=0 \
            STUB_RELEASE="$release" WORKOUT_TEST_RUN_LIMIT=600 HOME=$root/home PATH="$root/bin:$PATH" \
            perl -e '$SIG{INT} = "DEFAULT"; exec @ARGV' "$repo/scripts/test-sim.sh" --no-build --sim "$sim" unit 2>&1 \
            | cat >"$root/ended"
        [ -e "$release" ] && echo late >"$root/pipe" || echo early >"$root/pipe"
    ) &
    local piped=$!
    while [ ! -e "$started" ] && [ ! -e "$release" ]; do sleep 0.1; done
    if [ -z "$(watchdogs)" ] || ! kill_script "$how"; then
        bad "$how: test-sim.sh and its watchdog were running"
    else
        # SIGKILL runs no trap, so the watchdog stays to bound the xcodebuild left running.
        if [ "$how" = KILL ]; then
            sleep 1
            if [ -n "$(watchdogs)" ]; then ok "$how: the watchdog stays while xcodebuild runs"; else bad "$how: the watchdog stays while xcodebuild runs"; fi
        elif gone watchdogs; then
            ok "$how: the watchdog quits with test-sim.sh"
        else
            bad "$how: the watchdog quits with test-sim.sh: $(watchdogs)"
        fi
        if [ "$how" = KILL ]; then
            :
        elif gone runs; then
            ok "$how: test-sim.sh stops its xcodebuild"
        else
            bad "$how: test-sim.sh stops its xcodebuild: $(runs)"
        fi
    fi
    wait "$piped"
    if [ "$(cat "$root/pipe" 2>/dev/null)" = early ]; then
        ok "$how: a pipe on test-sim.sh closes when it ends"
    else
        bad "$how: a pipe on test-sim.sh closes when it ends"
    fi
    # Each trapped signal ends with a result line that names the script's own status; SIGKILL runs no trap.
    local want
    # SIGALRM also prints a line naming it.
    case $how in TERM) want=143 ;; INT) want=130 ;; HUP) want=129 ;; ALRM) want=142 ;; KILL) want= ;; esac
    if [ -z "$want" ]; then
        :
    elif tail -1 "$root/ended" | grep -q " exit=$want " && { [ "$how" != ALRM ] || grep -q 'stopped by SIGALRM' "$root/ended"; }; then
        ok "$how: the result line reads exit=$want"
    else
        bad "$how: the result line reads exit=$want: $(tail -2 "$root/ended" | tr '\n' '|')"
    fi
    # After SIGKILL the stub xcodebuild runs on until it sees the release file.
    touch "$release"
    gone runs || bad "$how: the stub xcodebuild ended once released: $(runs)"
    if gone watchdogs; then ok "$how: the watchdog quits once xcodebuild has exited"; else bad "$how: the watchdog quits once xcodebuild has exited: $(watchdogs)"; fi
    stop releaser
    wait "$releaser" 2>/dev/null
    rm -f "$release"
}
ended_by TERM
ended_by INT
ended_by HUP
ended_by ALRM
ended_by KILL

echo "after a SIGKILL of test-sim.sh, the watchdog still bounds xcodebuild, and signals nothing else"
rm -f "$release"
(sleep "$stuck_for" && touch "$release") &
releaser=$!
releaser_stamp=$(proc_stamp "$releaser")
(
    STUB_LOG=$root/xcodebuild.log STUB_OUT=$root/out STUB_SEEN=$root/seen STUB_TOUCH=$root/started STUB_RC=0 \
        STUB_RELEASE="$release" WORKOUT_TEST_RUN_LIMIT=4 WORKOUT_TEST_KILL_GRACE=1 HOME=$root/home PATH="$root/bin:$PATH" \
        "$repo/scripts/test-sim.sh" --no-build --sim "$sim" unit >/dev/null 2>&1
) &
rm -f "$root/started"
while [ ! -e "$root/started" ] && [ ! -e "$release" ]; do sleep 0.1; done
kill_script KILL
if gone runs; then ok "the watchdog stops the xcodebuild a SIGKILLed test-sim.sh left"; else bad "the watchdog stops the xcodebuild a SIGKILLed test-sim.sh left: $(runs)"; fi
stop releaser
wait 2>/dev/null

# The stub exits, a bystander starts, and the watchdog's next tick must leave it alone.
rm -f "$release"
(sleep "$stuck_for" && touch "$release") &
releaser=$!
releaser_stamp=$(proc_stamp "$releaser")
(
    STUB_LOG=$root/xcodebuild.log STUB_OUT=$root/out STUB_SEEN=$root/seen STUB_TOUCH=$root/started STUB_RC=0 \
        STUB_RELEASE="$release" WORKOUT_TEST_RUN_LIMIT=3 WORKOUT_TEST_KILL_GRACE=1 HOME=$root/home PATH="$root/bin:$PATH" \
        "$repo/scripts/test-sim.sh" --no-build --sim "$sim" unit >/dev/null 2>&1
) &
rm -f "$root/started"
while [ ! -e "$root/started" ] && [ ! -e "$release" ]; do sleep 0.1; done
kill_script KILL
touch "$release"
gone runs
sleep 30 &
bystander=$!
bystander_stamp=$(proc_stamp "$bystander")
sleep 5
if kill -0 "$bystander" 2>/dev/null && [ -z "$(watchdogs)" ]; then
    ok "once xcodebuild exits the watchdog quits, and a process started after it survives"
else
    bad "once xcodebuild exits the watchdog quits, and a process started after it survives: watchdog $(watchdogs)"
fi
stop bystander releaser
wait 2>/dev/null

echo "test-sim.sh signals only the xcodebuild that carries the start time it read at launch"
rm -f "$release" "$root/started" "$root/recycled"
(sleep "$stuck_for" && touch "$release") &
releaser=$!
releaser_stamp=$(proc_stamp "$releaser")
(
    STUB_LOG=$root/xcodebuild.log STUB_OUT=$root/out STUB_SEEN=$root/seen STUB_TOUCH=$root/started STUB_RC=0 \
        STUB_RELEASE="$release" STUB_RECYCLED=$root/recycled WORKOUT_TEST_RUN_LIMIT=600 WORKOUT_TEST_KILL_GRACE=1 \
        HOME=$root/home PATH="$root/recycled-bin:$root/bin:$PATH" \
        "$repo/scripts/test-sim.sh" --no-build --sim "$sim" unit >/dev/null 2>&1
    echo $? >"$root/recycled-status"
) &
recycled_run=$!
while { [ ! -e "$root/started" ] || [ -z "$(watchdogs)" ]; } && [ ! -e "$release" ]; do sleep 0.1; done
sleep 1
runs >"$root/recycled"
kill_script TERM
sleep 3
if [ -n "$(runs)" ] && [ ! -e "$release" ]; then
    ok "after SIGTERM, an xcodebuild pid whose start time changed gets no signal"
else
    bad "after SIGTERM, an xcodebuild pid whose start time changed gets no signal: $( [ -e "$release" ] && echo released || echo signalled)"
fi
touch "$release"
gone runs
wait "$recycled_run"
if [ "$(cat "$root/recycled-status" 2>/dev/null)" = 143 ]; then ok "test-sim.sh then exits 143"; else bad "test-sim.sh then exits 143: $(cat "$root/recycled-status" 2>/dev/null)"; fi
stop releaser
wait 2>/dev/null
rm -f "$release"

echo "the watchdog signals only the process that carries the start time it was given"
watchdog=$repo/scripts/test-run-watchdog.pl
mark=$root/mark
lstart() { ps -o lstart= -p "$1"; }
sleep 30 &
child=$!
rm -f "$mark"
# A wrong start time is what a recycled pid shows: the same number, another process.
started=$SECONDS
"$watchdog" 1 1 "$child" "Thu Jan  1 00:00:00 1970" "$mark"
if kill -0 "$child" 2>/dev/null && [ ! -e "$mark" ] && [ $((SECONDS - started)) -lt "$gone_within" ]; then
    ok "a pid whose start time differs gets no signal, and the watchdog quits at once"
else
    bad "a pid whose start time differs gets no signal, and the watchdog quits at once"
fi
"$watchdog" 1 1 "$child" "$(lstart "$child")" "$mark"
wait "$child"
child_status=$?
if [ "$child_status" = 143 ] && [ -e "$mark" ]; then
    ok "the process it was given gets SIGTERM past the limit, and the marker is made"
else
    bad "the process it was given gets SIGTERM past the limit, and the marker is made: status $child_status"
fi

sh -c 'trap "" TERM; sleep 30' &
child=$!
sleep 0.2
rm -f "$mark"
"$watchdog" 1 1 "$child" "$(lstart "$child")" "$mark"
wait "$child"
child_status=$?
if [ "$child_status" = 137 ]; then ok "one that ignores SIGTERM gets SIGKILL after the grace"; else bad "one that ignores SIGTERM gets SIGKILL after the grace: status $child_status"; fi

true &
child=$!
gone_start=$(lstart "$child")
wait "$child"
rm -f "$mark"
started=$SECONDS
"$watchdog" 600 1 "$child" "$gone_start" "$mark"
if [ ! -e "$mark" ] && [ $((SECONDS - started)) -lt "$gone_within" ]; then
    ok "a run that already ended gets no signal, and the watchdog quits at once"
else
    bad "a run that already ended gets no signal, and the watchdog quits at once: $((SECONDS - started)) s"
fi

if "$watchdog" 1 1 x y "$mark" 2>/dev/null; then bad "a pid that is not a number is a usage error"; else ok "a pid that is not a number is a usage error"; fi

printf '\n%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" = 0 ]
