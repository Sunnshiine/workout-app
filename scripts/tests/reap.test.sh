#!/bin/bash
set -uo pipefail

reap=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/reap.sh
root=$(mktemp -d) || exit 3
export WORKOUT_RUN_DIR=$root/runs
started=()
cleanup() {
    [ ${#started[@]} -eq 0 ] || kill "${started[@]}" 2>/dev/null
    rm -rf "$root"
}
trap cleanup EXIT
pass=0
fail=0
ok()  { pass=$((pass + 1)); printf '  ok   %s\n' "$1"; }
bad() { fail=$((fail + 1)); printf '  FAIL %s\n' "$1"; }
expect() { if [ "$2" = "$3" ]; then ok "$1"; else bad "$1"; printf '    got:  %s\n    want: %s\n' "$2" "$3"; fi; }
alive() { kill -0 "$1" 2>/dev/null && echo alive || echo ended; }
# A killed child stays a zombie, which kill -0 still finds, until something waits on it.
gone() {
    local i=0
    while kill -0 "$1" 2>/dev/null && [ $i -lt 50 ]; do sleep 0.1; i=$((i + 1)); done
    alive "$1"
}
start() { local pid; pid=$("$reap" --start "$1" sleep 300) && started+=("$pid") && echo "$pid"; }

a1=$(start lane-a)
a2=$(start lane-a)
b1=$(start lane-b)
expect "--start prints the pid of a running process and records it with its start time" \
    "$(alive "$a1") $(cut -f1 "$WORKOUT_RUN_DIR/lane-a.pids" | tr '\n' ' ')$(awk -F '\t' 'NF == 2 && $2 != "" { n++ } END { print n }' "$WORKOUT_RUN_DIR/lane-a.pids")" \
    "alive $a1 $a2 2"

"$reap" lane-a "$b1" >"$root/out" 2>"$root/err"; status=$?
expect "reaping another run's pid refuses and kills nothing" \
    "$status $(alive "$b1") $(alive "$a1") $(alive "$a2")" "1 alive alive alive"
expect "the refusal says whose pidfile it read" "$(cat "$root/err")" \
    "reap.sh: pid $b1 is not in run lane-a's pidfile ($WORKOUT_RUN_DIR/lane-a.pids), so it is another run's or nobody's; killed nothing"

"$reap" lane-a "$a2" "$b1" >"$root/out" 2>"$root/err"; status=$?
expect "one foreign pid among the named ones refuses them all" "$status $(alive "$a2")" "1 alive"

"$reap" lane-a "$a2" >"$root/out" 2>&1; status=$?
expect "reaping a named pid of the run ends only that one and keeps the other's row" \
    "$status $(gone "$a2") $(alive "$a1") $(cut -f1 "$WORKOUT_RUN_DIR/lane-a.pids")" "0 ended alive $a1"

"$reap" lane-a >"$root/out" 2>&1; status=$?
expect "reaping the run ends its processes, leaves the other run's, and deletes the pidfile" \
    "$status $(gone "$a1") $(alive "$b1") $([ -e "$WORKOUT_RUN_DIR/lane-a.pids" ] && echo kept || echo deleted)" \
    "0 ended alive deleted"
expect "and names what it killed" "$(cat "$root/out")" "killed pid $a1"

"$reap" lane-a >"$root/out" 2>"$root/err"; status=$?
expect "a run with no pidfile exits 1 and kills nothing" "$status $(alive "$b1")" "1 alive"
expect "and says so" "$(cat "$root/err")" \
    "reap.sh: run lane-a has no pidfile at $WORKOUT_RUN_DIR/lane-a.pids, so there is nothing of its own to reap; killed nothing"

printf '%s\t%s\n' "$b1" "Thu Jan  1 00:00:00 1970" >"$WORKOUT_RUN_DIR/lane-c.pids"
"$reap" lane-c >"$root/out" 2>&1; status=$?
expect "a recorded pid that now belongs to a process started at another time is not killed" \
    "$status $(alive "$b1") $(cat "$root/out") $([ -e "$WORKOUT_RUN_DIR/lane-c.pids" ] && echo kept || echo deleted)" \
    "0 alive pid $b1 already ended deleted"

sleep 300 &
own=$!
started+=("$own")
"$reap" --record lane-d "$own" >"$root/out" 2>&1; status=$?
expect "--record takes a pid the caller started" "$status $(cut -f1 "$WORKOUT_RUN_DIR/lane-d.pids")" "0 $own"
kill "$own"; wait "$own" 2>/dev/null
"$reap" --record lane-d "$own" >"$root/out" 2>"$root/err"; status=$?
expect "--record refuses a pid that is not running" "$status $(cat "$root/err")" \
    "1 reap.sh: pid $own is not running, so run lane-d cannot record it"

"$reap" ../lane-b >"$root/out" 2>"$root/err"; status=$?
expect "a run name that is not a plain name is a usage error" "$status $(alive "$b1")" "2 alive"

"$reap" lane-b >/dev/null 2>&1
expect "the last run reaps its own process" "$(gone "$b1")" "ended"

echo "reap: $pass passed, $fail failed"
[ "$fail" -eq 0 ]
