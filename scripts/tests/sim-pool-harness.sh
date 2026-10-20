# shellcheck shell=bash

scripts=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
root=$(mktemp -d) || exit 3
root=$(cd "$root" && pwd -P)
P=SIMPOOL$$
holder=
cleanup() {
    [ -z "$holder" ] || kill "$holder" 2>/dev/null
    rm -rf "$root" /tmp/workout-verify-"$P"-*
}
trap cleanup EXIT
mkdir -p "$root/bin" "$root/home"
cp "$scripts/tests/fake-xcrun" "$root/bin/xcrun"
cat >"$root/bin/sysctl" <<'STUB'
#!/bin/bash
[ "$2" = kern.memorystatus_level ] && echo "${STUB_MEM_LEVEL:-80}" || echo "{ ${STUB_LOAD:-1.00} 1.00 1.00 }"
STUB
cat >"$root/bin/pgrep" <<'STUB'
#!/bin/bash
[ "$1" = -f ] || exec /usr/bin/pgrep "$@"
[ -f "${STUB_APPS:-}" ] || exit 1
found=1
while read -r pid cmd; do
    printf '%s\n' "$cmd" | grep -qE -- "$2" && { echo "$pid"; found=0; }
done <"$STUB_APPS"
exit $found
STUB
chmod +x "$root/bin/sysctl" "$root/bin/pgrep"
export PATH="$root/bin:$PATH" HOME="$root/home" WORKOUT_HOST_LOCK_DIR="$root/locks"
unset WORKOUT_SIM_CAP WORKOUT_MEM_FLOOR WORKOUT_ADMIT_WAIT WORKOUT_BUILD_SLOTS WORKOUT_LEASE_MINUTES WORKOUT_IDLE_MINUTES STUB_APPS
export FAKE_SIM_PREFIX=$P FAKE_SIM_STORE="$root/store.json" FAKE_SIM_CALLS="$root/calls"
runtime=com.apple.CoreSimulator.SimRuntime.iOS-27-0
build_calls="create workout-template-v1-building com.apple.CoreSimulator.SimDeviceType.iPhone-17-Pro $runtime
boot $P-1
bootstatus $P-1 -b
bootstatus $P-1 -b
spawn $P-1 defaults read com.apple.keyboard.preferences AutomaticMinimizationEnabled
spawn $P-1 defaults write com.apple.keyboard.preferences AutomaticMinimizationEnabled -bool false
spawn $P-1 defaults read com.apple.keyboard.preferences AutomaticMinimizationEnabled
shutdown $P-1
rename $P-1 workout-template-v1"
pass=0
fail=0

ok()  { pass=$((pass + 1)); printf '  ok   %s\n' "$1"; }
bad() { fail=$((fail + 1)); printf '  FAIL %s\n' "$1"; }

fresh() { rm -f "$root/store.json" "$root/calls"; }
seed() {
    xcrun simctl create "$1" 'iPhone 17 Pro' "$runtime" >/dev/null
    [ "${2:-}" != Booted ] || xcrun simctl boot "$(xcrun simctl list devices -j | python3 -c '
import json, sys
print([d["udid"] for ds in json.load(sys.stdin)["devices"].values() for d in ds][-1])')"
    rm -f "$root/calls"
}
pool() {
    rm -f "$root/calls"
    "$scripts/sim-pool.sh" "$@" >"$root/out" 2>"$root/err"
    status=$?
}
calls() { cat "$root/calls" 2>/dev/null; }
refusal() { sed 's/^gave up after [0-9]* s/gave up after N s/' "$root/err"; }
listing() { "$scripts/sim-pool.sh" list; }
expect() {
    if [ "$2" = "$3" ]; then
        ok "$1"
    else
        bad "$1"
        printf '    got:\n%s\n    want:\n%s\n    stderr:\n%s\n' "$2" "$3" "$(cat "$root/err")"
    fi
}
hold() {
    mkdir -p "$(dirname "$1")"
    python3 -c 'import fcntl, sys, time
f = open(sys.argv[1], "a")
fcntl.flock(f, fcntl.LOCK_EX)
open(sys.argv[1], "w").write(sys.argv[2] + "\n")
open(sys.argv[3], "w").close()
time.sleep(120)' "$1" "$2" "$root/held" &
    holder=$!
    while [ ! -f "$root/held" ]; do sleep 0.05; done
    rm -f "$root/held"
}
release() { kill "$holder"; wait "$holder" 2>/dev/null; holder=; }
