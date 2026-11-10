#!/usr/bin/env bash
set -uo pipefail

# shellcheck source=scripts/tests/test-sim-harness.sh
. "$(dirname "${BASH_SOURCE[0]}")/test-sim-harness.sh"

# The harness's leases hold $sim and $other_sim, so a lease this identity takes gets $spare_sim.
export FAKE_SIMLOCK_WHO=runner
expect() { if [ "$2" = "$3" ]; then ok "$1"; else bad "$1"; printf '    got:\n%s\n    want:\n%s\n    stderr:\n%s\n' "$2" "$3" "$(cat "$root/err")"; fi; }
passing="✔ Test run with 1 test in 1 suite passed after 1.000 seconds.
** TEST EXECUTE SUCCEEDED **"
printf '%s\n' "$passing" >"$root/xcodebuild.log"
export STUB_LOG=$root/xcodebuild.log STUB_OUT=$root/out STUB_SEEN=$root/seen HOME=$root/home TMPDIR=$root/tmp
mkdir -p "$TMPDIR"
leftovers() { find "$TMPDIR" -maxdepth 1 -name 'workout-lease.*' | wc -l | tr -d ' '; }
test_sim() {
    rm -f "$root/seen" "$root/release" "$root/load-read"
    STUB_RC=${rc:-0} PATH="${path:-$root/bin:$PATH}" "$repo/scripts/test-sim.sh" --no-build "$@" unit >"$root/out" 2>"$root/err"
}
start() {
    rm -f "$root/seen" "$root/release" "$root/load-read"
    STUB_RC=0 STUB_RELEASE=$root/release PATH="$root/bin:$PATH" "$@" "$repo/scripts/test-sim.sh" --no-build unit >"$root/out" 2>"$root/err" &
    pid=$!
    for _ in $(seq 100); do [ -e "$root/seen" ] && break; sleep 0.05; done
}
held() { simlock list --leases | python3 -c 'import json, os, sys
print(" ".join(l["deviceId"][4:] for l in json.load(sys.stdin) if l["requesterId"] == os.environ["FAKE_SIMLOCK_WHO"]))'; }
released() { grep '^release' "$FAKE_SIMLOCK_STATE/log" | tail -1 | sed 's/lse_[0-9]*/lse_N/'; }
destination() { grep -m1 '^platform=' "$STUB_ARGS"; }
PATH="$root/bin:$PATH"

test_sim
expect "with no --sim it leases a simulator from Simlock, runs on it, and releases it when the run ends" \
    "$? $(destination) | $(sed 's/lse_[0-9]*/lse_N/' "$root/err") | $(released) | $(held)" \
    "0 platform=iOS Simulator,id=$spare_sim | leasing an iPhone 17 Pro simulator on iOS 27.0 from Simlock
simulator $spare_sim (Simlock lease lse_N) | release lse_N: stopped by SIGTERM | "
expect "and leaves no scratch dir behind" "$(leftovers)" "0"

printf '%s\n' "✘ Test run with 1 test in 1 suite failed after 1.000 seconds with 1 issue." "** TEST EXECUTE FAILED **" >"$root/xcodebuild.log"
rc=65 test_sim
expect "a failing run releases its lease too" "$? $(released) | $(held)" "65 release lse_N: stopped by SIGTERM | "
printf '%s\n' "$passing" >"$root/xcodebuild.log"

start
kill -TERM "$pid"; touch "$root/release"; wait "$pid"
expect "a run stopped with SIGTERM releases its lease" "$? $(released) | $(held)" "143 release lse_N: stopped by SIGTERM | "

start python3 -c 'import os, signal, sys; signal.signal(signal.SIGINT, signal.SIG_DFL); os.execvp(sys.argv[1], sys.argv[1:])'
kill -INT "$pid"; touch "$root/release"; wait "$pid"
expect "a run stopped with SIGINT releases its lease" "$? $(released) | $(held)" "130 release lse_N: stopped by SIGTERM | "

start
kill -KILL "$pid"; wait "$pid" 2>/dev/null; touch "$root/release"
for _ in $(seq 100); do [ -z "$(held)" ] && break; sleep 0.05; done
expect "a run killed with SIGKILL loses its lease, because the lease is bound to its pid" \
    "$(released) | $(held)" "release lse_N: bound pid $pid exited | "
sleep 0.6

simlock lease --platform ios --device 'iPhone 17 Pro' --os 27.0 --detach --ttl 60m >/dev/null
test_sim
expect "with a lease already held and no --sim it exits 75, names that lease's simulator, and keeps the lease" \
    "$? $(tail -1 "$root/err" | sed 's/lse_[0-9]*/lse_N/') | $(held) $([ -e "$root/seen" ] || echo no-xcodebuild)" \
    "75 your Simlock identity already holds a lease (simulator $spare_sim, lease lse_N); pass that simulator with --sim or SIM=, or simlock release its lease first | $spare_sim no-xcodebuild"

test_sim --sim "$(echo "$spare_sim" | tr '[:upper:]' '[:lower:]')"
expect "--sim naming your own lease runs on it and leaves the lease held" \
    "$? $(destination) | $(cat "$root/err") | $(held)" "0 platform=iOS Simulator,id=$spare_sim |  | $spare_sim"
SIM=$spare_sim test_sim
expect "SIM naming your own lease does the same" "$? $(held)" "0 $spare_sim"

test_sim --sim "$other_sim"
expect "--sim naming another agent's lease exits 2 before xcodebuild" "$? $(cat "$root/err") $([ -e "$root/seen" ] || echo no-xcodebuild)" \
    "2 $other_sim is not the simulator of a Simlock lease you hold (yours: $spare_sim); lease one first, see .agents/skills/simlock/SKILL.md no-xcodebuild"
simlock release "$(simlock list --leases | python3 -c 'import json, sys
print(next(l["id"] for l in json.load(sys.stdin) if l["requesterId"] == "runner"))')" >/dev/null
test_sim --sim "$spare_sim"
expect "--sim when you hold no lease exits 2" "$? $(cat "$root/err")" \
    "2 $spare_sim is not the simulator of a Simlock lease you hold (yours: none); lease one first, see .agents/skills/simlock/SKILL.md"

# The SIGKILLed run above had no chance to clean up.
rm -rf "$TMPDIR"/workout-lease.*
FAKE_SIMLOCK_REFUSE=10 test_sim
expect "Simlock's queue timing out exits 75" "$? $(tail -1 "$root/err")" \
    "75 Simlock had no free iPhone 17 Pro simulator within WORKOUT_ADMIT_WAIT (540 s); the host is full, so retry later"
expect "a refused lease leaves no scratch dir behind either" "$(leftovers)" "0"
FAKE_SIMLOCK_DEVICES="$sim $other_sim" WORKOUT_ADMIT_WAIT=0 test_sim
expect "with WORKOUT_ADMIT_WAIT=0 and no free simulator it does not queue, and exits 75" "$? $(tail -1 "$root/err") | $(tail -1 "$FAKE_SIMLOCK_STATE/log")" \
    "75 Simlock had no free iPhone 17 Pro simulator within WORKOUT_ADMIT_WAIT (0 s); the host is full, so retry later | refused runner (11): no free device"

STUB_TOUCH=$root/revoke FAKE_SIMLOCK_REVOKE=$root/revoke test_sim
expect "a lease Simlock takes back mid-run exits 69" "$? $(tail -1 "$root/err") | $(released)" \
    "69 Simlock took the lease back, so the simulator is gone; rerun to lease another | release lse_N: revoked"
rm -f "$root/revoke"

mkdir -p "$root/no-simlock"
cp "$root/bin/"* "$root/no-simlock/"
rm "$root/no-simlock/simlock"
path="$root/no-simlock:$(printf %s "$PATH" | tr ':' '\n' | while IFS= read -r dir; do [ -x "$dir/simlock" ] || printf '%s:' "$dir"; done)" test_sim
expect "with simlock missing from PATH it exits 78 before xcodebuild" "$? $(cat "$root/err") $([ -e "$root/seen" ] || echo no-xcodebuild)" \
    "78 simlock is not on PATH, and every simulator here comes from a Simlock lease; see .agents/skills/simlock/SKILL.md no-xcodebuild"

printf '\npassed %s, failed %s\n' "$pass" "$fail"
[ "$fail" -eq 0 ] || exit 1
