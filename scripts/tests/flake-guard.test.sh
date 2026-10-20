#!/bin/bash
set -uo pipefail

# shellcheck source=scripts/tests/flake-guard-harness.sh
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/flake-guard-harness.sh"

guard
verify "nothing changed: exits 0 before any xcodebuild call" 0 "$(status_line nothing 0 0 0)" \
    "flake-guard: nothing to repeat; no test file changed since $base."
[ ! -e "$STUB_ARGS.enumerate" ] && [ ! -e "$STUB_ARGS.run" ] || bad "nothing changed: xcodebuild ran"

sed -i '' -e 's/#expect(true)/#expect(1 == 1)/' -e 's/n > 0/n >= 1/' "$repo/Tests/Unit/NestedTests.swift"

STUB_LOG=$passing guard
same "a changed file repeats its enumerated tests and passes" "$out" \
"host: hw.ncpu=2 load1=1.50 hogs=0
selected 2 tests from 3 changed declarations:
  WorkoutTrackerTests/NestedTests/aNestedTest()  Tests/Unit/NestedTests.swift:4
  WorkoutTrackerTests/aParametrizedTest(n:)  Tests/Unit/NestedTests.swift:9
not in the enumeration (platform-guarded or excluded): aGuardedTest
run: 20 iterations of 2 tests under 0 hogs, budget 300s, stall 120s
flake-guard: passed; 2 tests x 20 repetitions under load in Ns
$(status_line passed 2 20 0)"
verify "a pass exits 0" 0 "$(status_line passed 2 20 0)"
same "the response file holds exactly the two selected identifiers" "$(cat "$run/selection.ids")" \
"WorkoutTrackerTests/NestedTests/aNestedTest()
WorkoutTrackerTests/aParametrizedTest(n:)"
if [ "$(head -1 "$STUB_ARGS.run")" = test-without-building ] && follows -derivedDataPath "$build/DerivedData" &&
    follows -only-testing "@$run/selection.ids" && follows -test-iterations 20 &&
    grep -qx -- -run-tests-until-failure "$STUB_ARGS.run"; then
    ok "the run reuses the gate's products and repeats the response file's tests until a failure"
else
    bad "the run's arguments:"
    sed 's/^/    /' "$STUB_ARGS.run"
fi

STUB_LOG=$failing_on_seven STUB_RC=65 GITHUB_ACTIONS=true guard
verify "a failure on repetition 7 names the test, its declaration, and its first issue" 1 "$(status_line failed 2 2 1)" \
    "flake-guard: FAILED on repetition 7 of 20 under 0 hogs; load1 now 1.50" \
    "✘ Test aNestedTest() recorded an issue at NestedTests.swift:4:31: Expectation failed: elapsed < .seconds(10)"
same "only the failing test is reported, annotated on its declaration, with its reproduce line" \
    "$(printf '%s\n' "$out" | grep -E '^(  ✘|::|reproduce:)')" \
"  ✘ WorkoutTrackerTests/NestedTests/aNestedTest()  Tests/Unit/NestedTests.swift:4
::error file=Tests/Unit/NestedTests.swift,line=4,title=flaky under load::WorkoutTrackerTests/NestedTests/aNestedTest() failed on repetition 7 of 20 under 0 busy loops on 2 cores
reproduce: scripts/flake-hunt.sh --repetitions 200 aNestedTest"

STUB_LOG=$crashed_on_two STUB_RC=65 guard
verify "a run that died before the Failing tests: block names the test it left running" 1 "$(status_line failed 2 1 1)" \
    "flake-guard: FAILED on repetition 2 of 20 under 0 hogs; load1 now 1.50" \
    "  ✘ WorkoutTrackerTests/NestedTests/aNestedTest()  Tests/Unit/NestedTests.swift:4" \
    "reproduce: scripts/flake-hunt.sh --repetitions 200 aNestedTest"

STUB_LOG=$one_of_two_ran guard
verify "a pass that ran fewer tests than it selected is broken" 65 "$(status_line broken 2 2 65)" \
    "2>flake-guard: selected 2 tests, the run reports 1; see $run/run.log"

STUB_LOG=$never_repeated guard
verify "a pass that never repeated is broken" 65 "$(status_line broken 2 1 65)" \
    "2>flake-guard: asked for 20 iterations, the log shows 1; see $run/run.log"

guard --xcodebuild "$root/empty"
verify "no products: exits 65" 65 "$(status_line broken 0 0 65)" \
    "2>flake-guard: no test products under $root/empty; run scripts/crap.sh gate --xcodebuild $root/empty first."
[ ! -e "$STUB_ARGS.enumerate" ] && [ ! -e "$STUB_ARGS.run" ] || bad "no products: xcodebuild ran"

inventory
guard
verify "an empty enumeration exits 65 and names its log" 65 "$(status_line broken 0 0 65)" \
    "2>flake-guard: listing the tests the products hold found none; see $run/enumerate.log"
[ -e "$STUB_ARGS.enumerate" ] && [ ! -e "$STUB_ARGS.run" ] || bad "an empty enumeration: enumerated $([ -e "$STUB_ARGS.enumerate" ] && echo once || echo never), launched a run $([ -e "$STUB_ARGS.run" ] && echo anyway || echo never)"

inventory 'WorkoutTrackerTests/OtherTests/anUntouchedTest()'
guard
verify "changed tests the enumeration lacks: exits 0 without a run" 0 "$(status_line nothing 0 0 0)" \
    "not in the enumeration (platform-guarded or excluded): aGuardedTest aNestedTest aParametrizedTest" \
    "flake-guard: nothing to repeat; no changed test is in the enumeration."
[ ! -e "$STUB_ARGS.run" ] || bad "changed tests the enumeration lacks: a run launched"
inventory 'WorkoutTrackerTests/NestedTests/aNestedTest()' 'WorkoutTrackerTests/aParametrizedTest(n:)'

STUB_LOG=$started_once STUB_SLEEP=4 GITHUB_ACTIONS=true guard --stall 1
verify "a run with no progress for --stall seconds is killed and names the running test" 1 "$(status_line hung 2 1 1)" \
    "flake-guard: no progress for 1s; killed the run on repetition 1 of 20" \
    "  ✘ aNestedTest()  Tests/Unit/NestedTests.swift:4" \
    "::error file=Tests/Unit/NestedTests.swift,line=4,title=hung under load::aNestedTest() was still running when the guard killed the run (no progress for 1s) under 0 busy loops on 2 cores"

STUB_LOG=$repeating STUB_SLEEP=4 GITHUB_ACTIONS=true guard --budget 1
verify "the budget stops a run that repeated every test twice, with a warning" 0 "$(status_line stopped 2 2 0)" \
    "flake-guard: stopped at the 1s budget after 2 of 20 repetitions; raise --budget to repeat more" \
    "::warning title=flake guard stopped at its budget::flake-guard: stopped at the 1s budget after 2 of 20 repetitions; raise --budget to repeat more"

STUB_LOG=$repeating STUB_SLEEP=6 SIGTERM_AFTER=2 guard
verify "TERM kills the run and names the tests still running" 1 "$(status_line hung 2 2 1)" \
    "flake-guard: interrupted; killed the run on repetition 2 of 20" \
    "  ✘ aNestedTest()  Tests/Unit/NestedTests.swift:4" \
    "  ✘ aParametrizedTest(n:)  Tests/Unit/NestedTests.swift:9"

guard --base no-such-rev
verify "a base git cannot resolve exits 2" 2 "host: hw.ncpu=2 load1=1.50 hogs=0" \
    "2>error: git cannot find where HEAD left 'no-such-rev'."

printf '\npassed %s, failed %s\n' "$pass" "$fail"
[ "$fail" -eq 0 ] || exit 1
