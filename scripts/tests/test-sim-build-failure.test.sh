#!/usr/bin/env bash
# A failed build-for-testing prints its log path and exits 65, whatever the log holds (#729).
set -uo pipefail

script_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
root=$(mktemp -d) || exit 3
sim=TEST-SIM-BUILD-$$
trap 'rm -rf "$root" "/tmp/workout-verify-$sim"' EXIT
repo=$root/repo
mkdir -p "$repo/scripts" "$root/bin" "$root/home"
cp "$script_dir/../test-sim.sh" "$script_dir/../sim-lock.sh" "$script_dir/../test-log-summary.awk" "$repo/scripts/"
export WORKOUT_MEM_FLOOR=0 WORKOUT_HOST_LOCK_DIR=$root/locks
pass=0
fail=0

ok()  { pass=$((pass + 1)); printf '  ok   %s\n' "$1"; }
bad() { fail=$((fail + 1)); printf '  FAIL %s\n' "$1"; }

cat >"$root/bin/xcodebuild" <<'STUB'
#!/bin/sh
cat "$STUB_LOG"
exit 1
STUB
cat >"$root/bin/xcrun" <<STUB
#!/bin/sh
[ "\$1" != xcresulttool ] || exit 0
[ "\$1 \$2" != "simctl shutdown" ] || exit 0
echo '{"devices":{"com.apple.CoreSimulator.SimRuntime.iOS-27-0":[{"udid":"$sim","state":"Booted","name":"iPhone 17 Pro"}]}}'
STUB
cat >"$root/bin/sysctl" <<'STUB'
#!/bin/sh
echo '{ 1.50 1.25 1.00 }'
STUB
chmod +x "$root/bin/xcodebuild" "$root/bin/xcrun" "$root/bin/sysctl"

check() {
    local name=$1 log=$2 want_lines=$3
    printf '%s' "$log" >"$root/xcodebuild.log"
    rm -rf "$repo/.build"
    STUB_LOG=$root/xcodebuild.log HOME=$root/home PATH="$root/bin:$PATH" \
        "$repo/scripts/test-sim.sh" --sim "$sim" unit >"$root/out" 2>"$root/err"
    local status=$? build_log err last
    build_log=$(ls "$repo"/.build/test-sim/*-build.log 2>/dev/null)
    err=$(cat "$root/err")
    last=$(tail -1 "$root/out" | sed 's/ load1=[^ ]*//')
    local want_err="${want_lines:+$want_lines
}build log: $build_log"
    if [ "$status" = 65 ] && [ -n "$build_log" ] && [ "$err" = "$want_err" ] \
        && [ "$last" = "test-sim: suite=unit passed=- failed=- expected=- exit=65 bundle=-" ]; then
        ok "$name"
    else
        bad "$name: exit $status (want 65)"
        printf '    stderr:\n%s\n    want stderr:\n%s\n    last line:\n%s\n' "$err" "$want_err" "$last"
    fi
}

check "a build that fails with no output prints its log path and exits 65" "" ""
check "a build that fails with no error: or BUILD FAILED line prints its log path and exits 65" \
"Command line invocation:
    xcodebuild build-for-testing
Killed: 9
" ""
check "a build that fails with error lines prints them, then its log path, and exits 65" \
"Compiling
App/Foo.swift:1:1: error: cannot find 'bar' in scope
** BUILD FAILED **
" "App/Foo.swift:1:1: error: cannot find 'bar' in scope
** BUILD FAILED **"

many=$(for n in $(seq 20000); do echo "App/Foo$n.swift:1:1: error: cannot find 'bar' in scope"; done)
check "a build with more error lines than it prints stops at 20, then prints its log path, and exits 65" \
"$many
** BUILD FAILED **
" "$(printf '%s\n' "$many" | sed -n 1,20p)"

printf '\npassed %s, failed %s\n' "$pass" "$fail"
[ "$fail" -eq 0 ] || exit 1
