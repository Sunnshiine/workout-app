#!/usr/bin/env bash
set -uo pipefail

script_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
root=$(mktemp -d) || exit 3
sim=TEST-SIM-TEST-$$
trap 'rm -rf "$root" "/tmp/workout-verify-$sim"' EXIT
repo=$root/repo
products=$root/home/Library/Developer/Xcode/DerivedData/WorkoutTracker-stub/Build/Products
mkdir -p "$repo/scripts" "$root/bin" "$products"
cp "$script_dir/../test-sim.sh" "$script_dir/../sim-lock.sh" "$repo/scripts/"
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
chmod +x "$root/bin/plutil" "$root/bin/xcodebuild"

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
✘ Test grows(height:setCount:) recorded more issues than these 3; the log holds every one
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

check "a failing XCTest names where it failed" 65 \
"/repo/Tests/UI/WorkoutTrackerUISmokeTests.swift:39: error: -[WorkoutTrackerUITests.WorkoutTrackerUISmokeTests testMoveOnAdvancesToNextExercise] : XCTAssertTrue failed
	 Executed 12 tests, with 1 failure (0 unexpected) in 41.203 (41.311) seconds
Failing tests:
	WorkoutTrackerUISmokeTests.testMoveOnAdvancesToNextExercise()
** TEST EXECUTE FAILED **" "" 65 \
"Test Case '-[WorkoutTrackerUITests.WorkoutTrackerUISmokeTests testMoveOnAdvancesToNextExercise]' started.
/repo/Tests/UI/WorkoutTrackerUISmokeTests.swift:39: error: -[WorkoutTrackerUITests.WorkoutTrackerUISmokeTests testMoveOnAdvancesToNextExercise] : XCTAssertTrue failed
Test Case '-[WorkoutTrackerUITests.WorkoutTrackerUISmokeTests testMoveOnAdvancesToNextExercise]' failed (9.120 seconds).
	 Executed 12 tests, with 1 failure (0 unexpected) in 41.203 (41.311) seconds

Failing tests:
	WorkoutTrackerUISmokeTests.testMoveOnAdvancesToNextExercise()

** TEST EXECUTE FAILED **"

check "xcodebuild failing before any test names its error, not the selection" 70 \
"xcodebuild: error: Unable to find a device matching the provided destination specifier:" \
"no tests ran; xcodebuild exited 70 before the first test, for the reason above" 70 \
"Command line invocation:
    /Applications/Xcode.app/Contents/Developer/usr/bin/xcodebuild test-without-building

xcodebuild: error: Unable to find a device matching the provided destination specifier:
		{ platform:iOS Simulator, id:00000000-0000-0000-0000-000000000769 }

	The requested device could not be found because no available devices matched the request."

check "a test host that fails to launch names the launch error, not the selection" 65 \
"Testing failed:
	WorkoutTracker (14855) encountered an error (Early unexpected exit, operation never finished bootstrapping - no restart will be attempted. (Underlying Error: Test crashed with signal abrt before establishing connection.))
** TEST EXECUTE FAILED **" \
"no tests ran; xcodebuild exited 65 before the first test, for the reason above" 65 \
"Test session results, code coverage, and logs:
	/tmp/run.xcresult

Testing failed:
	WorkoutTracker (14855) encountered an error (Early unexpected exit, operation never finished bootstrapping - no restart will be attempted. (Underlying Error: Test crashed with signal abrt before establishing connection.))

** TEST EXECUTE FAILED **"

if grep -q '^log: .*-test\.log$' "$root/seen"; then
    ok "the log path prints before xcodebuild starts"
else
    bad "the log path prints before xcodebuild starts: stdout at start was '$(cat "$root/seen")'"
fi

printf '\npassed %s, failed %s\n' "$pass" "$fail"
[ "$fail" -eq 0 ] || exit 1
