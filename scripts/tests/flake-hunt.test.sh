#!/usr/bin/env bash
set -uo pipefail

script_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
root=$(mktemp -d) || exit 3
trap 'rm -rf "$root"' EXIT
repo=$root/repo
mkdir -p "$repo/scripts" "$root/bin"
cp "$script_dir/../flake-hunt.sh" "$script_dir/../test-log-summary.awk" "$repo/scripts/"
pass=0
fail=0

ok()  { pass=$((pass + 1)); printf '  ok   %s\n' "$1"; }
bad() { fail=$((fail + 1)); printf '  FAIL %s\n' "$1"; }

cat >"$root/bin/swift" <<'STUB'
#!/bin/sh
[ "$1" = test ] || exit 0
cat "$STUB_LOG"
exit "$STUB_RC"
STUB
chmod +x "$root/bin/swift"

check() {
    local name=$1 want_status=$2 want_out=$3 swift_status=$4 log=$5
    printf '%s\n' "$log" >"$root/swift.log"
    STUB_LOG=$root/swift.log STUB_RC=$swift_status PATH="$root/bin:$PATH" \
        "$repo/scripts/flake-hunt.sh" --load 0 --repetitions 1 >"$root/out" 2>"$root/err"
    local status=$?
    local out
    out=$(grep -v '^log: ' "$root/out")
    local first
    first=$(head -1 "$root/out")
    [ -f "${first#log: }" ] || bad "$name: the first line is not the log path: $first"
    if [ "$status" = "$want_status" ] && [ "$out" = "$want_out" ]; then
        ok "$name"
    else
        bad "$name: exit $status (want $want_status)"
        printf '    stdout:\n%s\n    stderr:\n%s\n' "$out" "$(cat "$root/err")"
    fi
}

check "a passing run with a known issue prints its summary" 0 \
"━ Test run with 1020 tests in 11 suites passed after 2.921 seconds with 1 known issue." 0 \
"◇ Test run started.
━ Test replanningWhenTheRefetchFails() recorded a known issue at SyncCoordinatorReplanTests.swift:693:9: Expectation failed
✔ Test canMoveOnIsFalseOnLastSession() passed after 0.010 seconds.
━ Test run with 1020 tests in 11 suites passed after 2.921 seconds with 1 known issue."

check "a passing run prints its summary" 0 \
"✔ Test run with 1020 tests in 11 suites passed after 2.921 seconds." 0 \
"◇ Test run started.
✔ Test canMoveOnIsFalseOnLastSession() passed after 0.010 seconds.
✔ Test run with 1020 tests in 11 suites passed after 2.921 seconds."

check "a failing run prints each issue, the failed test, and the summary" 1 \
"✘ Test failsOnPurpose() recorded an issue at Issue769FailingProbeTests.swift:5:9: Expectation failed: 1 + 1 == 3
✘ Test envelope(height:setCount:) recorded an issue with 2 arguments height → 70.0, setCount → 3 at SessionStageBranchEnvelopeTests.swift:19:9: Expectation failed
✘ Test failsOnPurpose() failed after 0.001 seconds with 1 issue.
✘ Test run with 1021 tests in 12 suites failed after 2.172 seconds with 3 issues (including 1 known issue)." 1 \
"◇ Test run started.
✘ Test failsOnPurpose() recorded an issue at Issue769FailingProbeTests.swift:5:9: Expectation failed: 1 + 1 == 3
━ Test replanningWhenTheRefetchFails() recorded a known issue at SyncCoordinatorReplanTests.swift:693:9: Expectation failed
✘ Test envelope(height:setCount:) recorded an issue with 2 arguments height → 70.0, setCount → 3 at SessionStageBranchEnvelopeTests.swift:19:9: Expectation failed
✘ Test failsOnPurpose() failed after 0.001 seconds with 1 issue.
✘ Test run with 1021 tests in 12 suites failed after 2.172 seconds with 3 issues (including 1 known issue)."

check "a test that records many issues prints its first three" 1 \
"✘ Test grows(n:) recorded an issue with 1 argument n → 1 at GrowSuite.swift:5:9: Expectation failed: n == 0
✘ Test grows(n:) recorded an issue with 1 argument n → 2 at GrowSuite.swift:5:9: Expectation failed: n == 0
✘ Test grows(n:) recorded an issue with 1 argument n → 3 at GrowSuite.swift:5:9: Expectation failed: n == 0
✘ Test grows(n:) recorded more issues; the log holds every one
✘ Test grows(n:) failed after 0.001 seconds with 5 issues.
✘ Test run with 1 test in 1 suite failed after 0.002 seconds with 5 issues." 1 \
"◇ Test run started.
✘ Test grows(n:) recorded an issue with 1 argument n → 1 at GrowSuite.swift:5:9: Expectation failed: n == 0
✘ Test grows(n:) recorded an issue with 1 argument n → 2 at GrowSuite.swift:5:9: Expectation failed: n == 0
✘ Test grows(n:) recorded an issue with 1 argument n → 3 at GrowSuite.swift:5:9: Expectation failed: n == 0
✘ Test grows(n:) recorded an issue with 1 argument n → 4 at GrowSuite.swift:5:9: Expectation failed: n == 0
✘ Test grows(n:) recorded an issue with 1 argument n → 5 at GrowSuite.swift:5:9: Expectation failed: n == 0
✘ Test grows(n:) failed after 0.001 seconds with 5 issues.
✘ Test run with 1 test in 1 suite failed after 0.002 seconds with 5 issues."

printf '\npassed %s, failed %s\n' "$pass" "$fail"
[ "$fail" -eq 0 ] || exit 1
