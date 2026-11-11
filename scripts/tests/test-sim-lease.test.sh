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
# Runs unit unless a selection is given after the flags, as in: test_sim --sim X -- ui
test_sim() {
    local flags=() selection=(unit)
    while [ $# -gt 0 ]; do
        [ "$1" != -- ] || { shift; selection=("$@"); break; }
        flags+=("$1"); shift
    done
    rm -f "$root/seen" "$root/release" "$root/load-read"
    STUB_RC=${rc:-0} PATH="${path:-$root/bin:$PATH}" "$repo/scripts/test-sim.sh" --no-build ${flags[@]+"${flags[@]}"} "${selection[@]}" >"$root/out" 2>"$root/err"
}
start() {
    rm -f "$root/seen" "$root/release" "$root/load-read"
    STUB_RC=0 STUB_RELEASE=$root/release PATH="$root/bin:$PATH" "$@" "$repo/scripts/test-sim.sh" --no-build unit >"$root/out" 2>"$root/err" &
    pid=$!
    born=$(proc_stamp "$pid")
    for _ in $(seq 100); do [ -e "$root/seen" ] && break; sleep 0.05; done
}
mine() { simlock list --leases | python3 -c 'import json, os, sys
print(" ".join(l["id"] + " " + l["deviceId"][4:] for l in json.load(sys.stdin) if l["requesterId"] == os.environ["FAKE_SIMLOCK_WHO"]))'; }
held() { mine | awk '{print $2}'; }
give_back() { local id; id=$(mine | awk '{print $1}'); [ -z "$id" ] || simlock release "$id" >/dev/null; }
mark() { wc -l <"$FAKE_SIMLOCK_STATE/log" | tr -d ' '; }
log_since() { tail -n +$(($1 + 1)) "$FAKE_SIMLOCK_STATE/log" | grep -E "${2:-.}" | sed 's/lse_[0-9]*/lse_N/g'; }
renews_since() { log_since "$1" '^renew' | wc -l | tr -d ' '; }
destination() { grep -m1 '^platform=' "$STUB_ARGS"; }
err() { sed 's/lse_[0-9]*/lse_N/g' "$root/err"; }
PATH="$root/bin:$PATH"
kept="kept simulator $spare_sim (Simlock lease lse_N) for 10 min for your next run; simlock release lse_N gives it back now"

before=$(mark)
test_sim
expect "with no lease held it leases a detached full simulator kept 10 min, runs on it, and keeps the lease when the run ends" \
    "$? $(destination) | $(err) | $(log_since "$before" '^(lease|release)') | $(held)" \
    "0 platform=iOS Simulator,id=$spare_sim | leasing an iPhone 17 Pro simulator on iOS 27.0 from Simlock, kept 10 min after the run for your next run (WORKOUT_TEST_LEASE_MINUTES)
simulator $spare_sim (Simlock lease lse_N)
$kept | lease lse_N $spare_sim by runner, detached, mode full, ttl 10m | $spare_sim"
first=$(mine)
test_sim
expect "a second run from the same identity runs on the same simulator, with one lease and no release across both runs" \
    "$? $(destination) | $(mine) | $(log_since "$before" '^(lease|release)')" \
    "0 platform=iOS Simulator,id=$spare_sim | $first | lease lse_N $spare_sim by runner, detached, mode full, ttl 10m"
expect "and says which lease it ran on and that it kept it" "$(err)" "simulator $spare_sim (your Simlock lease lse_N)
$kept"
expect "and leaves no scratch dir behind" "$(leftovers)" "0"

printf '%s\n' "✘ Test run with 1 test in 1 suite failed after 1.000 seconds with 1 issue." "** TEST EXECUTE FAILED **" >"$root/xcodebuild.log"
rc=65 test_sim
expect "a failing run keeps its lease too" "$? $(mine) | $(tail -1 "$root/err" | sed 's/lse_[0-9]*/lse_N/g')" "65 $first | $kept"
printf '%s\n' "$passing" >"$root/xcodebuild.log"

before=$(mark)
STUB_SLEEP=2.5 WORKOUT_LEASE_RENEW_SECONDS=1 test_sim
during=$(renews_since "$before")
sleep 2.5
expect "a run renews its lease while it runs and once as it ends, and nothing renews it after the run" \
    "$? $([ "$during" -ge 3 ] && echo renewed) $(renews_since "$before")" "0 renewed $during"

before=$(mark)
start env WORKOUT_LEASE_RENEW_SECONDS=1
sleep 1.5
signal_same KILL "$pid" "$born"; wait "$pid" 2>/dev/null; touch "$root/release"
sleep 1.5
after_kill=$(renews_since "$before")
sleep 2.5
expect "a run killed with SIGKILL had its heartbeat renewing, which stops, and leaves its lease to lapse with its TTL" \
    "$([ "$after_kill" -ge 1 ] && echo renewed) $(renews_since "$before") | $(mine)" "renewed $after_kill | $first"

start
signal_same TERM "$pid" "$born"; touch "$root/release"; wait "$pid"
expect "a run stopped with SIGTERM keeps its lease" "$? $(mine) | $(tail -1 "$root/err" | sed 's/lse_[0-9]*/lse_N/g')" "143 $first | $kept"

start python3 -c 'import os, signal, sys; signal.signal(signal.SIGINT, signal.SIG_DFL); os.execvp(sys.argv[1], sys.argv[1:])'
signal_same INT "$pid" "$born"; touch "$root/release"; wait "$pid"
expect "a run stopped with SIGINT keeps its lease" "$? $(held) $(mine)" "130 $spare_sim $first"

start
test_sim
expect "a second run while the first holds the simulator exits 75 and names the holder, and both keep the lease" \
    "$? $(tail -1 "$root/err" | sed 's/pid [0-9]*/pid N/') | $(mine)" \
    "75 $spare_sim is held by a test-sim.sh run (pid N); wait for it to finish, or use another simulator (lsof /tmp/workout-verify-$spare_sim/lock lists every process holding it) | $first"
test_sim -- ui
expect "and so does a UI run, which leaves the lease the first run is on alone" \
    "$? $(tail -1 "$root/err" | sed 's/pid [0-9]*/pid N/') | $(mine)" \
    "75 $spare_sim is held by a test-sim.sh run (pid N); wait for it to finish, or use another simulator (lsof /tmp/workout-verify-$spare_sim/lock lists every process holding it) | $first"
touch "$root/release"; wait "$pid"

before=$(mark)
rm -f "$root/keyboard"
test_sim -- ui
expect "a UI run runs on the lease a unit run kept, with no new lease and no release" \
    "$? $(destination) | $(mine) | $(log_since "$before" '^(lease|release)') | $(cat "$root/keyboard")" \
    "0 platform=iOS Simulator,id=$spare_sim | $first |  | ensure $spare_sim"
full=$first

test_sim --sim "$(echo "$spare_sim" | tr '[:upper:]' '[:lower:]')"
expect "--sim naming your own lease runs on it, says nothing of it, and leaves it held" \
    "$? $(destination) | $(cat "$root/err") | $(mine)" "0 platform=iOS Simulator,id=$spare_sim |  | $full"
SIM=$spare_sim test_sim
expect "SIM naming your own lease does the same" "$? $(mine)" "0 $full"

test_sim --sim "$other_sim"
expect "--sim naming another agent's lease exits 2 before xcodebuild" "$? $(cat "$root/err") $([ -e "$root/seen" ] || echo no-xcodebuild)" \
    "2 $other_sim is not the simulator of a Simlock lease you hold (yours: $spare_sim); lease one first, see .agents/skills/simlock/SKILL.md no-xcodebuild"

before=$(mark)
printf '%s\n' "Application launch for 'com.sunnypatel.WorkoutTracker' did not return a process handle nor launch error." \
    "✘ Test run with 1 test in 1 suite failed after 31.2 seconds with 1 issue." "** TEST EXECUTE FAILED **" >"$root/xcodebuild.log"
rm -f "$root/shutdowns"
rc=65 test_sim
expect "a simulator fault exits 69, shuts the simulator down, and keeps the lease, which may be the one an agent designs on" \
    "$? $(grep '^simulator fault' "$root/err" | sed 's/lse_[0-9]*/lse_N/g') | $(log_since "$before" '^release') | $(mine) | $(cat "$root/shutdowns" 2>/dev/null)" \
    "69 simulator fault, not a test result: xcodebuild reported \"did not return a process handle nor launch error\". Shut $spare_sim down so the next run boots it fresh; rerun the same command, and if it faults again, release its Simlock lease and lease another |  | $first | simctl shutdown $spare_sim"
printf '%s\n' "$passing" >"$root/xcodebuild.log"
give_back

test_sim --sim "$spare_sim"
expect "--sim when you hold no lease exits 2" "$? $(cat "$root/err")" \
    "2 $spare_sim is not the simulator of a Simlock lease you hold (yours: none); lease one first, see .agents/skills/simlock/SKILL.md"

WORKOUT_TEST_LEASE_MINUTES=3 test_sim
expect "WORKOUT_TEST_LEASE_MINUTES sets how long the lease is kept" "$? $(log_since 0 '^lease .* by runner' | tail -1) | $(tail -1 "$root/err" | sed 's/lse_[0-9]*/lse_N/g')" \
    "0 lease lse_N $spare_sim by runner, detached, mode full, ttl 3m | kept simulator $spare_sim (Simlock lease lse_N) for 3 min for your next run; simlock release lse_N gives it back now"
give_back

simlock lease --platform ios --device 'iPhone 17 Pro' --os 27.0 --mode full --detach --ttl 60m >/dev/null
before=$(mark)
WORKOUT_LEASE_RENEW_SECONDS=1 STUB_SLEEP=1.5 test_sim
expect "a run on a verify lease renews it without shortening it, and keeps it" \
    "$? $(log_since "$before" '^(lease|release|renew)' | sort -u) | $(simlock list --leases | python3 -c 'import json, sys; print(" ".join(str(l["ttlMs"]) for l in json.load(sys.stdin) if l["requesterId"] == "runner"))') | $(tail -1 "$root/err" | sed 's/lse_[0-9]*/lse_N/g')" \
    "0 renew lse_N | 3600000 | kept simulator $spare_sim (Simlock lease lse_N) for 60 min for your next run; simlock release lse_N gives it back now"
give_back

FAKE_SIMLOCK_REFUSE=10 test_sim
expect "Simlock's queue timing out exits 75" "$? $(tail -1 "$root/err")" \
    "75 Simlock had no free iPhone 17 Pro simulator within WORKOUT_ADMIT_WAIT (540 s); the host is full, so retry later"
expect "a refused lease leaves no scratch dir behind either" "$(leftovers)" "0"
FAKE_SIMLOCK_DEVICES="$sim $other_sim" WORKOUT_ADMIT_WAIT=0 test_sim
expect "with WORKOUT_ADMIT_WAIT=0 and no free simulator it does not queue, and exits 75" "$? $(tail -1 "$root/err") | $(tail -1 "$FAKE_SIMLOCK_STATE/log")" \
    "75 Simlock had no free iPhone 17 Pro simulator within WORKOUT_ADMIT_WAIT (0 s); the host is full, so retry later | refused runner (11): no free device"

before=$(mark)
STUB_TOUCH=$root/revoke FAKE_SIMLOCK_REVOKE=$root/revoke test_sim
expect "a lease Simlock takes back mid-run exits 69" "$? $(tail -1 "$root/err") | $(log_since "$before" '^release')" \
    "69 Simlock took the lease back, so the simulator is gone; rerun to lease another | release lse_N: revoked"
rm -f "$root/revoke"

WORKOUT_TEST_LEASE_MINUTES=0 test_sim
expect "WORKOUT_TEST_LEASE_MINUTES under 1 exits 2" "$? $(cat "$root/err")" "2 WORKOUT_TEST_LEASE_MINUTES must be at least 1: 0"

mkdir -p "$root/no-simlock"
cp "$root/bin/"* "$root/no-simlock/"
rm "$root/no-simlock/simlock"
path="$root/no-simlock:$(printf %s "$PATH" | tr ':' '\n' | while IFS= read -r dir; do [ -x "$dir/simlock" ] || printf '%s:' "$dir"; done)" test_sim
expect "with simlock missing from PATH it exits 78 before xcodebuild" "$? $(cat "$root/err") $([ -e "$root/seen" ] || echo no-xcodebuild)" \
    "78 simlock is not on PATH, and every simulator here comes from a Simlock lease; see .agents/skills/simlock/SKILL.md no-xcodebuild"

printf '\npassed %s, failed %s\n' "$pass" "$fail"
[ "$fail" -eq 0 ] || exit 1
