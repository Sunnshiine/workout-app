#!/usr/bin/env bash
set -uo pipefail

# shellcheck source=scripts/tests/test-sim-harness.sh
. "$(dirname "${BASH_SOURCE[0]}")/test-sim-harness.sh"

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

fault_advice="simulator fault, not a test result: xcodebuild reported \"%s\". Shut $sim down so the next run boots it fresh; rerun the same command, and if it faults again, run xcrun simctl erase $sim first"
rm -f "$root/shutdowns"
check "a launch that returns no process handle is a simulator fault: exit 69, and the simulator is shut down" 69 \
"✘ Test run with 1 test in 1 suite failed after 31.2 seconds with 1 issue.
** TEST EXECUTE FAILED **" "$(printf "$fault_advice" "did not return a process handle nor launch error")" 65 \
"◇ Test run started.
Failed to get launch progress for <XCUIApplicationImpl: com.sunnypatel.WorkoutTracker>: Error Domain=NSPOSIXErrorDomain Code=3 \"No such process\"
Application launch for 'com.sunnypatel.WorkoutTracker' did not return a process handle nor launch error.
✘ Test run with 1 test in 1 suite failed after 31.2 seconds with 1 issue.
** TEST EXECUTE FAILED **"
if [ "$(cat "$root/shutdowns" 2>/dev/null)" = "simctl shutdown $sim" ]; then ok "and it shut that simulator down once"
else bad "and it shut that simulator down once: $(cat "$root/shutdowns" 2>/dev/null)"; fi
rm -f "$root/shutdowns"
check "a CoreSimulator error that stops xcodebuild before the run is a simulator fault" 69 \
"xcodebuild: error: Failed to prepare device for impending launch. (Underlying Error: The operation couldn't be completed. (com.apple.CoreSimulator.SimError error 405.))" "$(printf "$fault_advice" "com.apple.CoreSimulator.SimError")
xcodebuild exited 69 before the test run finished; the lines above and the log say why" 70 \
"xcodebuild: error: Failed to prepare device for impending launch. (Underlying Error: The operation couldn't be completed. (com.apple.CoreSimulator.SimError error 405.))"
rm -f "$root/shutdowns"
printf '{"testNodes":[{"name":"testSettingsAppearancePickerIsReachableAndWired()","result":"Failed","children":[{"name":"Test crashed with signal term."}]}]}' >"$root/tests.json"
STUB_TESTS=$(cat "$root/tests.json") check "a test killed by SIGTERM, as when its simulator shuts down mid-run, is a simulator fault" 69 \
"Restarting after unexpected exit, crash, or test timeout; summary will include totals from previous launches.
** TEST EXECUTE FAILED **" "$(printf "$fault_advice" "Test crashed with signal term")" 65 \
"Test Suite 'Selected tests' started at 2026-10-16 16:39:16.000.
Restarting after unexpected exit, crash, or test timeout; summary will include totals from previous launches.
	 Executed 22 tests, with 0 failures (0 unexpected) in 151.370 (151.406) seconds
** TEST EXECUTE FAILED **"
printf '{"testNodes":[{"name":"testLaunch()","result":"Failed","children":[{"name":"Test crashed with signal abrt."}]}]}' >"$root/tests.json"
STUB_TESTS=$(cat "$root/tests.json") check "a test the app crashed with SIGABRT stays a test failure" 65 \
"Restarting after unexpected exit, crash, or test timeout; summary will include totals from previous launches.
** TEST EXECUTE FAILED **" "" 65 \
"Restarting after unexpected exit, crash, or test timeout; summary will include totals from previous launches.
	 Executed 22 tests, with 0 failures (0 unexpected) in 151.370 (151.406) seconds
** TEST EXECUTE FAILED **"
rm -f "$root/shutdowns"
check "the UI test runner crashing before any test is a simulator fault, though the app crashing at launch is not" 69 \
"Testing failed:
	WorkoutTrackerUITests-Runner (3706) encountered an error (Early unexpected exit, operation never finished bootstrapping - no restart will be attempted. (Underlying Error: Test crashed with signal abrt while preparing to run tests.))
** TEST EXECUTE FAILED **" "$(printf "$fault_advice" "-Runner (3706) encountered an error (Early unexpected exit")
xcodebuild exited 69 before the test run finished; the lines above and the log say why" 65 \
"Testing failed:
	WorkoutTrackerUITests-Runner (3706) encountered an error (Early unexpected exit, operation never finished bootstrapping - no restart will be attempted. (Underlying Error: Test crashed with signal abrt while preparing to run tests.))
** TEST EXECUTE FAILED **"
rm -f "$root/shutdowns"
check "a test failure that names no simulator fault keeps xcodebuild's status and leaves the simulator up" 65 \
"✘ Test run with 1020 tests in 11 suites failed after 2.921 seconds with 1 issue.
** TEST EXECUTE FAILED **" "" 65 \
"◇ Test run started.
✘ Test run with 1020 tests in 11 suites failed after 2.921 seconds with 1 issue.
** TEST EXECUTE FAILED **"
[ ! -e "$root/shutdowns" ] && ok "and shut nothing down" || bad "and shut nothing down: $(cat "$root/shutdowns")"

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

cache_settings() {
    rm -f "$STUB_ARGS.build"
    printf '** TEST EXECUTE SUCCEEDED **\n' >"$root/xcodebuild.log"
    STUB_LOG=$root/xcodebuild.log STUB_RC=0 STUB_OUT=$root/out STUB_SEEN=$root/seen HOME=$root/home PATH="$root/bin:$PATH" \
        "$repo/scripts/test-sim.sh" --sim "$sim" unit >/dev/null 2>&1
    grep -E '^(COMPILATION_CACHE_|WORKOUT_COMPILE_CACHE_|(SWIFT|CLANG)_.*PREFIX_MAPPING)' "$STUB_ARGS.build"
}
# shellcheck disable=SC2016  # Xcode, not the shell, expands the $(...) macros per target
want_cache='COMPILATION_CACHE_ENABLE_CACHING=$(WORKOUT_COMPILE_CACHE_$(PROJECT_NAME:c99extidentifier):default=YES)'"
WORKOUT_COMPILE_CACHE_WorkoutTracker=NO
COMPILATION_CACHE_CAS_PATH=$root/home/Library/Developer/Xcode/DerivedData/WorkoutTracker.CompilationCache.noindex
COMPILATION_CACHE_LIMIT_SIZE=2G
COMPILATION_CACHE_ENABLE_DIAGNOSTIC_REMARKS=YES
SWIFT_ENABLE_PREFIX_MAPPING=YES
CLANG_ENABLE_PREFIX_MAPPING=YES
SWIFT_ENABLE_PROJECT_PREFIX_MAPPING=YES
CLANG_ENABLE_PROJECT_PREFIX_MAPPING=YES"'
SWIFT_OTHER_PREFIX_MAPPINGS=$(WORKSPACE_DIR:dir:standardizepath)=/^wt $(OBJROOT:dir:standardizepath:dir:standardizepath)=/^dd
CLANG_OTHER_PREFIX_MAPPINGS=$(WORKSPACE_DIR:dir:standardizepath)=/^wt $(OBJROOT:dir:standardizepath:dir:standardizepath)=/^dd'
got=$(cache_settings)
if [ "$got" = "$want_cache" ]; then
    ok "a build puts package targets on the repo's own compilation cache, with macros left for Xcode to expand"
else
    bad "a build puts package targets on the repo's own compilation cache, with macros left for Xcode to expand"
    printf '    got:\n%s\n    want:\n%s\n' "$got" "$want_cache"
fi
got=$(WORKOUT_COMPILE_CACHE=0 cache_settings)
if [ -z "$got" ] && [ -s "$STUB_ARGS.build" ]; then ok "WORKOUT_COMPILE_CACHE=0 builds with none of the cache settings"
else bad "WORKOUT_COMPILE_CACHE=0 builds with none of the cache settings: $got"; fi
# shellcheck disable=SC2016  # Xcode, not the shell, expands the $(...) macros per target
want_lean='COMPILER_INDEX_STORE_ENABLE=$(WORKOUT_INDEX_STORE_$(PROJECT_NAME:c99extidentifier):default=Default)
WORKOUT_INDEX_STORE_WorkoutTracker=NO'
for cache in 1 0; do
    got=$(WORKOUT_COMPILE_CACHE=$cache cache_settings >/dev/null; grep -E '^(COMPILER_INDEX_STORE_ENABLE|WORKOUT_INDEX_STORE_)' "$STUB_ARGS.build")
    if [ "$got" = "$want_lean" ]; then ok "WORKOUT_COMPILE_CACHE=$cache builds the project's own targets without an index store"
    else bad "WORKOUT_COMPILE_CACHE=$cache builds the project's own targets without an index store: $got"; fi
done

run_sim() {
    rm -f "$root/seen" "$root/load-read" "$STUB_ARGS.build"
    printf '✔ Test run with 1 test in 1 suite passed after 0.001 seconds.\n** TEST EXECUTE SUCCEEDED **\n' >"$root/xcodebuild.log"
    STUB_LOG=$root/xcodebuild.log STUB_RC=0 STUB_OUT=$root/out STUB_SEEN=$root/seen HOME=$root/home PATH="$root/bin:$PATH" \
        "$repo/scripts/test-sim.sh" "$@" >"$root/out" 2>"$root/err"
}
built_targets() {
    grep -qx test-sim "$STUB_ARGS.build" 2>/dev/null || { echo "no build of the test-sim scheme"; return; }
    sed -nE 's/.*BlueprintName = "(WorkoutTracker[A-Za-z]*Tests)".*/\1/p' \
        "$repo/WorkoutTracker.xcodeproj/xcuserdata/$(id -un).xcuserdatad/xcschemes/test-sim.xcscheme" | paste -sd ' ' -
}
while IFS='|' read -r selection want; do
    # shellcheck disable=SC2086  # the selection is several words
    run_sim --sim "$sim" $selection
    got=$(built_targets)
    if [ "$got" = "$want" ]; then ok "a build of '$selection' builds only $want"
    else bad "a build of '$selection' builds only $want: got '$got'"; fi
done <<'CASES'
unit|WorkoutTrackerTests
visual WorkoutTrackerUITests/WorkoutTrackerUISmokeTests/testLaunch|WorkoutTrackerSnapshotTests WorkoutTrackerUITests
all|WorkoutTrackerTests WorkoutTrackerSnapshotTests WorkoutTrackerUITests
CASES

run_sim --sim "$sim" WorkoutTrackerTest/RPETableTests
status=$?
if [ $status = 2 ] && [ "$(cat "$root/err")" = "no test target WorkoutTrackerTest in the WorkoutTracker scheme" ] && [ ! -e "$root/seen" ]; then
    ok "a TEST-ID whose target the scheme does not test exits 2 before xcodebuild runs"
else
    bad "a TEST-ID whose target the scheme does not test exits 2 before xcodebuild runs: exit $status, stderr '$(cat "$root/err")'"
fi

xctestrun WorkoutTrackerTests >"$products/test-sim_iphonesimulator27.0-arm64.xctestrun"
run_sim --no-build --sim "$sim" unit visual
status=$?
want="the last build covered WorkoutTrackerTests but not WorkoutTrackerSnapshotTests; run without --no-build"
if [ $status = 65 ] && [ "$(cat "$root/err")" = "$want" ] && [ ! -e "$root/seen" ]; then
    ok "--no-build refuses a test target the last build left out, before xcodebuild runs"
else
    bad "--no-build refuses a test target the last build left out, before xcodebuild runs: exit $status, stderr '$(cat "$root/err")'"
fi
run_sim --no-build --sim "$sim" WorkoutTrackerTests/RPETableTests
status=$?
if [ $status = 0 ] && [ -e "$root/seen" ]; then ok "--no-build runs a TEST-ID in a target the last build covered"
else bad "--no-build runs a TEST-ID in a target the last build covered: exit $status, stderr '$(cat "$root/err")'"; fi

printf '\npassed %s, failed %s\n' "$pass" "$fail"
[ "$fail" -eq 0 ] || exit 1
