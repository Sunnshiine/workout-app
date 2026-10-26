#!/bin/bash
# Tests scripts/ui-suite.sh and scripts/ui-flake-guard.sh against a stub xcodebuild and xcrun.
set -uo pipefail
script_dir=$(cd "$(dirname "$0")" && pwd)
root=$(mktemp -d) || exit 3
trap 'rm -rf "$root"' EXIT
repo=$root/repo
mkdir -p "$repo/scripts" "$repo/Tests/UI" "$root/bin"
find "$script_dir/.." -maxdepth 1 -type f -exec cp {} "$repo/scripts/" \;
unset GITHUB_ACTIONS GITHUB_STEP_SUMMARY
export STUB_ARGS=$root/args STUB_TESTS=$root/tests.json
pass=0
fail=0
ok() { pass=$((pass + 1)); printf '  ok   %s\n' "$1"; }
bad() { fail=$((fail + 1)); printf '  FAIL %s\n' "$1"; }
check() { if eval "$2"; then ok "$1"; else bad "$1"; sed 's/^/       | /' "$root/out"; fi; }

cat >"$root/bin/xcodebuild" <<'STUB'
#!/bin/sh
printf '%s\n' "$@" >"$STUB_ARGS"
printf '%s\n' "$STUB_LOG"
[ -z "${STUB_SLEEP:-}" ] || sleep "$STUB_SLEEP"
exit "${STUB_RC:-0}"
STUB
cat >"$root/bin/xcrun" <<'STUB'
#!/bin/sh
[ "$1 $2 $3 $4" = "xcresulttool get test-results tests" ] || exit 64
[ -f "$STUB_TESTS" ] && cat "$STUB_TESTS"
STUB
chmod +x "$root/bin/xcodebuild" "$root/bin/xcrun"
export PATH="$root/bin:$PATH"

tests_json() {
    python3 -c '
import json, sys
cases = [{"nodeType": "Test Case", "nodeIdentifier": n, "result": r, "durationInSeconds": float(d)}
         for n, r, d in (a.split(":") for a in sys.argv[1:])]
print(json.dumps({"testNodes": [{"nodeType": "Unit test bundle", "children": cases}]}))' "$@" >"$STUB_TESTS"
}

suite() { (cd "$repo" && scripts/ui-suite.sh --xctestrun run.xctestrun --destination id=SIM --out "$root/ui" "$@") >"$root/out" 2>&1; }
guard() { (cd "$repo" && scripts/ui-flake-guard.sh --xctestrun run.xctestrun --destination id=SIM --out "$root/guard" "$@") >"$root/out" 2>&1; }

echo "ui-suite.sh"
STUB_LOG="Test Case '-[WorkoutTrackerUITests.SmokeTests testA]' passed (1.0 seconds)."
export STUB_LOG
tests_json "SmokeTests/testA():Passed:12" "SmokeTests/testB():Skipped:0" "QueueTests/testC():Passed:40"
suite; status=$?
check "a green run under its SLA exits 0" '[ $status = 0 ] && tail -1 "$root/out" | grep -q "result=passed .* passed=2 failed=0 skipped=1 exit=0"'
check "a run under its SLA asks for nothing" '! grep -q "Hill-climb" "$root/out"'
check "it runs only the UI bundle, without building" 'grep -qx test-without-building "$STUB_ARGS" && grep -qx -- -only-testing:WorkoutTrackerUITests "$STUB_ARGS"'

summary=$root/summary
STUB_SLEEP=2 GITHUB_ACTIONS=true GITHUB_STEP_SUMMARY=$summary suite --sla 1; status=$?
check "a run over its SLA still passes" '[ $status = 0 ] && tail -1 "$root/out" | grep -q "result=passed"'
check "a run over its SLA asks for a hill-climb, slowest test first" 'grep -q "over its 1s SLA. Hill-climb UI test speed" "$root/out" && grep -m1 -A1 "Hill-climb" "$root/out" | tail -1 | grep -q "QueueTests/testC"'
check "under Actions it annotates and summarizes the SLA" 'grep -q "^::warning title=UI suite over its 1s SLA::" "$root/out" && grep -q "UI suite over its 1s SLA" "$summary"'

STUB_SLEEP=5 STUB_LOG="Test Case '-[WorkoutTrackerUITests.SmokeTests testA]' started.
Test Case '-[WorkoutTrackerUITests.SmokeTests testA]' passed (1.0 seconds).
Test Case '-[WorkoutTrackerUITests.QueueTests testStuck]' started." suite --cap 1; status=$?
check "at its cap the run fails" '[ $status = 1 ] && tail -1 "$root/out" | grep -q "result=capped"'
check "at its cap it names the test still running, and only that one" 'grep -q "✘ QueueTests/testStuck" "$root/out" && ! grep -q "✘ SmokeTests/testA" "$root/out" && grep -q "with 1 tests finished" "$root/out"'

STUB_SLEEP=5 STUB_LOG="Test case 'QueueTests.testParallel()' started on 'Clone 1 of iPhone'" suite --cap 1
check "at its cap it reads a parallel run's log too" 'grep -q "✘ QueueTests/testParallel" "$root/out"'

tests_json "SmokeTests/testA():Failed:12" "SmokeTests/testB():Passed:3"
STUB_RC=65 suite; status=$?
check "a failing test fails the run" '[ $status = 1 ] && tail -1 "$root/out" | grep -q "result=failed .* failed=1"'

rm -f "$STUB_TESTS"
suite; status=$?
check "a run with no readable result is broken, not green" '[ $status = 65 ] && tail -1 "$root/out" | grep -q "result=broken"'

suite --sla soon; status=$?
check "a non-numeric SLA is a usage error" '[ $status = 2 ]'

echo "ui-flake-guard.sh"
cat >"$repo/Tests/UI/QueueUITests.swift" <<'SWIFT'
import XCTest

final class QueueUITests: XCTestCase {
    func testOpens() {
        XCTAssertTrue(true)
    }

    func testCloses() {
        XCTAssertTrue(true)
    }
}
SWIFT
git -C "$repo" init -q -b main
git -C "$repo" config user.email test@example.com
git -C "$repo" config user.name test
git -C "$repo" config commit.gpgsign false
git -C "$repo" add -A && git -C "$repo" commit -qm base

rm -f "$STUB_ARGS"
guard --base HEAD; status=$?
check "no changed UI test runs nothing" '[ $status = 0 ] && tail -1 "$root/out" | grep -q "result=nothing tests=0" && [ ! -f "$STUB_ARGS" ]'

sed -i '' 's/XCTAssertTrue(true)$/XCTAssertTrue(1 == 1)/' "$repo/Tests/UI/QueueUITests.swift"
sed -i '' '9s/1 == 1/true/' "$repo/Tests/UI/QueueUITests.swift"
git -C "$repo" commit -qam "change testOpens"
STUB_LOG="Test Case '-[WorkoutTrackerUITests.QueueUITests testOpens]' passed (1.0 seconds)." guard --base HEAD^; status=$?
check "a changed test is repeated, and passes" '[ $status = 0 ] && tail -1 "$root/out" | grep -q "result=passed tests=1 iterations=5"'
check "it repeats only the changed test, until a failure" 'grep -qx -- -only-testing:WorkoutTrackerUITests/QueueUITests/testOpens "$STUB_ARGS" && ! grep -q testCloses "$STUB_ARGS" && grep -qx -- -run-tests-until-failure "$STUB_ARGS"'

STUB_RC=65 STUB_LOG="Test Case '-[WorkoutTrackerUITests.QueueUITests testOpens]' failed (1.0 seconds).
Failing tests:
	QueueUITests.testOpens()" GITHUB_ACTIONS=true guard --base HEAD^; status=$?
check "a failing repetition fails the guard" '[ $status = 1 ] && tail -1 "$root/out" | grep -q "result=failed"'
check "a failure names the line that reproduces it, and annotates the test" 'grep -q "reproduce: scripts/test-sim.sh WorkoutTrackerUITests/QueueUITests/testOpens" "$root/out" && grep -q "^::error file=Tests/UI/QueueUITests.swift,line=4," "$root/out"'

STUB_SLEEP=5 STUB_LOG="Test Case '-[WorkoutTrackerUITests.QueueUITests testOpens]' passed (1.0 seconds)." guard --base HEAD^ --budget 1; status=$?
check "the budget stops a passing run without failing it" '[ $status = 0 ] && tail -1 "$root/out" | grep -q "result=stopped"'

STUB_LOG="" guard --base HEAD^; status=$?
check "a run that ran none of the selection is broken" '[ $status = 65 ] && tail -1 "$root/out" | grep -q "result=broken"'

echo "passed $pass, failed $fail"
[ "$fail" = 0 ]
