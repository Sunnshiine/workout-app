#!/usr/bin/env bash
set -uo pipefail

# shellcheck source=scripts/tests/test-sim-harness.sh
. "$(dirname "${BASH_SOURCE[0]}")/test-sim-harness.sh"

check "every failing name prints, whatever characters it holds" 65 \
"✘ Test someTest(height:setCount:) recorded an issue with 2 arguments height → 70.0, setCount → 3 at SomeSuite.swift:19:9: Expectation failed: 1 == 2
✘ Test failsOnPurpose() recorded an issue at Issue769FailingProbeTests.swift:5:9: Expectation failed: 1 + 1 == 3
✘ Test run with 1021 tests in 12 suites failed after 2.172 seconds with 3 issues (including 1 known issue).
	 Executed 3 tests, with 1 failure (0 unexpected) in 0.100 (0.104) seconds
Failing tests:
	-[SomeSuite someTest(height:setCount:)]
	Issue769FailingProbeTests.failsOnPurpose()
	PlainSuite.plainTest()
** TEST EXECUTE FAILED **" "" 65 \
"◇ Test run started.
✘ Test someTest(height:setCount:) recorded an issue with 2 arguments height → 70.0, setCount → 3 at SomeSuite.swift:19:9: Expectation failed: 1 == 2
✘ Test failsOnPurpose() recorded an issue at Issue769FailingProbeTests.swift:5:9: Expectation failed: 1 + 1 == 3
━ Test replanningKeepsTheLandedWrite() recorded a known issue at SyncCoordinatorReplanTests.swift:693:9: Expectation failed
✘ Test run with 1021 tests in 12 suites failed after 2.172 seconds with 3 issues (including 1 known issue).
Test Suite 'Selected tests' failed at 2026-09-24 11:52:20.004.
	 Executed 3 tests, with 1 failure (0 unexpected) in 0.100 (0.104) seconds

Test session results, code coverage, and logs:
	/tmp/Test-WorkoutTracker.xcresult

Failing tests:
	-[SomeSuite someTest(height:setCount:)]
	-[SomeSuite someTest(height:setCount:)]
	Issue769FailingProbeTests.failsOnPurpose()
	PlainSuite.plainTest()

** TEST EXECUTE FAILED **"

check "a test that records many issues prints its first three" 65 \
"✘ Test grows(height:setCount:) recorded an issue with 2 arguments height → 70, setCount → 3 at GrowSuite.swift:19:9: Expectation failed
✘ Test grows(height:setCount:) recorded an issue with 2 arguments height → 70, setCount → 5 at GrowSuite.swift:19:9: Expectation failed
✘ Test grows(height:setCount:) recorded an issue with 2 arguments height → 90, setCount → 3 at GrowSuite.swift:19:9: Expectation failed
✘ Test grows(height:setCount:) recorded more issues; the log holds every one
✘ Test run with 3 tests in 1 suite failed after 0.100 seconds with 5 issues.
Failing tests:
	-[GrowSuite grows(height:setCount:)]
** TEST EXECUTE FAILED **" "" 65 \
"◇ Test run started.
✘ Test grows(height:setCount:) recorded an issue with 2 arguments height → 70, setCount → 3 at GrowSuite.swift:19:9: Expectation failed
✘ Test grows(height:setCount:) recorded an issue with 2 arguments height → 70, setCount → 5 at GrowSuite.swift:19:9: Expectation failed
✘ Test grows(height:setCount:) recorded an issue with 2 arguments height → 90, setCount → 3 at GrowSuite.swift:19:9: Expectation failed
✘ Test grows(height:setCount:) recorded an issue with 2 arguments height → 90, setCount → 5 at GrowSuite.swift:19:9: Expectation failed
✘ Test grows(height:setCount:) recorded an issue with 2 arguments height → 120, setCount → 3 at GrowSuite.swift:19:9: Expectation failed
✘ Test run with 3 tests in 1 suite failed after 0.100 seconds with 5 issues.

Failing tests:
	-[GrowSuite grows(height:setCount:)]

** TEST EXECUTE FAILED **"

check "a failing XCTest names where it failed and counts its run once" 65 \
"/repo/Tests/UI/WorkoutTrackerUISmokeTests.swift:39: error: -[WorkoutTrackerUITests.WorkoutTrackerUISmokeTests testMoveOnAdvancesToNextExercise] : XCTAssertTrue failed
	 Executed 4 tests, with 1 failure (0 unexpected) in 49.621 (49.644) seconds
Failing tests:
	WorkoutTrackerUISmokeTests.testMoveOnAdvancesToNextExercise()
** TEST EXECUTE FAILED **" "" 65 \
"Test Case '-[WorkoutTrackerUITests.WorkoutTrackerUISmokeTests testMoveOnAdvancesToNextExercise]' started.
/repo/Tests/UI/WorkoutTrackerUISmokeTests.swift:39: error: -[WorkoutTrackerUITests.WorkoutTrackerUISmokeTests testMoveOnAdvancesToNextExercise] : XCTAssertTrue failed
Test Case '-[WorkoutTrackerUITests.WorkoutTrackerUISmokeTests testMoveOnAdvancesToNextExercise]' failed (9.120 seconds).
Test Suite 'WorkoutTrackerUISmokeTests' failed at 2026-09-14 09:57:09.224.
	 Executed 4 tests, with 1 failure (0 unexpected) in 49.621 (49.637) seconds
Test Suite 'WorkoutTrackerUITests.xctest' failed at 2026-09-14 09:57:09.227.
	 Executed 4 tests, with 1 failure (0 unexpected) in 49.621 (49.640) seconds
Test Suite 'Selected tests' failed at 2026-09-14 09:57:09.227.
	 Executed 4 tests, with 1 failure (0 unexpected) in 49.621 (49.644) seconds

Failing tests:
	WorkoutTrackerUISmokeTests.testMoveOnAdvancesToNextExercise()

** TEST EXECUTE FAILED **"

check "a failing multi-line expectation prints the values it compared" 65 \
"✘ Test suggestsLoadForDropPrescriptionFromPreviousSetWeight() recorded an issue at LoadSuggestionEngineTests.swift:6:5: Expectation failed: LoadSuggestionEngine.suggest(
↳   LoadSuggestionEngine.suggest(
            ) → .weight(185.0)
↳   .weight(186) → .weight(186.0)
✘ Test suggestsLoadForDropPrescriptionFromPreviousSetWeight() failed after 0.013 seconds with 1 issue.
✘ Test run with 1042 tests in 11 suites failed after 5.575 seconds with 1 issue.
** TEST EXECUTE FAILED **" "" 65 \
"◇ Test run started.
↳ Testing Library Version: 2084
✘ Test suggestsLoadForDropPrescriptionFromPreviousSetWeight() recorded an issue at LoadSuggestionEngineTests.swift:6:5: Expectation failed: LoadSuggestionEngine.suggest(
            prescribedLoad: \"Drop 17.5%\",
            previousSetWeight: 225
        ) == .weight(186)
↳ LoadSuggestionEngine.suggest(
              prescribedLoad: \"Drop 17.5%\",
              previousSetWeight: 225
          ) == .weight(186) → false
↳   LoadSuggestionEngine.suggest(
                prescribedLoad: \"Drop 17.5%\",
                previousSetWeight: 225
            ) → .weight(185.0)
↳     weight → 185.0
↳   .weight(186) → .weight(186.0)
↳     weight → 186.0
✘ Test suggestsLoadForDropPrescriptionFromPreviousSetWeight() failed after 0.013 seconds with 1 issue.
✘ Test run with 1042 tests in 11 suites failed after 5.575 seconds with 1 issue.
** TEST EXECUTE FAILED **"

check "an expectation's comment and a recorded issue's message print with the issue" 65 \
"✘ Test branchFits(height:) recorded an issue with 1 argument height → 78.0 at SessionStageBranchEnvelopeTests.swift:24:13: Expectation failed: ink.bottom <= height + Self.inkBelow
↳ 3 Sets
↳   ink.bottom → 90.33333333333334
↳   height + Self.inkBelow → 90.0
✘ Test branchFits(height:) recorded an issue with 1 argument height → 78.0 at SessionStageBranchEnvelopeTests.swift:24:13: Expectation failed: ink.bottom <= height + Self.inkBelow
↳ 5 Sets
↳   ink.bottom → 90.33333333333334
↳   height + Self.inkBelow → 90.0
✘ Test seededSessionViewMatchesVisualBaseline() recorded an issue at SessionViewVisualTests.swift:11:32: Issue recorded
↳ Snapshot does not match reference.
✘ Test parses() recorded an issue at ParserTests.swift:9:5: Expectation failed: isValid
↳ isValid after parsing 185x5@8
✘ Test run with 2 tests in 2 suites failed after 1.100 seconds with 3 issues.
** TEST EXECUTE FAILED **" "" 65 \
"◇ Test run started.
✘ Test branchFits(height:) recorded an issue with 1 argument height → 78.0 at SessionStageBranchEnvelopeTests.swift:24:13: Expectation failed: ink.bottom <= height + Self.inkBelow
↳ 3 Sets
↳ ink.bottom <= height + Self.inkBelow → false
↳   ink.bottom → 90.33333333333334
↳   height + Self.inkBelow → 90.0
✘ Test branchFits(height:) recorded an issue with 1 argument height → 78.0 at SessionStageBranchEnvelopeTests.swift:24:13: Expectation failed: ink.bottom <= height + Self.inkBelow
↳ 5 Sets
↳ ink.bottom <= height + Self.inkBelow → false
↳   ink.bottom → 90.33333333333334
↳   height + Self.inkBelow → 90.0
✘ Test seededSessionViewMatchesVisualBaseline() recorded an issue at SessionViewVisualTests.swift:11:32: Issue recorded
↳ Snapshot does not match reference.
  
  @−
  \"file:///repo/Tests/Visual/__Snapshots__/SessionViewVisualTests/seededSessionViewMatchesVisualBaseline.1.png\"
  
  Newly-taken snapshot does not match reference.
✘ Test parses() recorded an issue at ParserTests.swift:9:5: Expectation failed: isValid
↳ isValid after parsing 185x5@8
↳ isValid → false
✘ Test run with 2 tests in 2 suites failed after 1.100 seconds with 3 issues.
** TEST EXECUTE FAILED **"

check "only a printed issue's values print" 65 \
"✘ Test grows(height:) recorded an issue with 1 argument height → 70 at GrowSuite.swift:19:9: Expectation failed: ink.top >= -4
↳   ink.top → -1.0
✘ Test grows(height:) recorded an issue with 1 argument height → 80 at GrowSuite.swift:19:9: Expectation failed: ink.top >= -4
↳   ink.top → -2.0
✘ Test grows(height:) recorded an issue with 1 argument height → 90 at GrowSuite.swift:19:9: Expectation failed: ink.top >= -4
↳   ink.top → -3.0
✘ Test grows(height:) recorded more issues; the log holds every one
✘ Test grows(height:) with 4 test cases failed after 0.002 seconds with 4 issues.
✘ Test run with 2 tests in 1 suite failed after 0.100 seconds with 5 issues (including 1 known issue).
** TEST EXECUTE FAILED **" "" 65 \
"◇ Test run started.
✘ Test grows(height:) recorded an issue with 1 argument height → 70 at GrowSuite.swift:19:9: Expectation failed: ink.top >= -4
↳ ink.top >= -4 → false
↳   ink.top → -1.0
✘ Test grows(height:) recorded an issue with 1 argument height → 80 at GrowSuite.swift:19:9: Expectation failed: ink.top >= -4
↳ ink.top >= -4 → false
↳   ink.top → -2.0
✘ Test grows(height:) recorded an issue with 1 argument height → 90 at GrowSuite.swift:19:9: Expectation failed: ink.top >= -4
↳ ink.top >= -4 → false
↳   ink.top → -3.0
✘ Test grows(height:) recorded an issue with 1 argument height → 99 at GrowSuite.swift:19:9: Expectation failed: ink.top >= -4
↳ 4 Sets
↳ ink.top >= -4 → false
↳   ink.top → -4.5
✘ Test grows(height:) with 4 test cases failed after 0.002 seconds with 4 issues.
↳ /// The branch stays inside the gaps around it.
━ Test replanningKeepsTheLandedWrite() recorded a known issue at SyncCoordinatorReplanTests.swift:693:9: Expectation failed: sync.outcome == .flushed
↳   sync.outcome → .writesQueued(2)
✘ Test run with 2 tests in 1 suite failed after 0.100 seconds with 5 issues (including 1 known issue).
** TEST EXECUTE FAILED **"

check "xcodebuild failing before any test names its error, not the selection" 70 \
"xcodebuild: error: Unable to find a device matching the provided destination specifier:
		{ platform:iOS Simulator, id:00000000-0000-0000-0000-000000000769 }" \
"xcodebuild exited 70 before the test run finished; the lines above and the log say why" 70 \
"Command line invocation:
    /Applications/Xcode.app/Contents/Developer/usr/bin/xcodebuild test-without-building

xcodebuild: error: Unable to find a device matching the provided destination specifier:
		{ platform:iOS Simulator, id:00000000-0000-0000-0000-000000000769 }

	The requested device could not be found because no available devices matched the request."

check "a test host that fails to launch names the launch error, not the selection" 65 \
"Testing failed:
	WorkoutTracker (14855) encountered an error (Early unexpected exit, operation never finished bootstrapping - no restart will be attempted. (Underlying Error: Test crashed with signal abrt before establishing connection.))
** TEST EXECUTE FAILED **" \
"xcodebuild exited 65 before the test run finished; the lines above and the log say why" 65 \
"Test session results, code coverage, and logs:
	/tmp/run.xcresult

Testing failed:
	WorkoutTracker (14855) encountered an error (Early unexpected exit, operation never finished bootstrapping - no restart will be attempted. (Underlying Error: Test crashed with signal abrt before establishing connection.))

** TEST EXECUTE FAILED **"

check "a host that dies mid-run names the test it was running" 65 \
"Failing tests:
	AtmosphereVisualTests.livingPaperMatchesVisualBaseline()
** TEST EXECUTE FAILED **" \
"xcodebuild exited 65 before the test run finished; the lines above and the log say why" 65 \
"	 Executed 0 tests, with 0 failures (0 unexpected) in 0.000 (0.000) seconds
◇ Test run started.
◇ Test activeSetCardMatchesVisualBaseline() started.
✔ Test activeSetCardMatchesVisualBaseline() passed after 1.204 seconds.
◇ Test livingPaperMatchesVisualBaseline() started.
Failed to send signal 19 to process 41235

Failing tests:
	AtmosphereVisualTests.livingPaperMatchesVisualBaseline()

** TEST EXECUTE FAILED **"

check "a crash xcodebuild restarts past says so" 65 \
"Restarting after unexpected exit, crash, or test timeout; summary will include totals from previous launches.
✔ Test run with 30 tests in 8 suites passed after 4.437 seconds.
Failing tests:
	BlockGridVisualTests.threeDayGridMatchesVisualBaseline()
** TEST EXECUTE FAILED **" "" 65 \
"◇ Test threeDayGridMatchesVisualBaseline() started.

Restarting after unexpected exit, crash, or test timeout; summary will include totals from previous launches.

	 Executed 0 tests, with 0 failures (0 unexpected) in 0.000 (0.000) seconds
◇ Test run started.
✔ Test run with 30 tests in 8 suites passed after 4.437 seconds.

Failing tests:
	BlockGridVisualTests.threeDayGridMatchesVisualBaseline()

** TEST EXECUTE FAILED **"

if grep -q '^log: .*-test\.log$' "$root/seen"; then
    ok "the log path prints before xcodebuild starts"
else
    bad "the log path prints before xcodebuild starts: stdout at start was '$(cat "$root/seen")'"
fi

printf '\npassed %s, failed %s\n' "$pass" "$fail"
[ "$fail" -eq 0 ] || exit 1
