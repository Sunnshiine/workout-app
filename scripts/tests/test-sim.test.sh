#!/usr/bin/env bash
set -uo pipefail

script_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
root=$(mktemp -d) || exit 3
sim=TEST-SIM-TEST-$$
other_sim=TEST-SIM-OTHER-$$
unknown=DEADBEEF-0000-4000-8000-$(printf %012d $$)
trap 'rm -rf "$root" "/tmp/workout-verify-$sim" "/tmp/workout-verify-$other_sim" "/tmp/workout-verify-$unknown"' EXIT
repo=$root/repo
products=$root/home/Library/Developer/Xcode/DerivedData/WorkoutTracker-stub/Build/Products
mkdir -p "$repo/scripts" "$root/bin" "$products"
cp "$script_dir/../test-sim.sh" "$script_dir/../sim-lock.sh" "$script_dir/../test-log-summary.awk" "$repo/scripts/"
touch "$products/../../info.plist" "$products/WorkoutTracker_iphonesimulator27.0-arm64.xctestrun"
cat >"$repo/scripts/sim-keyboard.sh" <<'STUB'
#!/bin/sh
echo "$*" >>"$STUB_KEYBOARD_CALLS"
echo "keyboard: stub"
exit "${STUB_KEYBOARD_RC:-0}"
STUB
chmod +x "$repo/scripts/sim-keyboard.sh"
export WORKOUT_LOAD_LIMIT=1000000 WORKOUT_HOST_LOCK_DIR=$root/locks
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
printf '%s\n' "$@" >"$STUB_ARGS"
while [ $# -gt 0 ]; do
    [ "$1" != -resultBundlePath ] || [ -z "${STUB_SUMMARY:-}" ] || mkdir "$2"
    shift
done
cat "$STUB_LOG"
cp "$STUB_OUT" "$STUB_SEEN"
[ -z "${STUB_RELEASE:-}" ] || while [ ! -e "$STUB_RELEASE" ]; do sleep 0.1; done
[ -z "${STUB_SLEEP:-}" ] || sleep "$STUB_SLEEP"
exit "$STUB_RC"
STUB
cat >"$root/bin/xcrun" <<STUB
#!/bin/sh
if [ "\$1" = xcresulttool ]; then
    [ -n "\${STUB_SUMMARY:-}" ] && [ "\$4 \$5" = "summary --path" ] && [ -d "\$6" ] && printf '%s\n' "\$STUB_SUMMARY"
    exit
fi
[ -z "\${STUB_SIMCTL_DOWN:-}" ] || { echo "An error was encountered processing the command (code=405)" >&2; exit 1; }
echo '{"devices":{"com.apple.CoreSimulator.SimRuntime.iOS-27-0":[{"udid":"$sim","state":"Booted","name":"iPhone 17 Pro"},{"udid":"$other_sim","state":"Booted","name":"iPhone 17"}]}}'
STUB
cat >"$root/bin/date" <<'STUB'
#!/bin/sh
[ -n "${STUB_STAMP:-}" ] && [ "$*" = +%Y%m%d-%H%M%S ] && { echo "$STUB_STAMP"; exit; }
exec /bin/date "$@"
STUB
cat >"$root/bin/sysctl" <<'STUB'
#!/bin/sh
[ -e "$STUB_LOAD_READ" ] && echo '{ 2.50 1.25 1.00 }' || echo '{ 1.50 1.25 1.00 }'
touch "$STUB_LOAD_READ"
STUB
chmod +x "$root/bin/plutil" "$root/bin/xcodebuild" "$root/bin/xcrun" "$root/bin/sysctl" "$root/bin/date"
export STUB_ARGS=$root/args STUB_KEYBOARD_CALLS=$root/keyboard STUB_LOAD_READ=$root/load-read
result() { echo "test-sim: suite=$1 passed=- failed=- expected=- exit=$2 load1=1.50/2.50 bundle=-"; }

check() {
    local name=$1 want_status=$2 want_out=$3 want_err=$4 xcodebuild_status=$5 log=$6
    printf '%s\n' "$log" >"$root/xcodebuild.log"
    STUB_LOG=$root/xcodebuild.log STUB_RC=$xcodebuild_status STUB_OUT=$root/out STUB_SEEN=$root/seen HOME=$root/home PATH="$root/bin:$PATH" \
        "$repo/scripts/test-sim.sh" --no-build --sim "$sim" unit >"$root/out" 2>"$root/err"
    local status=$?
    rm -f "$root/load-read"
    local out err last
    out=$(grep -v -e '^log: ' -e '^bundle: ' -e '^test-sim: ' "$root/out")
    err=$(cat "$root/err")
    last=$(tail -1 "$root/out")
    if [ "$status" = "$want_status" ] && [ "$out" = "$want_out" ] && [ "$err" = "$want_err" ] \
        && [ "$last" = "$(result unit "$want_status")" ]; then
        ok "$name"
    else
        bad "$name: exit $status (want $want_status)"
        printf '    stdout:\n%s\n    last line:\n%s\n    stderr:\n%s\n' "$out" "$last" "$err"
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

for build in --no-build ""; do
    flags="${build:+$build }--sim"
    rm -f "$root/seen" "$root/load-read"
    STUB_LOG=$root/xcodebuild.log STUB_RC=70 STUB_OUT=$root/out STUB_SEEN=$root/seen HOME=$root/home PATH="$root/bin:$PATH" \
        "$repo/scripts/test-sim.sh" ${build:+"$build"} --sim "$unknown" unit >"$root/out" 2>"$root/err"
    status=$?
    want="no available simulator $unknown; xcrun simctl list devices available lists them"
    if [ $status = 2 ] && [ "$(cat "$root/out")" = "$(result unit 2)" ] && [ "$(cat "$root/err")" = "$want" ] && [ ! -e "$root/seen" ] \
        && [ ! -e "/tmp/workout-verify-$unknown" ]; then
        ok "an unknown --sim UDID ($flags) is refused before it claims the simulator or xcodebuild starts"
    else
        bad "an unknown --sim UDID ($flags) is refused before it claims the simulator or xcodebuild starts: exit $status, xcodebuild ran: $([ -e "$root/seen" ] && echo yes || echo no)"
        printf '    stdout:\n%s\n    stderr:\n%s\n' "$(cat "$root/out")" "$(cat "$root/err")"
    fi
done

STUB_SIMCTL_DOWN=1 HOME=$root/home PATH="$root/bin:$PATH" "$repo/scripts/test-sim.sh" --sim "$sim" unit >"$root/out" 2>"$root/err"
status=$?
if [ $status = 1 ] && [ "$(cat "$root/err")" = "An error was encountered processing the command (code=405)" ]; then
    ok "a simctl failure prints simctl's error, not a refused UDID"
else
    bad "a simctl failure prints simctl's error, not a refused UDID: exit $status, stderr '$(cat "$root/err")'"
fi

run() {
    rm -f "$root/seen" "$root/keyboard" "$root/load-read"
    STUB_LOG=$root/xcodebuild.log STUB_RC=${rc:-65} STUB_OUT=$root/out STUB_SEEN=$root/seen HOME=$root/home PATH="$root/bin:$PATH" \
        "$repo/scripts/test-sim.sh" "$@" >"$root/out" 2>"$root/err"
}
expect() {
    if [ "$2" = "$3" ]; then
        ok "$1"
    else
        bad "$1"
        printf '    got:\n%s\n    want:\n%s\n    stderr:\n%s\n' "$2" "$3" "$(cat "$root/err")"
    fi
}

printf '%s\n' "✘ Test seededSessionViewMatchesVisualBaseline() recorded an issue at SessionViewVisualTests.swift:11:32: Issue recorded" \
    "↳ Snapshot does not match reference." "✘ Test run with 30 tests in 8 suites failed after 4.437 seconds with 1 issue." \
    "** TEST EXECUTE FAILED **" >"$root/xcodebuild.log"
STUB_SUMMARY='{"passedTests":29,"failedTests":1,"expectedFailures":0,"skippedTests":0}' run --no-build --sim "$sim" visual
bundle=$(sed -n 's/^bundle: //p' "$root/out")
expect "a run hands xcodebuild the bundle path it printed" "$(grep -A1 -x -- -resultBundlePath "$root/args" | tail -1)" "$bundle"
expect "a failed visual run names the snapshot diff command, then ends with its counts and bundle" "$(tail -2 "$root/out")" \
"snapshot diffs: scripts/snapshot-diffs.sh $bundle
test-sim: suite=visual passed=29 failed=1 expected=0 exit=65 load1=1.50/2.50 bundle=$bundle"

printf '%s\n' "✔ Test run with 30 tests in 8 suites passed after 4.437 seconds." "** TEST EXECUTE SUCCEEDED **" >"$root/xcodebuild.log"
rc=0 STUB_SUMMARY='{"passedTests":30,"failedTests":0,"expectedFailures":0}' run --no-build --sim "$sim" visual
expect "a passing visual run names no diff command" "$(grep -c '^snapshot diffs' "$root/out"; tail -1 "$root/out")" \
"0
test-sim: suite=visual passed=30 failed=0 expected=0 exit=0 load1=1.50/2.50 bundle=$(sed -n 's/^bundle: //p' "$root/out")"

printf '%s\n' "✘ Test parses() recorded an issue at ParserTests.swift:9:5: Expectation failed: isValid" \
    "✘ Test run with 1020 tests in 11 suites failed after 2.921 seconds with 1 issue." "** TEST EXECUTE FAILED **" >"$root/xcodebuild.log"
STUB_SUMMARY='{"passedTests":1019,"failedTests":1,"expectedFailures":0}' run --no-build --sim "$sim" unit WorkoutTrackerTests/ParserTests
expect "a failed run with no snapshot mismatch names no diff command" "$(tail -1 "$root/out"; grep -c '^snapshot diffs' "$root/out")" \
"test-sim: suite=unit,WorkoutTrackerTests/ParserTests passed=1019 failed=1 expected=0 exit=65 load1=1.50/2.50 bundle=$(sed -n 's/^bundle: //p' "$root/out")
0"

printf '%s\n' "━ Test run with 1069 tests in 11 suites passed after 4.453 seconds with 1 known issue." \
    "** TEST EXECUTE SUCCEEDED **" >"$root/xcodebuild.log"
rc=0 STUB_SUMMARY='{"passedTests":1068,"failedTests":0,"expectedFailures":1,"skippedTests":0}' run --no-build --sim "$sim" unit
expect "a test that records only a known issue counts as expected, not passed" "$(tail -1 "$root/out")" \
"test-sim: suite=unit passed=1068 failed=0 expected=1 exit=0 load1=1.50/2.50 bundle=$(sed -n 's/^bundle: //p' "$root/out")"

logs=$repo/.build/test-sim
finished="test-sim: suite=unit passed=1 failed=0 expected=0 exit=0 load1=1.50/2.50 bundle=-"
fixture_run() {
    local stamp=$1 last_line=$2 age=$3
    mkdir "$logs/$stamp.xcresult" "$logs/$stamp-diffs"
    printf '%s\n' "◇ Test run started." "$last_line" >"$logs/$stamp-test.log"
    echo "** BUILD SUCCEEDED **" >"$logs/$stamp-build.log"
    touch -t "$age" "$logs/$stamp"*
}
minutes_ago() { date -v-"$1"M +%Y%m%d%H%M; }
rm -rf "$logs"
mkdir -p "$logs"
fixture_run 20991231-000001 "$finished" 202001010001
fixture_run 20991231-000002 "$finished" 202001010002
for n in 3 4 5 6; do fixture_run "20991231-00000$n" "$finished" "$(minutes_ago "$n")"; done
fixture_run 20991231-000007 "$finished" "$(minutes_ago 10)"
fixture_run 20991231-000008 "✔ Test run with 1 test in 1 suite passed after 1.000 seconds." "$(date -v-25H +%Y%m%d%H%M)"
fixture_run 20991231-000012 "✔ Test run with 1 test in 1 suite passed after 1.000 seconds." "$(date -v-2H +%Y%m%d%H%M)"
echo notes >"$logs/20200101-000000-notes.txt"
# Written now, so a match on the stamp alone would rank run 000001 among the five newest and keep it.
echo notes >"$logs/20991231-000001-notes.txt"
echo notes >"$logs/20991231-000002-notes.txt"
echo notes >"$logs/README.txt"
mkdir "$logs/unit.xcresult"
touch -t 202001010000 "$logs/20200101-000000-notes.txt" "$logs/20991231-000002-notes.txt" "$logs/README.txt" "$logs/unit.xcresult"
rc=0 STUB_STAMP=20991231-000000 STUB_SUMMARY='{"passedTests":1,"failedTests":0,"expectedFailures":0}' run --no-build --sim "$sim" unit
expect "a run deletes every file of a finished run older than the five written last, whatever their stamps sort as" \
    "$(tail -1 "$root/out" | sed 's/ load1=.*bundle=/ bundle=/'; ls "$logs")" \
"test-sim: suite=unit passed=1 failed=0 expected=0 exit=0 bundle=$logs/20991231-000000.xcresult
20200101-000000-notes.txt
20991231-000000-test.log
20991231-000000.xcresult
20991231-000001-notes.txt
20991231-000002-notes.txt
20991231-000003-build.log
20991231-000003-diffs
20991231-000003-test.log
20991231-000003.xcresult
20991231-000004-build.log
20991231-000004-diffs
20991231-000004-test.log
20991231-000004.xcresult
20991231-000005-build.log
20991231-000005-diffs
20991231-000005-test.log
20991231-000005.xcresult
20991231-000006-build.log
20991231-000006-diffs
20991231-000006-test.log
20991231-000006.xcresult
20991231-000007-build.log
20991231-000007-diffs
20991231-000007-test.log
20991231-000007.xcresult
20991231-000012-build.log
20991231-000012-diffs
20991231-000012-test.log
20991231-000012.xcresult
README.txt
unit.xcresult"
expect "a run's test log ends with its result line" "$(tail -1 "$logs/20991231-000000-test.log")" \
    "test-sim: suite=unit passed=1 failed=0 expected=0 exit=0 load1=1.50/2.50 bundle=$logs/20991231-000000.xcresult"
expect "a file whose name only starts with a stamp, even a deleted run's, and a file with no stamp, survive" \
    "$(cd "$logs" && ls -d 20200101-000000-notes.txt 20991231-000001-notes.txt 20991231-000002-notes.txt README.txt unit.xcresult)" \
"20200101-000000-notes.txt
20991231-000001-notes.txt
20991231-000002-notes.txt
README.txt
unit.xcresult"
expect "a run with no result line, untouched for 24 hours, is abandoned and deleted" \
    "$(cd "$logs" && ls -d 20991231-000008* 2>/dev/null)" ""
expect "a run with no result line touched 2 hours ago survives" "$(cd "$logs" && ls -d 20991231-000012*)" \
"20991231-000012-build.log
20991231-000012-diffs
20991231-000012-test.log
20991231-000012.xcresult"
expect "a finished run past the five written last survives while a file of it changed in the last 30 minutes" \
    "$(cd "$logs" && ls -d 20991231-000007*)" \
"20991231-000007-build.log
20991231-000007-diffs
20991231-000007-test.log
20991231-000007.xcresult"

printf '%s\n' "** BUILD FAILED **" >"$root/xcodebuild.log"
rm -rf "$logs"
STUB_STAMP=20991231-000009 run --sim "$sim" unit
expect "a run that fails in the build writes its result line to its test log" \
    "$(cat "$logs/20991231-000009-test.log")" "$(result unit 65)"

printf '%s' "◇ Test run started." >"$root/xcodebuild.log"
STUB_STAMP=20991231-000010 run --no-build --sim "$sim" unit
expect "a result line lands on its own line after a log cut off mid-line" "$(tail -1 "$logs/20991231-000010-test.log")" \
    "$(result unit 65)"

rm -rf "$logs"
printf '%s\n' "◇ Test run started." "✔ Test run with 1 test in 1 suite passed after 1.000 seconds." "** TEST EXECUTE SUCCEEDED **" \
    >"$root/xcodebuild.log"
STUB_RELEASE=$root/release STUB_STAMP=20991231-100000 STUB_SUMMARY='{"passedTests":1,"failedTests":0,"expectedFailures":0}' \
    STUB_LOG=$root/xcodebuild.log STUB_RC=0 STUB_OUT=$root/in-progress.out STUB_SEEN=$root/in-progress.seen \
    HOME=$root/home PATH="$root/bin:$PATH" \
    "$repo/scripts/test-sim.sh" --no-build --sim "$other_sim" unit >"$root/in-progress.out" 2>"$root/in-progress.err" &
pid=$!
for _ in $(seq 50); do [ -e "$root/in-progress.seen" ] && break; sleep 0.1; done
touch -t "$(date -v-2H +%Y%m%d%H%M)" "$logs/20991231-100000"*
for n in 1 2 3 4 5; do
    rc=0 STUB_STAMP=20991231-10000$n STUB_SUMMARY='{"passedTests":1,"failedTests":0,"expectedFailures":0}' run --no-build --sim "$sim" unit
done
touch "$root/release"
wait "$pid"
status=$?
expect "a run still in xcodebuild survives five later runs in its checkout and ends with its bundle" \
    "$status $(tail -1 "$root/in-progress.out" | sed 's/ load1=.*bundle=/ bundle=/') $(cd "$logs" && ls -d 20991231-100000*)" \
    "0 test-sim: suite=unit passed=1 failed=0 expected=0 exit=0 bundle=$logs/20991231-100000.xcresult 20991231-100000-test.log
20991231-100000.xcresult"

STUB_SUMMARY='not json' run --no-build --sim "$sim" unit
expect "an unreadable summary leaves the counts unknown" "$(tail -1 "$root/out")" \
"test-sim: suite=unit passed=- failed=- expected=- exit=65 load1=1.50/2.50 bundle=$(sed -n 's/^bundle: //p' "$root/out")"

run
status=$?
expect "a usage error exits 2 and still ends with the result line" "$status $(cat "$root/out")" "2 $(result - 2)"

for selection in ui all WorkoutTrackerUITests/WorkoutTrackerUISmokeTests; do
    run --no-build --sim "$sim" "$selection"
    expect "$selection runs the keyboard step once" \
        "$(cat "$root/keyboard"; grep '^keyboard: ' "$root/out")" "ensure $sim
keyboard: stub"
done
for selection in unit visual WorkoutTrackerSnapshotTests/BlockGridVisualTests; do
    run --no-build --sim "$sim" "$selection"
    expect "$selection skips the keyboard step" "$([ -e "$root/keyboard" ] && echo ran || echo skipped)" skipped
done

run --no-build unit --sim
status=$?
expect "a --sim with no UDID is a usage error, not a clean run" "$status $(cat "$root/out")" "2 $(result unit 2)"

rm -f "$root/seen" "$root/load-read"
printf '%s\n' "◇ Test run started." >"$root/xcodebuild.log"
STUB_SLEEP=2 HOME=$root/home PATH="$root/bin:$PATH" STUB_LOG=$root/xcodebuild.log STUB_RC=0 STUB_OUT=$root/out STUB_SEEN=$root/seen \
    "$repo/scripts/test-sim.sh" --no-build --sim "$sim" unit >"$root/out" 2>"$root/err" &
pid=$!
for _ in 1 2 3 4 5 6 7 8 9 10; do [ -e "$root/seen" ] && break; sleep 0.2; done
kill -TERM "$pid"
wait "$pid"
status=$?
expect "a run killed with TERM reports exit=143, not the last command's 0" "$status $(tail -1 "$root/out" | sed 's/ load1=.*//')" \
    "143 test-sim: suite=unit passed=- failed=- expected=- exit=143"

STUB_KEYBOARD_RC=70 run --no-build --sim "$sim" ui
status=$?
expect "a keyboard step that fails stops the run before xcodebuild with its status" \
    "$status $([ -e "$root/seen" ] && echo xcodebuild-ran || echo xcodebuild-skipped) $(tail -1 "$root/out")" \
    "70 xcodebuild-skipped $(result ui 70)"

printf '\npassed %s, failed %s\n' "$pass" "$fail"
[ "$fail" -eq 0 ] || exit 1
