#!/bin/bash
# verify.sh stop against a stub xcrun, for a recorded pid the kernel gave to another process (#728).
set -uo pipefail

verify=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)/.agents/skills/verify/verify.sh
root=$(mktemp -d) || exit 3
sim=VERIFY-STOP-TEST-$$
state=/tmp/workout-verify-$sim
procs=()
cleanup() {
    [ ${#procs[@]} -eq 0 ] || { kill "${procs[@]}"; wait "${procs[@]}"; } 2>/dev/null
    rm -rf "$root" "$state"
}
trap cleanup EXIT
mkdir -p "$root/bin" "$root/evidence"
pass=0
fail=0

ok()  { pass=$((pass + 1)); printf '  ok   %s\n' "$1"; }
bad() { fail=$((fail + 1)); printf '  FAIL %s\n' "$1"; }
expect() { if [ "$2" = "$3" ]; then ok "$1"; else bad "$1"; printf '    got:  %s\n    want: %s\n    stderr: %s\n' "$2" "$3" "$(cat "$root/err")"; fi; }

# simctl terminate exits 3 when the app is not running, as the real one does.
cat >"$root/bin/xcrun" <<STUB
#!/bin/sh
echo "\$*" >> "$root/calls"
case "\$*" in
  "simctl terminate "*)
    [ -n "\${STUB_APP_RUNNING:-}" ] && exit 0
    echo "An error was encountered processing the command (domain=com.apple.CoreSimulator.SimError, code=3):" >&2
    echo "found nothing to terminate" >&2
    exit 3 ;;
esac
STUB
chmod +x "$root/bin/xcrun"

record() {
    rm -rf "$state" "$root/calls"
    mkdir -p "$state"
    echo "$1" >"$state/pid"
    echo "-UITEST_FIXTURE -UITEST_SESSION -UITEST_DISABLE_LIVE_ACTIVITIES" >"$state/args"
    echo owner-run >"$state/run"
}
stop() {
    SIM=$sim VERIFY_EVIDENCE=$root/evidence PATH="$root/bin:$PATH" "$verify" stop >"$root/out" 2>"$root/err"
    status=$?
}
calls() { cat "$root/calls" 2>/dev/null | tr '\n' ' ' | sed 's/ $//'; }
left() { ls "$state" | tr '\n' ' ' | sed 's/ $//'; }

sleep 120 &
reused=$!
procs+=("$reused")
python3 -c 'import time; time.sleep(120)' -UITEST_FIXTURE &
app=$!
procs+=("$app")

record "$reused"
VERIFY_RUN=owner-run stop
expect "a recorded pid that now names a process that is not a fixture launch is forgotten, not terminated" \
    "$status | $(cat "$root/out") | $(calls) | $(left)" \
    "0 |  |  | run"

record "$reused"
VERIFY_RUN=another-run stop
expect "another run's recorded pid, reused by a non-fixture process, is not that run's app, so stop does not refuse" \
    "$status | $(calls) | $(left)" \
    "0 |  | run"

record "$reused"
stop
expect "an unnamed stop clears the same stale pid file" "$status | $(calls) | $(left)" "0 |  | run"

record "$app"
STUB_APP_RUNNING=1 VERIFY_RUN=owner-run stop
expect "a recorded pid that is a live fixture launch is still terminated" \
    "$status | $(cat "$root/out") | $(calls) | $(left)" \
    "0 | terminated pid $app | simctl terminate $sim com.sunnypatel.WorkoutTracker | run"

record "$app"
VERIFY_RUN=another-run stop
expect "a live fixture launch another run owns is still refused" "$status | $(calls) | $(left)" "75 |  | args pid run"

echo "$pass passed, $fail failed"
[ "$fail" -eq 0 ]
