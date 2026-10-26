#!/bin/bash
set -uo pipefail

source_script=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/ci-keyboard-lane.sh
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
printf '    @MainActor\n    func testOne() {}\n    @MainActor\n    func testTwo() {}\n' \
    >"$repo/Tests/UI/KeyboardLaneUITests.swift"
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
echo "xcodebuild $*" >>"$STUB_CALLS"
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
if grep -q -- '-xctestrun /tmp/run.xctestrun -destination platform=iOS Simulator,id=SIM-UDID' "$calls" \
    && grep -q -- '-test-timeouts-enabled YES -default-test-execution-time-allowance 180' "$calls"; then
    ok "xcodebuild runs the build's xctestrun on the simulator with a per-test limit"
else
    bad "xcodebuild runs the build's xctestrun on the simulator with a per-test limit, got: $(cat "$calls")"
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

out=$("$source_script" only-one 2>/dev/null; echo "exit=$?")
if [ "$out" = exit=2 ]; then ok "one argument exits 2"; else bad "one argument exits 2, got: $out"; fi

printf '%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" = 0 ]
