#!/usr/bin/env bash
set -uo pipefail

# shellcheck source=scripts/tests/test-sim-harness.sh
. "$(dirname "${BASH_SOURCE[0]}")/test-sim-harness.sh"

export HOME=$root/home STUB_LOG=$root/xcodebuild.log STUB_OUT=$root/out STUB_SEEN=$root/seen STUB_RC=0
printf '%s\n' "✔ Test run with 1 test in 1 suite passed after 1.000 seconds." "** TEST EXECUTE SUCCEEDED **" >"$root/xcodebuild.log"
install="gh api -H 'Accept: application/vnd.github.raw' repos/Sunnshiine/hostgate/contents/install | sh"
finding="fail sandbox-report: 3 of 3 sandboxed, denied mach-lookups did not return within 5 s, so sandbox violation reporting is stuck
  remedy: Xcode builds that run a build plug-in or tool Apple did not sign will hang (SwiftLint's plug-in is one). Needs an administrator: restart sandboxd when no simulator lease is held, or reboot. Until then do not start such builds.
  needs the operator"
expect() { if [ "$2" = "$3" ]; then ok "$1"; else bad "$1"; printf '    got:\n%s\n    want:\n%s\n    stderr:\n%s\n' "$2" "$3" "$(cat "$root/err")"; fi; }
test_sim() {
    rm -f "$root/seen" "$root/load-read" "$root/args" "$root/hostgate-calls" "$root/hostgate.log"
    PATH="${path:-$root/bin:$PATH}" "$repo/scripts/test-sim.sh" "$@" >"$root/out" 2>"$root/err"
}
calls() { tr '\n' ';' 2>/dev/null <"$root/hostgate-calls"; }
built() {
    local test_log
    test_log=$(sed -n 's/^log: //p' "$root/out")
    if [ -n "$test_log" ] && [ -e "${test_log%-test.log}-build.log" ]; then echo built; else echo no-build; fi
}
leases_by() { grep -c "^lease .* by $1," "$FAKE_SIMLOCK_STATE/log"; }

FAKE_HOSTGATE_CHECK_RC=1 FAKE_HOSTGATE_CHECK_OUT=$finding FAKE_SIMLOCK_WHO=builder test_sim unit
expect "a failing sandbox-report finding refuses the build with 75, prints the finding and its remedy, and builds and leases nothing" \
    "$? $(cat "$root/err") | $(built) $(leases_by builder) | $(calls)" \
    "75 $finding
test-sim.sh will not start the build: the SwiftLint build plug-in would hang until the operator clears the finding above, by restarting sandboxd while no simulator lease is held, or by rebooting. Until then --no-build runs the tests on the app already built. | no-build 0 | check --only sandbox-report;"

FAKE_HOSTGATE_CHECK_SLEEP=7 FAKE_HOSTGATE_CHECK_RC=1 FAKE_HOSTGATE_CHECK_OUT=$finding test_sim --sim "$sim" unit
expect "a check that reports the wedge after 7 s, as hostgate does, still refuses within the default bound" \
    "$? $(head -1 "$root/err") | $(built)" "75 $(head -1 <<< "$finding") | no-build"

FAKE_HOSTGATE_CHECK_SLEEP=5 WORKOUT_SANDBOX_CHECK_SECONDS=1 test_sim --sim "$sim" unit
expect "a check that outlasts WORKOUT_SANDBOX_CHECK_SECONDS builds anyway after one WARNING line" "$? $(cat "$root/err") | $(built)" \
    "0 WARNING: hostgate check --only sandbox-report did not finish within 1 s (WORKOUT_SANDBOX_CHECK_SECONDS), so nothing checked sandbox reporting; building anyway | built"

FAKE_HOSTGATE_BROKEN=1 test_sim --sim "$sim" unit
expect "a broken hostgate that exits 1 with no finding builds anyway, once warned by the check and once by the build's slot" \
    "$? $(cat "$root/err") | $(built)" \
    "0 WARNING: hostgate check --only sandbox-report exited 1, so nothing checked sandbox reporting; building anyway. It printed: Traceback (most recent call last): ImportError: hostgate is broken
Traceback (most recent call last): ImportError: hostgate is broken
hostgate run failed (exit 1) before it started the build, so this build takes no host-wide slot and may stall every other agent; reinstall it: $install | built"

test_sim --sim "$sim" unit
expect "a healthy check builds, saying nothing of it" "$? $(cat "$root/err") | $(built) | $(calls)" \
    "0  | built | check --only sandbox-report;"

FAKE_HOSTGATE_CHECK_RC=64 FAKE_HOSTGATE_CHECK_OUT="hostgate check: error: unrecognized arguments: --only" test_sim --sim "$sim" unit
expect "a check that exits otherwise builds anyway after one WARNING line" "$? $(cat "$root/err") | $(built)" \
    "0 WARNING: hostgate check --only sandbox-report exited 64, so nothing checked sandbox reporting; building anyway. It printed: hostgate check: error: unrecognized arguments: --only | built"

FAKE_HOSTGATE_VERSION=0.9.4 test_sim --sim "$sim" unit
expect "a hostgate older than the pin is named once, by the build's slot, and the check still runs" "$? $(cat "$root/err") | $(calls)" \
    "0 hostgate 0.9.4 is older than the $(cat "$repo/scripts/hostgate-version") this repo pins (scripts/hostgate-version); update it: $install | check --only sandbox-report;"

FAKE_HOSTGATE_VERSION=1.10.0 test_sim --sim "$sim" unit
expect "a hostgate newer than the pin says nothing of its version" "$? $(cat "$root/err")" "0 "

mkdir -p "$root/no-hostgate"
cp "$root/bin/"* "$root/no-hostgate/"
rm "$root/no-hostgate/hostgate"
path="$root/no-hostgate:$(printf %s "$PATH" | tr ':' '\n' | while IFS= read -r dir; do [ -x "$dir/hostgate" ] || printf '%s:' "$dir"; done)" test_sim --sim "$sim" unit
expect "without hostgate it builds anyway after one line naming the install command" "$? $(cat "$root/err") | $(built)" \
    "0 hostgate is not on PATH, so this build takes no host-wide slot and may stall every other agent; install it: $install | built"

FAKE_HOSTGATE_CHECK_RC=1 FAKE_HOSTGATE_CHECK_OUT=$finding test_sim --no-build --sim "$sim" unit
expect "--no-build never calls hostgate" "$? $(calls)" "0 "

printf '\npassed %s, failed %s\n' "$pass" "$fail"
[ "$fail" -eq 0 ] || exit 1
