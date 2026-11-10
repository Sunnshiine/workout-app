#!/usr/bin/env bash
set -uo pipefail

script_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
checker="$script_dir/../lint-simulators.py"

tmp=$(mktemp -d) || exit 3
trap 'rm -rf "$tmp"' EXIT
pass=0
fail=0

ok()  { pass=$((pass + 1)); printf '  ok   %s\n' "$1"; }
bad() { fail=$((fail + 1)); printf '  FAIL %s\n' "$1"; }

check() { out=$(python3 "$checker" "$1" 2>&1); status=$?; }

expect_exit() {
    if [ "$status" -eq "$2" ]; then ok "$1 exits $2"; else bad "$1 exits $2, got $status: $out"; fi
}

expect_errors() {
    local got
    got=$(printf '%s\n' "$out" | grep -c '^error: ')
    if [ "$got" -eq "$2" ]; then ok "$1 reports $2 error(s)"; else bad "$1 reports $2 error(s), got $got: $out"; fi
}

tree() {
    local root="$tmp/$1"
    mkdir -p "$root/scripts/tests" "$root/scripts/ci" "$root/.agents/skills/verify/tests"
    printf '%s\n' "$root"
}

echo "a simulator taken through Simlock passes"
root=$(tree clean)
cat > "$root/scripts/run.sh" <<'SH'
simlock lease --platform ios --device 'iPhone 17 Pro' --bind-pid $$
simlock simctl bootstatus "$sim" -b
simlock simctl shutdown "$sim"
xcrun simctl install "$sim" "$app"
xcodebuild build-for-testing -destination "platform=iOS Simulator,id=$sim"
SH
check "$root"
expect_exit "clean" 0

echo "each way around the lease is an error"
root=$(tree bypass)
cat > "$root/scripts/run.sh" <<'SH'
xcrun simctl boot "$udid"
xcrun simctl create lane "iPhone 17 Pro" "$runtime"
simctl shutdown "$udid"
simctl clone template lane
xcodebuild build -destination 'platform=iOS Simulator,name=iPhone 17 Pro'
xcodebuild test -destination "platform=iOS Simulator,id=$udid"
SH
printf 'Run `xcrun simctl erase <udid>` to reset it.\n' > "$root/.agents/skills/verify/SKILL.md"
check "$root"
expect_exit "bypass" 1
expect_errors "bypass" 7
printf '%s\n' "$out" | grep -q '^error: scripts/run.sh:5: names a simulator by model' \
    && ok "a named destination cites its line" || bad "a named destination cites its line: $out"

echo "an exception waives only the rule it names"
root=$(tree excepted)
printf 'xcodebuild test-without-building -xctestrun "$x"\n' > "$root/scripts/test-sim.sh"
printf 'xcrun simctl create ci "$type" "$runtime"\n' > "$root/scripts/ci/ensure-simulator.sh"
printf 'xcrun simctl boot fake\n' > "$root/scripts/tests/fake-xcrun"
check "$root"
expect_exit "exceptions" 0
printf 'xcrun simctl boot "$sim"\n' >> "$root/scripts/test-sim.sh"
check "$root"
expect_errors "a boot in test-sim.sh" 1

echo "a root with neither directory is a usage error"
mkdir "$tmp/empty"
check "$tmp/empty"
expect_exit "empty" 2

echo
echo "$pass passed, $fail failed"
[ "$fail" -eq 0 ]
