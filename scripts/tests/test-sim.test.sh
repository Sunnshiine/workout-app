#!/usr/bin/env bash
set -uo pipefail

script_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
root=$(mktemp -d) || exit 3
sim=TEST-SIM-TEST-$$
trap 'rm -rf "$root" "/tmp/workout-verify-$sim"' EXIT
repo=$root/repo
products=$root/home/Library/Developer/Xcode/DerivedData/WorkoutTracker-stub/Build/Products
mkdir -p "$repo/scripts" "$root/bin" "$products"
cp "$script_dir/../test-sim.sh" "$script_dir/../sim-lock.sh" "$script_dir/../test-log-summary.awk" "$repo/scripts/"
touch "$products/../../info.plist" "$products/WorkoutTracker_iphonesimulator27.0-arm64.xctestrun"
pass=0
fail=0

ok()  { pass=$((pass + 1)); printf '  ok   %s\n' "$1"; }
bad() { fail=$((fail + 1)); printf '  FAIL %s\n' "$1"; }

cat >"$root/bin/plutil" <<STUB
#!/bin/sh
echo "$repo/WorkoutTracker.xcodeproj"
STUB
cat >"$root/bin/xcodebuild" <<'STUB'
#!/bin/sh
cp "$STUB_OUT" "$STUB_SEEN"
cat "$STUB_LOG"
exit "$STUB_RC"
STUB
cat >"$root/bin/xcrun" <<STUB
#!/bin/sh
echo '{"devices":{"com.apple.CoreSimulator.SimRuntime.iOS-27-0":[{"udid":"$sim","state":"Booted","name":"iPhone 17 Pro"}]}}'
STUB
chmod +x "$root/bin/plutil" "$root/bin/xcodebuild" "$root/bin/xcrun"

check() {
    local name=$1 want_status=$2 want_out=$3 want_err=$4 xcodebuild_status=$5 log=$6
    printf '%s\n' "$log" >"$root/xcodebuild.log"
    STUB_LOG=$root/xcodebuild.log STUB_RC=$xcodebuild_status STUB_OUT=$root/out STUB_SEEN=$root/seen HOME=$root/home PATH="$root/bin:$PATH" \
        "$repo/scripts/test-sim.sh" --no-build --sim "$sim" unit >"$root/out" 2>"$root/err"
    local status=$?
    local out err
    out=$(grep -v '^log: ' "$root/out")
    err=$(cat "$root/err")
    if [ "$status" = "$want_status" ] && [ "$out" = "$want_out" ] && [ "$err" = "$want_err" ]; then
        ok "$name"
    else
        bad "$name: exit $status (want $want_status)"
        printf '    stdout:\n%s\n    stderr:\n%s\n' "$out" "$err"
    fi
}

no_tests_ran="no tests ran; check the selection (-only-testing:WorkoutTrackerTests)"

check "a passing run with a known issue passes" 0 \
"━ Test run with 1020 tests in 11 suites passed after 2.921 seconds with 1 known issue.
** TEST EXECUTE SUCCEEDED **" "" 0 \
"Test Suite 'All tests' started at 2026-09-24 11:52:19.954.
Test Suite 'All tests' passed at 2026-09-24 11:52:19.954.
	 Executed 0 tests, with 0 failures (0 unexpected) in 0.000 (0.000) seconds
◇ Test run started.
↳ Testing Library Version: 2084
◇ Test canMoveOnIsFalseOnLastSession() started.
✔ Test canMoveOnIsFalseOnLastSession() passed after 0.010 seconds.
━ Test run with 1020 tests in 11 suites passed after 2.921 seconds with 1 known issue.
** TEST EXECUTE SUCCEEDED **"

check "a passing run passes" 0 \
"✔ Test run with 1020 tests in 11 suites passed after 2.921 seconds.
** TEST EXECUTE SUCCEEDED **" "" 0 \
"◇ Test run started.
✔ Test run with 1020 tests in 11 suites passed after 2.921 seconds.
	 Executed 0 tests, with 0 failures (0 unexpected) in 0.000 (0.004) seconds
** TEST EXECUTE SUCCEEDED **"

check "a failing run fails with xcodebuild's status" 65 \
"✘ Test run with 1020 tests in 11 suites failed after 2.921 seconds with 1 issue.
** TEST EXECUTE FAILED **" "" 65 \
"◇ Test run started.
✘ Test run with 1020 tests in 11 suites failed after 2.921 seconds with 1 issue.
	 Executed 0 tests, with 0 failures (0 unexpected) in 0.000 (0.004) seconds
** TEST EXECUTE FAILED **"

check "an XCTest run passes on its Executed line" 0 \
"	 Executed 12 tests, with 0 failures (0 unexpected) in 41.203 (41.311) seconds
** TEST EXECUTE SUCCEEDED **" "" 0 \
"Test Suite 'All tests' passed at 2026-09-24 11:33:21.004.
	 Executed 12 tests, with 0 failures (0 unexpected) in 41.203 (41.311) seconds
** TEST EXECUTE SUCCEEDED **"

check "a selection that runs no tests exits 65" 65 \
"** TEST EXECUTE SUCCEEDED **" "$no_tests_ran" 0 \
"Test Suite 'All tests' passed at 2026-09-24 11:33:21.004.
	 Executed 0 tests, with 0 failures (0 unexpected) in 0.000 (0.004) seconds
** TEST EXECUTE SUCCEEDED **"

check "a Swift Testing selection that runs no tests exits 65" 65 \
"✔ Test run with 0 tests in 1 suite passed after 0.001 seconds.
** TEST EXECUTE SUCCEEDED **" "$no_tests_ran" 0 \
"	 Executed 0 tests, with 0 failures (0 unexpected) in 0.000 (0.000) seconds
◇ Test run started.
↳ Testing Library Version: 2084
✔ Test run with 0 tests in 1 suite passed after 0.001 seconds.
** TEST EXECUTE SUCCEEDED **"

colored=$'\e[90m━\e[0m Test run with 1020 tests in 11 suites passed after 2.921 seconds with 1 known issue.'
check "a colored summary counts, whatever its glyph" 0 \
"$colored
** TEST EXECUTE SUCCEEDED **" "" 0 \
"◇ Test run started.
$colored
** TEST EXECUTE SUCCEEDED **"

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

unknown=DEADBEEF-0000-4000-8000-000000000790
for flags in "--no-build --sim" "--sim"; do
    rm -f "$root/seen"
    STUB_LOG=$root/xcodebuild.log STUB_RC=70 STUB_OUT=$root/out STUB_SEEN=$root/seen HOME=$root/home PATH="$root/bin:$PATH" \
        "$repo/scripts/test-sim.sh" $flags "$unknown" unit >"$root/out" 2>"$root/err"
    status=$?
    want="no available simulator $unknown; xcrun simctl list devices available lists them"
    if [ $status = 2 ] && [ ! -s "$root/out" ] && [ "$(cat "$root/err")" = "$want" ] && [ ! -e "$root/seen" ]; then
        ok "an unknown --sim UDID ($flags) is refused before xcodebuild starts"
    else
        bad "an unknown --sim UDID ($flags) is refused before xcodebuild starts: exit $status, xcodebuild ran: $([ -e "$root/seen" ] && echo yes || echo no)"
        printf '    stdout:\n%s\n    stderr:\n%s\n' "$(cat "$root/out")" "$(cat "$root/err")"
    fi
done

printf '\npassed %s, failed %s\n' "$pass" "$fail"
[ "$fail" -eq 0 ] || exit 1
