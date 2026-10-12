#!/bin/bash
set -uo pipefail

awk_file=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/test-failures.awk
pass=0
fail=0

check() {
    local name=$1 log=$2 want=$3 got
    got=$(printf '%s\n' "$log" | awk -f "$awk_file")
    if [ "$got" = "$want" ]; then
        pass=$((pass + 1))
        printf '  ok   %s\n' "$name"
    else
        fail=$((fail + 1))
        printf '  FAIL %s\n    got:\n%s\n    want:\n%s\n' "$name" "$got" "$want"
    fi
}

check "a swift test log with twelve failures among passing tests names all twelve" \
"[1/1] Planning build
Test Suite 'All tests' started at 2026-10-12 11:00:00.000.
Test Case '-[WorkoutTrackerTests.SyncTests testFlushKeepsOrder]' started.
Test Case '-[WorkoutTrackerTests.SyncTests testFlushKeepsOrder]' passed (0.002 seconds).
Test Case '-[WorkoutTrackerTests.SyncTests testFlushDropsNothing]' started.
/repo/Tests/Unit/SyncTests.swift:12: error: -[WorkoutTrackerTests.SyncTests testFlushDropsNothing] : XCTAssertEqual failed: (\"1\") is not equal to (\"2\")
Test Case '-[WorkoutTrackerTests.SyncTests testFlushDropsNothing]' failed (0.003 seconds).
Test Case '-[WorkoutTrackerTests.SyncTests testRetryAfterFailure]' failed (0.001 seconds).
Test Suite 'All tests' failed at 2026-10-12 11:00:00.010.
	 Executed 3 tests, with 2 failures (0 unexpected) in 0.006 (0.010) seconds
◇ Test run started.
↳ Testing Library Version: 2084
◇ Test canMoveOnIsFalseOnLastSession() started.
✔ Test canMoveOnIsFalseOnLastSession() passed after 0.010 seconds.
✘ Test \"Every cell of the RPE Table matches the published RTS chart\" recorded an issue with 1 argument reps → 3 at RPETableTests.swift:9:9: Expectation failed: 1 == 2
✘ Test \"Every cell of the RPE Table matches the published RTS chart\" with 12 test cases failed after 0.004 seconds with 3 issues.
✘ Test suggestsLoadForRPESet() failed after 0.013 seconds with 1 issue.
✘ Test grows(n:) with 1 test case failed after 0.001 seconds with 1 issue.
✔ Test grows(m:) passed after 0.001 seconds.
━ Test replanningKeepsTheLandedWrite() recorded a known issue at SyncCoordinatorReplanTests.swift:693:9: Expectation failed
✔ Test replanningKeepsTheLandedWrite() passed after 0.002 seconds with 1 known issue.
✘ Test failedSetIsRetried() failed after 0.002 seconds with 1 issue.
✘ Test ordering() recorded an issue at A.swift:1:1: Expectation failed: done failed after start
✘ Test ordering() failed after 0.001 seconds with 1 issue.
"$'\e[91m✘\e[0m'" Test coloredFailure() failed after 0.100 seconds with 1 issue.
✘ Test \"Load Basis line names its Set Log\" failed after 0.001 seconds with 2 issues.
✘ Test sheetRowParses(row:) with 4 test cases failed after 0.003 seconds with 4 issues.
✘ Test cliPrintsJSON() failed after 0.004 seconds with 1 issue.
✘ Test exportWritesCSV() failed after 0.002 seconds with 1 issue.
✘ Suite RPETableTests failed after 0.005 seconds with 3 issues.
✘ Test run with 1020 tests in 11 suites failed after 2.921 seconds with 12 issues (including 1 known issue)." \
"\"Every cell of the RPE Table matches the published RTS chart\"
\"Load Basis line names its Set Log\"
SyncTests.testFlushDropsNothing
SyncTests.testRetryAfterFailure
cliPrintsJSON
coloredFailure
exportWritesCSV
failedSetIsRetried
grows(n:)
ordering
sheetRowParses(row:)
suggestsLoadForRPESet"

check "an xcodebuild log names each failing test once, qualified by its suite" \
"◇ Test run started.
✘ Test someTest(height:setCount:) with 2 test cases failed after 0.010 seconds with 2 issues.
✘ Test failsOnPurpose() failed after 0.001 seconds with 1 issue.
✔ Test passes() passed after 0.001 seconds.
Test Case '-[WorkoutTrackerUITests.WorkoutTrackerUISmokeTests testMoveOnAdvancesToNextExercise]' failed (9.120 seconds).
Test Case '-[WorkoutTrackerUITests.WorkoutTrackerUISmokeTests testLaunches]' passed (3.001 seconds).
Test Case '-[WorkoutTrackerTests.LegacyTests testOld]' failed (0.100 seconds).
Restarting after unexpected exit, crash, or test timeout; summary will include totals from previous launches.
✘ Test run with 1021 tests in 12 suites failed after 2.172 seconds with 3 issues.

Failing tests:
	-[SomeSuite someTest(height:setCount:)]
	Issue769FailingProbeTests.failsOnPurpose()
	PlainSuite.plainTest()
	WorkoutTrackerUISmokeTests.testMoveOnAdvancesToNextExercise()
	AtmosphereVisualTests.livingPaperMatchesVisualBaseline()

** TEST EXECUTE FAILED **" \
"AtmosphereVisualTests.livingPaperMatchesVisualBaseline
Issue769FailingProbeTests.failsOnPurpose
LegacyTests.testOld
PlainSuite.plainTest
SomeSuite.someTest(height:setCount:)
WorkoutTrackerUISmokeTests.testMoveOnAdvancesToNextExercise"

check "a passing log names nothing" \
"✔ Test run with 1020 tests in 11 suites passed after 2.921 seconds.
Test Case '-[M.C testA]' passed (0.001 seconds).
	 Executed 1 test, with 0 failures (0 unexpected) in 0.001 (0.001) seconds" \
""

printf '\npassed %s, failed %s\n' "$pass" "$fail"
[ "$fail" -eq 0 ] || exit 1
