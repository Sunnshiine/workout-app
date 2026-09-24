#!/usr/bin/env bash
set -uo pipefail

script_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
root=$(mktemp -d) || exit 3
sim=test-sim-test-$$
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
cat "$STUB_LOG"
exit "$STUB_RC"
STUB
chmod +x "$root/bin/plutil" "$root/bin/xcodebuild"

check() {
    local name=$1 want_status=$2 want_out=$3 want_err=$4 xcodebuild_status=$5 log=$6
    printf '%s\n' "$log" >"$root/xcodebuild.log"
    STUB_LOG=$root/xcodebuild.log STUB_RC=$xcodebuild_status HOME=$root/home PATH="$root/bin:$PATH" \
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

printf '\npassed %s, failed %s\n' "$pass" "$fail"
[ "$fail" -eq 0 ] || exit 1
