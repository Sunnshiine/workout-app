# shellcheck shell=bash
script_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
root=$(mktemp -d) || exit 3
sim=TEST-SIM-TEST-$$
other_sim=TEST-SIM-OTHER-$$
unknown=DEADBEEF-0000-4000-8000-$(printf %012d $$)
trap 'rm -rf "$root" "/tmp/workout-verify-$sim" "/tmp/workout-verify-$other_sim" "/tmp/workout-verify-$unknown"' EXIT
repo=$root/repo
products=$root/home/Library/Developer/Xcode/DerivedData/WorkoutTracker-stub/Build/Products
mkdir -p "$repo/scripts" "$root/bin" "$products"
cp "$script_dir/../test-sim.sh" "$script_dir/../sim-lock.sh" "$script_dir/../test-log-summary.awk" "$script_dir/../compile-cache.sh" \
    "$repo/scripts/"
touch "$products/../../info.plist" "$products/WorkoutTracker_iphonesimulator27.0-arm64.xctestrun"
cat >"$repo/scripts/sim-keyboard.sh" <<'STUB'
#!/bin/sh
echo "$*" >>"$STUB_KEYBOARD_CALLS"
echo "keyboard: stub"
exit "${STUB_KEYBOARD_RC:-0}"
STUB
chmod +x "$repo/scripts/sim-keyboard.sh"
export WORKOUT_MEM_FLOOR=0 WORKOUT_HOST_LOCK_DIR=$root/locks
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
printf '%s\n' "$@" >"$STUB_ARGS"
[ "$1" != build-for-testing ] || printf '%s\n' "$@" >"$STUB_ARGS.build"
while [ $# -gt 0 ]; do
    [ "$1" != -resultBundlePath ] || [ -z "${STUB_SUMMARY:-}" ] || { mkdir -p "$2" && printf '%s\n' "$STUB_SUMMARY" >"$2/summary"; }
    shift
done
cat "$STUB_LOG"
cp "$STUB_OUT" "$STUB_SEEN"
[ -z "${STUB_RELEASE:-}" ] || while [ ! -e "$STUB_RELEASE" ]; do sleep 0.1; done
[ -z "${STUB_SLEEP:-}" ] || sleep "$STUB_SLEEP"
[ -z "${STUB_BACKDATE:-}" ] || python3 -c 'import os, sys, time; t = time.time() - 30 * 60; os.utime(sys.argv[1], (t, t))' "$STUB_BACKDATE"
exit "$STUB_RC"
STUB
cat >"$root/bin/xcrun" <<STUB
#!/bin/sh
if [ "\$1" = xcresulttool ]; then
    [ "\$4 \$5" = "tests --path" ] && { printf '%s' "\${STUB_TESTS:-}"; exit; }
    [ "\$4 \$5" = "summary --path" ] && cat "\$6/summary" 2>/dev/null
    exit
fi
[ "\$1 \$2" != "simctl shutdown" ] || { echo "\$*" >>"$root/shutdowns"; exit 0; }
[ -z "\${STUB_SIMCTL_DOWN:-}" ] || { echo "An error was encountered processing the command (code=405)" >&2; exit 1; }
echo '{"devices":{"com.apple.CoreSimulator.SimRuntime.iOS-27-0":[{"udid":"$sim","state":"Booted","name":"iPhone 17 Pro"},{"udid":"$other_sim","state":"Booted","name":"iPhone 17"}]}}'
STUB
cat >"$root/bin/date" <<'STUB'
#!/bin/sh
[ -n "${STUB_STAMP:-}" ] && [ "$*" = +%Y%m%d-%H%M%S ] && { echo "$STUB_STAMP"; exit; }
exec /bin/date "$@"
STUB
cat >"$root/bin/sysctl" <<'STUB'
#!/bin/sh
[ -e "$STUB_LOAD_READ" ] && echo '{ 2.50 1.25 1.00 }' || echo '{ 1.50 1.25 1.00 }'
touch "$STUB_LOAD_READ"
STUB
chmod +x "$root/bin/plutil" "$root/bin/xcodebuild" "$root/bin/xcrun" "$root/bin/sysctl" "$root/bin/date"
export STUB_ARGS=$root/args STUB_KEYBOARD_CALLS=$root/keyboard STUB_LOAD_READ=$root/load-read
result() { echo "test-sim: suite=$1 passed=- failed=- expected=- exit=$2 load1=1.50/2.50 bundle=-"; }

check() {
    local name=$1 want_status=$2 want_out=$3 want_err=$4 xcodebuild_status=$5 log=$6
    printf '%s\n' "$log" >"$root/xcodebuild.log"
    STUB_LOG=$root/xcodebuild.log STUB_RC=$xcodebuild_status STUB_OUT=$root/out STUB_SEEN=$root/seen HOME=$root/home PATH="$root/bin:$PATH" \
        "$repo/scripts/test-sim.sh" --no-build --sim "$sim" unit >"$root/out" 2>"$root/err"
    local status=$?
    rm -f "$root/load-read"
    local out err last
    out=$(grep -v -e '^log: ' -e '^bundle: ' -e '^test-sim: ' "$root/out")
    err=$(cat "$root/err")
    last=$(tail -1 "$root/out")
    if [ "$status" = "$want_status" ] && [ "$out" = "$want_out" ] && [ "$err" = "$want_err" ] \
        && [ "$last" = "$(result unit "$want_status")" ]; then
        ok "$name"
    else
        bad "$name: exit $status (want $want_status)"
        printf '    stdout:\n%s\n    last line:\n%s\n    stderr:\n%s\n' "$out" "$last" "$err"
    fi
}
