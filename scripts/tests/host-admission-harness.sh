# shellcheck shell=bash
# CI sets GITHUB_ACTIONS, under which test-log-summary.sh adds ::error lines these checks do not expect.
unset GITHUB_ACTIONS
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
find "$script_dir/.." -maxdepth 1 -type f -exec cp {} "$repo/scripts/" \;
find "$script_dir/../../.agents/skills/verify" -maxdepth 1 -type f -exec cp {} "$repo/.agents/skills/verify/" \;
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
# bootstatus, which every claim runs through simlock simctl, goes unrecorded.
cat >"$root/bin/xcrun" <<STUB
#!/bin/sh
[ "\$1" != xcresulttool ] || exit 0
[ "\$2" != bootstatus ] || exit 0
echo "\$*" >> "$root/xcrun-calls"
case "\$*" in
  "simctl launch "*) echo "com.sunnypatel.WorkoutTracker: 999999" ;;
  "simctl get_app_container "*) echo "$products/Debug-iphonesimulator/WorkoutTracker.app" ;;
esac
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
cat >"$root/bin/df" <<STUB
#!/bin/sh
echo call >> "$root/df-calls"
free=\${STUB_DISK_FREE_MB:-100000}
[ -z "\${STUB_LOW_DISK_PATH:-}" ] || [ "\$2" = "\$STUB_LOW_DISK_PATH" ] || free=100000
[ "\$(wc -l < "$root/df-calls")" -le "\${STUB_LOW_DISK_CALLS:-1000}" ] || free=100000
echo "Filesystem 1024-blocks Used Available Capacity Mounted on"
echo "/dev/stub 200000000 100000000 \$((free * 1024)) 50% /"
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
cp "$script_dir/fake-simlock" "$root/bin/simlock"
chmod +x "$root/bin/"*
export HOME=$root/home PATH="$root/bin:$PATH" WORKOUT_HOST_LOCK_DIR=$root/locks
export FAKE_SIMLOCK_STATE=$root/simlock FAKE_SIMLOCK_DEVICES="$sim $sim2"
# shellcheck disable=SC2046
unset VERIFY_RUN SIM WORKOUT_LOAD_LIMIT FAKE_SIMLOCK_WHO $(sed -n 's/^host_knob \([A-Z_]*\) .*/\1/p' "$repo/scripts/sim-lock.sh")
# The caller holds a lease on $sim, and another agent, neighbour, one on $sim2.
for who in agent-test neighbour; do
    FAKE_SIMLOCK_WHO=$who simlock lease --platform ios --device 'iPhone 17 Pro' --os 27.0 --detach --ttl 60m >/dev/null
done

reset() {
    rm -rf "$state" "/tmp/workout-verify-$sim2" "$root/builds" "$root/sysctl-calls" "$root/mem-calls" "$root/df-calls" "$root/xcrun-calls" \
        "$root/holding" "$root/release" "$repo/.claude/work/evidence"
}
builds() { cat "$root/builds" 2>/dev/null | tr '\n' ' ' | sed 's/ $//'; }
test_sim() { "$repo/scripts/test-sim.sh" "$@" --sim "$sim" unit >"$root/out" 2>"$root/err"; }
# A run of the other agent on its own simulator, holding the build slot it takes until release.
neighbour_build() {
    FAKE_SIMLOCK_WHO=neighbour STUB_HOLD=1 "$repo/scripts/test-sim.sh" --sim "$sim2" unit >/dev/null 2>&1 &
    # shellcheck disable=SC2034 # the tests read first
    first=$!
    for _ in $(seq 1 100); do [ -f "$root/holding" ] && break; sleep 0.1; done
}
verify() { SIM=$sim "$repo/.agents/skills/verify/verify.sh" "$@"; }
