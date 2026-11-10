#!/usr/bin/env bash
set -uo pipefail

# shellcheck source=scripts/tests/test-sim-harness.sh
. "$(dirname "${BASH_SOURCE[0]}")/test-sim-harness.sh"

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
run env STUB_RC=0 STUB_RELEASE="$release" WORKOUT_TEST_RUN_LIMIT=1
kill "$releaser" 2>/dev/null
wait "$releaser" 2>/dev/null
if [ "$status" = 124 ] && [ ! -e "$release" ] \
    && grep -q 'the test run outlived WORKOUT_TEST_RUN_LIMIT (1 s), so it was stopped' "$root/err" \
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

printf '\n%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" = 0 ]
