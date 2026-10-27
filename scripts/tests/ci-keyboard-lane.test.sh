#!/bin/bash
set -uo pipefail

scripts_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
source_script=$scripts_dir/ci-keyboard-lane.sh
root=$(mktemp -d) || exit 3
trap 'rm -rf "$root"' EXIT
repo=$root/repo
calls=$root/calls
pass=0
fail=0

ok()  { pass=$((pass + 1)); printf '  ok   %s\n' "$1"; }
bad() { fail=$((fail + 1)); printf '  FAIL %s\n' "$1"; }

mkdir -p "$repo/scripts" "$repo/Tests/UI" "$root/bin"
cp "$source_script" "$repo/scripts/"
tests_file=$repo/Tests/UI/KeyboardLaneUITests.swift
two_tests='    @MainActor\n    func testOne() {}\n    @MainActor\n    func testTwo() {}\n'
printf '%b' "$two_tests" >"$tests_file"
cat >"$repo/scripts/keyboard-lane-paths.sh" <<'STUB'
#!/bin/sh
echo "$STUB_DECISION"
STUB
cat >"$repo/scripts/sim-keyboard.sh" <<'STUB'
#!/bin/sh
echo "keyboard: $2 ensured"
STUB
cat >"$root/bin/xcodebuild" <<'STUB'
#!/bin/sh
printf '%s\n' "$@" >>"$STUB_CALLS"
exit "${STUB_XCODEBUILD_STATUS:-0}"
STUB
cat >"$root/bin/xcrun" <<'STUB'
#!/bin/sh
case $1 in
    simctl) echo 0 ;;
    xcresulttool) echo "$STUB_SUMMARY" ;;
esac
STUB
chmod +x "$repo/scripts/"*.sh "$root/bin/"*

# Prints the argument xcodebuild was given after the flag $1.
arg_after() { awk -v flag="$1" 'found { print; exit } $0 == flag { found = 1 }' "$calls"; }

summary() { printf '{"passedTests":%d,"failedTests":%d,"skippedTests":%d,"expectedFailures":0}' "$@"; }

# Runs the lane with the given environment and prints its output and exit status.
lane() {
    : >"$calls"
    : >"$root/env"
    env PATH="$root/bin:$PATH" STUB_CALLS="$calls" GITHUB_ENV="$root/env" GITHUB_EVENT_NAME=pull_request \
        STUB_DECISION=run=true STUB_SUMMARY="$(summary 2 0 0)" "$@" \
        "$repo/scripts/ci-keyboard-lane.sh" SIM-UDID /tmp/run.xctestrun 2>&1
    echo "exit=$?"
}

out=$(lane STUB_DECISION=run=false)
if [ "$(tail -1 <<<"$out")" = exit=0 ] && [ ! -s "$calls" ]; then
    ok "a pull request the lane does not reach runs no test"
else
    bad "a pull request the lane does not reach runs no test, got: $out $(cat "$calls")"
fi

for decision in '' garbage $'run=true\nrun=false'; do
    out=$(lane STUB_DECISION="$decision")
    if [ "$(tail -1 <<<"$out")" = exit=1 ] && [ ! -s "$calls" ] && grep -q "::error::" <<<"$out"; then
        ok "a path decision of '${decision//$'\n'/\\n}' fails the lane and runs no test"
    else
        bad "a path decision of '${decision//$'\n'/\\n}' fails the lane and runs no test, got: $out"
    fi
done

out=$(lane GITHUB_EVENT_NAME=push)
if [ "$(tail -1 <<<"$out")" = exit=0 ] && [ ! -s "$calls" ]; then
    ok "a push that was not dispatched runs no test"
else
    bad "a push that was not dispatched runs no test, got: $out"
fi

out=$(lane GITHUB_EVENT_NAME=workflow_dispatch DISPATCHED=true)
if grep -q -- '-only-testing:WorkoutTrackerUITests/KeyboardLaneUITests' "$calls"; then
    ok "a dispatch with keyboard-lane=true runs the lane"
else
    bad "a dispatch with keyboard-lane=true runs the lane, got: $out"
fi

out=$(lane)
if [ "$(tail -1 <<<"$out")" = exit=0 ] && grep -q "2 of 2 tests ran" <<<"$out"; then
    ok "every declared test ran and passed"
else
    bad "every declared test ran and passed, got: $out"
fi
if [ "$(arg_after -xctestrun)" = /tmp/run.xctestrun ] \
    && [ "$(arg_after -destination)" = 'platform=iOS Simulator,id=SIM-UDID' ]; then
    ok "xcodebuild runs the build's xctestrun on the simulator"
else
    bad "xcodebuild runs the build's xctestrun on the simulator, got: $(cat "$calls")"
fi
step_seconds=$(awk '/id: keyboard$/ { found = 1 } found && /timeout-minutes:/ { print $2 * 60; exit }' \
    "$scripts_dir/../.github/workflows/ci.yml")
per_test=$(arg_after -default-test-execution-time-allowance)
cap=$(arg_after -maximum-test-execution-time-allowance)
if [ "$(arg_after -test-timeouts-enabled)" = YES ] && [ "${step_seconds:-0}" -gt 0 ] \
    && [ "${per_test:-0}" -gt 0 ] && [ "$per_test" -le "${cap:-0}" ] && [ "$cap" -lt "$step_seconds" ]; then
    ok "a hung test fails inside the step: per-test $per_test s, cap $cap s, step $step_seconds s"
else
    bad "a hung test fails inside the step, got: per-test '$per_test' cap '$cap' step '$step_seconds'"
fi
if grep -q "preference before the lane: 0" <<<"$out" && grep -q "preference after the lane: 0" <<<"$out"; then
    ok "the keyboard preference is printed before and after"
else
    bad "the keyboard preference is printed before and after, got: $out"
fi
if grep -qE '^KEYBOARD_LANE_SECONDS=[0-9]+$' "$root/env"; then
    ok "the lane's time reaches GITHUB_ENV"
else
    bad "the lane's time reaches GITHUB_ENV, got: $(cat "$root/env")"
fi

out=$(lane STUB_SUMMARY="$(summary 0 0 0)")
if [ "$(tail -1 <<<"$out")" = exit=1 ] && grep -q "declares 2 tests and the bundle shows 0 ran" <<<"$out"; then
    ok "a passing run with no test fails"
else
    bad "a passing run with no test fails, got: $out"
fi

out=$(lane STUB_SUMMARY="$(summary 1 0 1)")
if [ "$(tail -1 <<<"$out")" = exit=1 ]; then
    ok "a skipped test fails the lane"
else
    bad "a skipped test fails the lane, got: $out"
fi

out=$(lane STUB_SUMMARY=garbage)
if [ "$(tail -1 <<<"$out")" = exit=1 ] && grep -q "shows none ran" <<<"$out"; then
    ok "an unreadable bundle fails the lane"
else
    bad "an unreadable bundle fails the lane, got: $out"
fi

out=$(lane STUB_XCODEBUILD_STATUS=65)
if [ "$(tail -1 <<<"$out")" = exit=65 ] && grep -q "preference after the lane" <<<"$out" \
    && grep -q KEYBOARD_LANE_SECONDS "$root/env"; then
    ok "a red run exits with xcodebuild's status and still reports"
else
    bad "a red run exits with xcodebuild's status and still reports, got: $out"
fi

for shape in 'tab-indented' 'unindented' attributed; do
    case $shape in
        tab-indented) printf '\t@MainActor\n\tfunc testOne() {}\n\tfunc testTwo() {}\n' >"$tests_file" ;;
        unindented) printf 'func testOne() {}\nfunc testTwo() async throws {}\n' >"$tests_file" ;;
        *) printf '    @MainActor func testOne() {}\n    private func testTwo ( ) {}\n' >"$tests_file" ;;
    esac
    out=$(lane)
    if [ "$(tail -1 <<<"$out")" = exit=0 ] && grep -q "2 of 2 tests ran" <<<"$out"; then
        ok "two $shape tests count as two declared"
    else
        bad "two $shape tests count as two declared, got: $out"
    fi
done

printf '    // func testOld() {}\n    func testHelper(_ x: Int) {}\n    func setUp() {}\n' >"$tests_file"
out=$(lane STUB_SUMMARY="$(summary 0 0 0)")
if [ "$(tail -1 <<<"$out")" = exit=1 ] && grep -q "declares no test" <<<"$out" && [ ! -s "$calls" ]; then
    ok "a file that declares no test fails the lane before xcodebuild"
else
    bad "a file that declares no test fails the lane before xcodebuild, got: $out $(cat "$calls")"
fi
printf '%b' "$two_tests" >"$tests_file"

out=$("$source_script" only-one 2>/dev/null; echo "exit=$?")
if [ "$out" = exit=2 ]; then ok "one argument exits 2"; else bad "one argument exits 2, got: $out"; fi

printf '%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" = 0 ]
