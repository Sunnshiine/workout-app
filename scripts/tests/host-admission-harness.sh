# shellcheck shell=bash
script_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
root=$(mktemp -d) || exit 3
sim=HOST-ADMISSION-TEST-$$
sim2=$sim-2
state=/tmp/workout-verify-$sim
apps=()
cleanup() {
    touch "$root/release"
    [ ${#apps[@]} -eq 0 ] || { kill "${apps[@]}"; wait "${apps[@]}"; } 2>/dev/null
    rm -rf "$root" "$state" "/tmp/workout-verify-$sim2"
}
trap cleanup EXIT
repo=$root/repo
products=$root/home/Library/Developer/Xcode/DerivedData/WorkoutTracker-stub/Build/Products
mkdir -p "$repo/scripts" "$repo/.agents/skills/verify" "$root/bin" "$products"
cp "$script_dir/../test-sim.sh" "$script_dir/../sim-lock.sh" "$script_dir/../build-slot.sh" \
    "$script_dir/../test-log-summary.awk" "$script_dir/../test-log-summary.sh" "$repo/scripts/"
cp "$script_dir/../../.agents/skills/verify/"verify.sh "$script_dir/../../.agents/skills/verify/"verify-*.sh "$repo/.agents/skills/verify/"
touch "$products/../../info.plist" "$products/WorkoutTracker_iphonesimulator27.0-arm64.xctestrun"
mkdir -p "$products/Debug-iphonesimulator/WorkoutTracker.app" "$repo/.build/verify/node_modules/xcodebuildmcp/bundled"
printf '#!/bin/sh\n' > "$repo/.build/verify/node_modules/xcodebuildmcp/bundled/axe"
chmod +x "$repo/.build/verify/node_modules/xcodebuildmcp/bundled/axe"
git -C "$repo" init -q && git -C "$repo" add -A && git -C "$repo" -c user.name=test -c user.email=test@example.com commit -qm test
pass=0
fail=0

ok()  { pass=$((pass + 1)); printf '  ok   %s\n' "$1"; }
bad() { fail=$((fail + 1)); printf '  FAIL %s\n' "$1"; }
refusal() { tail -1 "$root/err" | sed 's/^gave up after [0-9]* s/gave up after N s/'; }
expect() { if [ "$2" = "$3" ]; then ok "$1"; else bad "$1"; printf '    got:  %s\n    want: %s\n' "$2" "$3"; fi; }

cat >"$root/bin/plutil" <<STUB
#!/bin/sh
echo "$repo/WorkoutTracker.xcodeproj"
STUB
cat >"$root/bin/npm" <<'STUB'
#!/bin/sh
exit 1
STUB
cat >"$root/bin/xcrun" <<STUB
#!/bin/sh
[ "\$1" != xcresulttool ] || exit 0
if [ "\$*" != "simctl list devices available -j" ]; then
    echo "\$*" >> "$root/xcrun-calls"
    case "\$*" in
      "simctl boot "*)
        if [ -n "\${STUB_BOOT_HOLD:-}" ]; then
            touch "$root/boot-holding"
            i=0
            while [ ! -f "$root/release" ] && [ \$i -lt 300 ]; do sleep 0.1; i=\$((i + 1)); done
        fi
        [ -z "\${STUB_BOOT_FAILS:-}" ] || { case \$STUB_BOOT_FAILS in raced) echo "\$3" >> "$root/booted" ;;
            booting) echo "\$3" >> "$root/booting" ;; esac
            echo "Unable to boot device in current state: Booted" >&2; exit 149; }
        echo "\$3" >> "$root/booted" ;;
      "simctl list devices booted") sed 's/.*/    iPhone 17 Pro (&) (Booted)/' "$root/booted" 2>/dev/null ;;
      "simctl launch "*) echo "com.sunnypatel.WorkoutTracker: 999999" ;;
      "simctl get_app_container "*) echo "$products/Debug-iphonesimulator/WorkoutTracker.app" ;;
    esac
    exit 0
fi
[ -z "\${STUB_LIST_WARNING:-}" ] || echo "objc[4242]: Class SimDeviceSet is implemented in both CoreSimulator and CoreSimulatorUtilities" >&2
echo call >> "$root/list-calls"
[ "\$(wc -l < "$root/list-calls")" -lt "\${STUB_LIST_GARBAGE_FROM_CALL:-1000}" ] || { echo "not a device list"; exit 0; }
if [ "\$(wc -l < "$root/list-calls")" -eq "\${STUB_SLOW_LIST_CALL:-0}" ]; then touch "$root/listing-slowly"; sleep 3; fi
if [ "\$(wc -l < "$root/list-calls")" -eq "\${STUB_PROBE_ON_LIST_CALL:-0}" ]; then
    python3 -c 'import fcntl, sys, time
slot = open(sys.argv[1], "a")
fcntl.flock(slot, fcntl.LOCK_SH)
open(sys.argv[2], "w").close()
time.sleep(0.12)' "$root/locks/build-1" "$root/probing" 7>&- 8>&- 9>&- &
    while [ ! -f "$root/probing" ]; do sleep 0.01; done
fi
if [ "\$(wc -l < "$root/list-calls")" -gt "\${STUB_LIST_OK_CALLS:-1000}" ]; then
    echo "An error was encountered processing the command (domain=com.apple.CoreSimulator.SimError, code=405)" >&2
    exit 1
fi
python3 -c 'import json, os, sys
others = [{"udid": "OTHER-%d" % i, "state": "Booted", "name": "iPad Pro"} for i in range(int(sys.argv[1]))]
shut = sys.argv[2].split()
booted = open(sys.argv[3]).read().split() if os.path.exists(sys.argv[3]) else []
booting = open(sys.argv[4]).read().split() if os.path.exists(sys.argv[4]) else []
ours = ["$sim"] + [u for u in shut if u != "$sim"]
stopping = os.environ.get("STUB_SHUTTING_DOWN", "").split()
state = lambda u: "Shutting Down" if u in stopping else "Booting" if u in booting else "Shutdown" if u in shut and u not in booted else "Booted"
print(json.dumps({"devices": {"iOS-27-0": others + [
    {"udid": u, "state": state(u), "name": "iPhone 17 Pro"} for u in ours]}}))' \
    "\${STUB_BOOTED_OTHERS:-0}" "\${STUB_SHUTDOWN:-}" "$root/booted" "$root/booting"
STUB
cat >"$root/bin/sysctl" <<STUB
#!/bin/sh
[ -z "\${STUB_SYSCTL_FAILS:-}" ] || { echo "sysctl: unknown oid '\$2'" >&2; exit 1; }
if [ "\$2" = kern.memorystatus_level ]; then
    echo call >> "$root/mem-calls"
    if [ "\$(wc -l < "$root/mem-calls")" -gt "\${STUB_LOW_MEM_CALLS:-1000}" ]; then echo 80; else echo "\${STUB_MEM_LEVEL:-80}"; fi
    exit 0
fi
echo call >> "$root/sysctl-calls"
if [ "\$(wc -l < "$root/sysctl-calls")" -gt "\${STUB_BUSY_CALLS:-1000}" ]; then echo "{ 1.00 1.00 1.00 }"; else echo "{ \${STUB_LOAD:-1.00} 1.00 1.00 }"; fi
STUB
cat >"$root/bin/xcodebuild" <<STUB
#!/bin/sh
echo "\$1" >> "$root/builds"
if [ -n "\${STUB_HOLD:-}" ]; then
    touch "$root/holding"
    i=0
    while [ ! -f "$root/release" ] && [ \$i -lt 300 ]; do sleep 0.1; i=\$((i + 1)); done
fi
echo "** BUILD FAILED **"
exit 65
STUB
printf '#!/bin/sh\nexit 1\n' >"$root/bin/gh"
chmod +x "$root/bin/"*
export HOME=$root/home PATH="$root/bin:$PATH" WORKOUT_HOST_LOCK_DIR=$root/locks
# shellcheck disable=SC2046
unset VERIFY_RUN SIM WORKOUT_LOAD_LIMIT $(sed -n 's/^host_knob \([A-Z_]*\) .*/\1/p' "$repo/scripts/sim-lock.sh")

reset() {
    rm -rf "$state" "/tmp/workout-verify-$sim2" "$root/builds" "$root/sysctl-calls" "$root/mem-calls" "$root/xcrun-calls" "$root/list-calls" \
        "$root/booted" "$root/booting" "$root/holding" "$root/boot-holding" "$root/release" "$root/listing-slowly" "$root/probing" \
        "$repo/.claude/work/evidence"
}
leftovers() {
    local file
    for file in "$root/locks"/*; do
        case ${file##*/} in admit|build-[0-9]*) ;; *) printf '%s ' "${file##*/}" ;; esac
    done
}
builds() { cat "$root/builds" 2>/dev/null | tr '\n' ' ' | sed 's/ $//'; }
test_sim() { "$repo/scripts/test-sim.sh" "$@" --sim "$sim" unit >"$root/out" 2>"$root/err"; }
verify() { SIM=$sim "$repo/.agents/skills/verify/verify.sh" "$@"; }
