#!/usr/bin/env bash
set -uo pipefail
# CI sets GITHUB_ACTIONS, under which test-log-summary.sh adds ::error lines these checks do not expect.
unset GITHUB_ACTIONS

script_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
root=$(mktemp -d) || exit 3
# Every process a hunt here starts runs a stub under $root/bin, so this ends exactly the harness's own.
trap 'pkill -f "$root/" 2>/dev/null; rm -rf "$root"' EXIT
repo=$root/repo
mkdir -p "$repo/scripts" "$root/bin"
find "$script_dir/.." -maxdepth 1 -type f -exec cp {} "$repo/scripts/" \;
export WORKOUT_DISK_FLOOR=0 WORKOUT_HOST_LOCK_DIR=$root/locks
pass=0
fail=0

ok()  { pass=$((pass + 1)); printf '  ok   %s\n' "$1"; }
bad() { fail=$((fail + 1)); printf '  FAIL %s\n' "$1"; }

cat >"$root/bin/swift" <<'STUB'
#!/bin/sh
[ "$1" = test ] || { [ -z "${STUB_BUILD_LOG:-}" ] || cat "$STUB_BUILD_LOG"; exit "${STUB_BUILD_RC:-0}"; }
while [ $# -gt 0 ]; do [ "$1" = --xunit-output ] && xunit=$2; shift; done
[ -z "${STUB_HOLD:-}" ] || { "${0%/*}/spin" </dev/null >/dev/null 2>&1 & echo $! >"$STUB_HOLD"; while :; do sleep 0.1; done; }
[ -z "${STUB_TESTS:-}" ] ||
    printf '<testsuites>\n  <testsuite name="TestResults" errors="0" tests="%s" failures="0">\n' "$STUB_TESTS" \
        >"${xunit%.xml}-swift-testing.xml"
cat "$STUB_LOG"
exit "$STUB_RC"
STUB
printf '#!/bin/sh\nexit 1\n' >"$root/bin/gh"
printf '#!/bin/sh\nwhile :; do sleep 0.2; done\n' >"$root/bin/spin"
ln -s spin "$root/bin/yes"
chmod +x "$root/bin/swift" "$root/bin/gh" "$root/bin/spin"

check() {
    local name=$1 want_status=$2 want_out=$3 swift_status=$4 log=$5
    printf '%s\n' "$log" >"$root/swift.log"
    STUB_LOG=$root/swift.log STUB_RC=$swift_status STUB_TESTS=${STUB_TESTS-1} PATH="$root/bin:$PATH" \
        "$repo/scripts/flake-hunt.sh" --load 0 --repetitions 1 >"$root/out" 2>"$root/err"
    local status=$?
    local out
    out=$(grep -v -e '^log: ' -e '^run: ' "$root/out")
    local first
    first=$(head -1 "$root/out")
    [ -f "${first#log: }" ] || bad "$name: the first line is not the log path: $first"
    if [ "$status" = "$want_status" ] && [ "$out" = "$want_out" ]; then
        ok "$name"
    else
        bad "$name: exit $status (want $want_status)"
        printf '    stdout:\n%s\n    stderr:\n%s\n' "$out" "$(cat "$root/err")"
    fi
}

check "a passing run with a known issue prints its summary" 0 \
"━ Test run with 1020 tests in 11 suites passed after 2.921 seconds with 1 known issue." 0 \
"◇ Test run started.
━ Test replanningWhenTheRefetchFails() recorded a known issue at SyncCoordinatorReplanTests.swift:693:9: Expectation failed
✔ Test canMoveOnIsFalseOnLastSession() passed after 0.010 seconds.
━ Test run with 1020 tests in 11 suites passed after 2.921 seconds with 1 known issue."

check "a passing run prints its summary" 0 \
"✔ Test run with 1020 tests in 11 suites passed after 2.921 seconds." 0 \
"◇ Test run started.
✔ Test canMoveOnIsFalseOnLastSession() passed after 0.010 seconds.
✔ Test run with 1020 tests in 11 suites passed after 2.921 seconds."

check "a failing run prints each issue, the failed test, and the summary" 1 \
"✘ Test failsOnPurpose() recorded an issue at Issue769FailingProbeTests.swift:5:9: Expectation failed: 1 + 1 == 3
✘ Test envelope(height:setCount:) recorded an issue with 2 arguments height → 70.0, setCount → 3 at SessionStageBranchEnvelopeTests.swift:19:9: Expectation failed
✘ Test failsOnPurpose() failed after 0.001 seconds with 1 issue.
✘ Test run with 1021 tests in 12 suites failed after 2.172 seconds with 3 issues (including 1 known issue)." 1 \
"◇ Test run started.
✘ Test failsOnPurpose() recorded an issue at Issue769FailingProbeTests.swift:5:9: Expectation failed: 1 + 1 == 3
━ Test replanningWhenTheRefetchFails() recorded a known issue at SyncCoordinatorReplanTests.swift:693:9: Expectation failed
✘ Test envelope(height:setCount:) recorded an issue with 2 arguments height → 70.0, setCount → 3 at SessionStageBranchEnvelopeTests.swift:19:9: Expectation failed
✘ Test failsOnPurpose() failed after 0.001 seconds with 1 issue.
✘ Test run with 1021 tests in 12 suites failed after 2.172 seconds with 3 issues (including 1 known issue)."

check "a test that records many issues prints its first three" 1 \
"✘ Test grows(n:) recorded an issue with 1 argument n → 1 at GrowSuite.swift:5:9: Expectation failed: n == 0
✘ Test grows(n:) recorded an issue with 1 argument n → 2 at GrowSuite.swift:5:9: Expectation failed: n == 0
✘ Test grows(n:) recorded an issue with 1 argument n → 3 at GrowSuite.swift:5:9: Expectation failed: n == 0
✘ Test grows(n:) recorded more issues; the log holds every one
✘ Test grows(n:) failed after 0.001 seconds with 5 issues.
✘ Test run with 1 test in 1 suite failed after 0.002 seconds with 5 issues." 1 \
"◇ Test run started.
✘ Test grows(n:) recorded an issue with 1 argument n → 1 at GrowSuite.swift:5:9: Expectation failed: n == 0
✘ Test grows(n:) recorded an issue with 1 argument n → 2 at GrowSuite.swift:5:9: Expectation failed: n == 0
✘ Test grows(n:) recorded an issue with 1 argument n → 3 at GrowSuite.swift:5:9: Expectation failed: n == 0
✘ Test grows(n:) recorded an issue with 1 argument n → 4 at GrowSuite.swift:5:9: Expectation failed: n == 0
✘ Test grows(n:) recorded an issue with 1 argument n → 5 at GrowSuite.swift:5:9: Expectation failed: n == 0
✘ Test grows(n:) failed after 0.001 seconds with 5 issues.
✘ Test run with 1 test in 1 suite failed after 0.002 seconds with 5 issues."

STUB_TESTS= check "a test process that crashes before its xunit file exits 1, not as if no test ran, and names the crash" 1 \
"WorkoutTrackerTests/ExerciseNameTests.swift:11: Fatal error: Unexpectedly found nil while unwrapping an Optional value
error: Exited with unexpected signal code 5" 1 \
"◇ Test run started.
✔ Test canMoveOnIsFalseOnLastSession() passed after 0.010 seconds.
WorkoutTrackerTests/ExerciseNameTests.swift:11: Fatal error: Unexpectedly found nil while unwrapping an Optional value
error: Exited with unexpected signal code 5"

STUB_TESTS= check "a swift test that fails before any test runs prints why" 1 \
"error: no tests found; create a target in the 'Tests' directory" 1 \
"error: no tests found; create a target in the 'Tests' directory"

STUB_TESTS=0 check "an XCTest-only run, whose tests Swift Testing's xunit file does not count, passes" 0 \
"	 Executed 1 test, with 0 failures (0 unexpected) in 0.000 (0.001) seconds" 0 \
"Test Suite 'Selected tests' started at 2026-10-25 12:29:12.672.
Test Suite 'PTests.xctest' started at 2026-10-25 12:29:12.673.
Test Suite 'XT' started at 2026-10-25 12:29:12.673.
Test Case '-[PTests.XT testRealX]' started.
Test Case '-[PTests.XT testRealX]' passed (0.000 seconds).
Test Suite 'XT' passed at 2026-10-25 12:29:12.673.
	 Executed 1 test, with 0 failures (0 unexpected) in 0.000 (0.000) seconds
Test Suite 'PTests.xctest' passed at 2026-10-25 12:29:12.673.
	 Executed 1 test, with 0 failures (0 unexpected) in 0.000 (0.000) seconds
Test Suite 'Selected tests' passed at 2026-10-25 12:29:12.673.
	 Executed 1 test, with 0 failures (0 unexpected) in 0.000 (0.001) seconds"

no_test() {
    local name=$1 want_err=$2
    shift 2
    printf 'warning: No matching test cases were run\n' >"$root/swift.log"
    STUB_LOG=$root/swift.log STUB_RC=0 STUB_TESTS=0 PATH="$root/bin:$PATH" \
        "$repo/scripts/flake-hunt.sh" --load 0 --repetitions 1 "$@" >"$root/out" 2>"$root/err"
    local status=$? log
    log=$(head -1 "$root/out")
    want_err="$want_err; see ${log#log: }"
    if [ "$status" = 65 ] && [ "$(grep -vc '^run: ' "$root/out")" -eq 1 ] && [ "$(cat "$root/err")" = "$want_err" ]; then
        ok "$name"
    else
        bad "$name: exit $status (want 65)"
        printf '    stdout:\n%s\n    stderr:\n%s\n    want stderr:\n%s\n' "$(cat "$root/out")" "$(cat "$root/err")" "$want_err"
    fi
}

no_test "a filter that matches no test exits 65 and names the filter" \
    "flake-hunt: no test ran; no test matches NoSuchTestMatchesThis" NoSuchTestMatchesThis
no_test "a run with no filter and no test exits 65" "flake-hunt: no test ran"

build_failure() {
    local name=$1 log=$2 want_lines=$3
    printf '%s' "$log" >"$root/build.log"
    STUB_BUILD_LOG=$root/build.log STUB_BUILD_RC=1 PATH="$root/bin:$PATH" \
        "$repo/scripts/flake-hunt.sh" --load 0 --repetitions 1 >"$root/out" 2>"$root/err"
    local status=$? out err want_err
    out=$(cat "$root/out")
    err=$(cat "$root/err")
    want_err="${want_lines:+$want_lines
}build log: ${out#log: }"
    if [ "$status" = 65 ] && [ "$(wc -l <"$root/out")" -eq 1 ] && [ "$err" = "$want_err" ]; then
        ok "$name"
    else
        bad "$name: exit $status (want 65)"
        printf '    stdout:\n%s\n    stderr:\n%s\n    want stderr:\n%s\n' "$out" "$err" "$want_err"
    fi
}

build_failure "a build that fails with no error: line prints its log path and exits 65" \
"Compiling WorkoutTracker
Killed: 9
" ""

many=$(for n in $(seq 20000); do echo "Sources/Foo$n.swift:1:1: error: cannot find 'bar' in scope"; done)
build_failure "a build with more error lines than it prints stops at 20, then prints its log path, and exits 65" \
"$many
" "$(printf '%s\n' "$many" | sed -n 1,20p)"

mkdir -p "$root/calls-bin"
printf '#!/bin/sh\necho "$*" >>"%s/swift-calls"\n' "$root" >"$root/calls-bin/swift"
chmod +x "$root/calls-bin/swift"
WORKOUT_DISK_FLOOR=99999999 WORKOUT_ADMIT_WAIT=0 PATH="$root/calls-bin:$PATH" \
    "$repo/scripts/flake-hunt.sh" --load 0 --repetitions 1 >"$root/out" 2>"$root/err"
status=$?
if [ "$status" = 75 ] && [ ! -e "$root/swift-calls" ] &&
    [ "$(sed -E 's/free disk is [0-9]+ MB/free disk is N MB/' "$root/err")" = "gave up after 0 s waiting for free disk: free disk is N MB on the volume holding $repo, under the floor of 99999999 MB (WORKOUT_DISK_FLOOR) a build needs" ]; then
    ok "free disk under WORKOUT_DISK_FLOOR stops a hunt with 75 before it builds"
else
    bad "free disk under WORKOUT_DISK_FLOOR stops a hunt with 75: exit $status, swift calls: $(cat "$root/swift-calls" 2>/dev/null), $(cat "$root/err")"
fi

loops() { pgrep -f "$root/bin/yes" | wc -l | tr -d ' '; }
loops_settled() { local i=0; while [ "$(loops)" != 0 ] && [ $i -lt 50 ]; do sleep 0.1; i=$((i + 1)); done; loops; }

STUB_LOG=$root/swift.log STUB_RC=0 WORKOUT_RUN='bad name' PATH="$root/bin:$PATH" \
    "$repo/scripts/flake-hunt.sh" --load 3 --repetitions 1 >"$root/out" 2>"$root/err"
status=$?
if [ "$status" = 2 ] && [ "$(loops_settled)" = 0 ] && [ ! -s "$root/out" ] &&
    [ "$(cat "$root/err")" = 'reap.sh: run name must match ^[A-Za-z0-9][A-Za-z0-9._-]{0,63}$: bad name' ]; then
    ok "a WORKOUT_RUN that is not a run name exits 2 before it builds or starts a busy loop"
else
    bad "a WORKOUT_RUN that is not a run name: exit $status, $(loops) busy loops left, stdout: $(cat "$root/out"), stderr: $(cat "$root/err")"
fi

: >"$root/not-a-dir"
STUB_LOG=$root/swift.log STUB_RC=0 WORKOUT_RUN_DIR=$root/not-a-dir PATH="$root/bin:$PATH" \
    "$repo/scripts/flake-hunt.sh" --load 3 --repetitions 1 >"$root/out" 2>"$root/err"
status=$?
if [ "$status" = 1 ] && [ "$(loops_settled)" = 0 ]; then
    ok "a hunt that cannot record its busy loops ends them and exits 1"
else
    bad "a hunt that cannot record its busy loops: exit $status, $(loops) busy loops left, stderr: $(cat "$root/err")"
fi

alive() { local pid n=0; for pid in "$@"; do ! kill -0 "$pid" 2>/dev/null || n=$((n + 1)); done; echo "$n"; }
settled() { local i=0; while [ "$(alive "$@")" != 0 ] && [ $i -lt 50 ]; do sleep 0.1; i=$((i + 1)); done; alive "$@"; }
export WORKOUT_RUN_DIR=$root/runs
printf 'x\n' >"$root/swift.log"
# Starts a hunt whose test process holds, with a child of its own, and sets hunt, recorded, and child.
hold() {
    rm -f "$root/holding"
    STUB_LOG=$root/swift.log STUB_RC=0 STUB_HOLD=$root/holding WORKOUT_RUN=$1 PATH="$root/bin:$PATH" \
        "$repo/scripts/flake-hunt.sh" --load 2 --repetitions 1 >"$root/out" 2>"$root/err" &
    hunt=$!
    local pidfile
    for _ in $(seq 1 100); do
        pidfile=$(echo "$WORKOUT_RUN_DIR"/*/"$1.pids")
        [ -s "$root/holding" ] && [ "$(wc -l <"$pidfile" 2>/dev/null)" -eq 3 ] && break
        sleep 0.1
    done
    recorded=$(cut -f1 "$pidfile" 2>/dev/null | tr '\n' ' ')
    child=$(cat "$root/holding" 2>/dev/null)
}
hold hunt-a
kill -9 "$hunt"; wait "$hunt" 2>/dev/null
# shellcheck disable=SC2086
if [ "$(sed -n 2p "$root/out")" = "run: hunt-a ($repo/scripts/reap.sh hunt-a ends its processes)" ] && [ "$(alive $recorded $child)" = 4 ]; then
    ok "a hunt names its run and records its two busy loops and its test process, which outlive a kill -9 of the hunt"
else
    bad "a hunt names its run and records its processes: $(cat "$root/out") recorded=$recorded child=$child alive=$(alive $recorded $child)"
fi
"$repo/scripts/reap.sh" hunt-a >/dev/null
# shellcheck disable=SC2086
if [ "$(settled $recorded $child)" = 0 ]; then ok "scripts/reap.sh <run> then ends all three and the test process's child"; else bad "reap left $(alive $recorded $child) of: $recorded $child"; fi

hold hunt-b
kill -TERM "$hunt"; wait "$hunt" 2>/dev/null
# shellcheck disable=SC2086
if [ -n "$child" ] && [ "$(settled $recorded $child)" = 0 ]; then
    ok "a SIGTERM to the hunt ends its busy loops, its test process, and that process's child"
else
    bad "a SIGTERM to the hunt left $(alive $recorded $child) of: $recorded $child"
fi

printf '\npassed %s, failed %s\n' "$pass" "$fail"
[ "$fail" -eq 0 ] || exit 1
