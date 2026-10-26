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
pids() { echo "$WORKOUT_RUN_DIR"/*/"$1.pids"; }

a1=$(start lane-a)
a2=$(start lane-a)
b1=$(start lane-b)
expect "--start prints the pid of a running process and records it with its start time" \
    "$(alive "$a1") $(cut -f1 "$(pids lane-a)" | tr '\n' ' ')$(awk -F '\t' 'NF == 2 && $2 != "" { n++ } END { print n }' "$(pids lane-a)")" \
    "alive $a1 $a2 2"
scope=$(dirname "$(pids lane-a)")

"$reap" lane-a "$b1" >"$root/out" 2>"$root/err"; status=$?
expect "reaping another run's pid refuses and kills nothing" \
    "$status $(alive "$b1") $(alive "$a1") $(alive "$a2")" "1 alive alive alive"
expect "the refusal says whose pidfile it read" "$(cat "$root/err")" \
    "reap.sh: pid $b1 is not in run lane-a's pidfile ($scope/lane-a.pids), so it is another run's or nobody's; killed nothing"

"$reap" lane-a "$a2" "$b1" >"$root/out" 2>"$root/err"; status=$?
expect "one foreign pid among the named ones refuses them all" "$status $(alive "$a2")" "1 alive"

"$reap" lane-a "$a2" >"$root/out" 2>&1; status=$?
expect "reaping a named pid of the run ends only that one and keeps the other's row" \
    "$status $(gone "$a2") $(alive "$a1") $(cut -f1 "$(pids lane-a)")" "0 ended alive $a1"

"$reap" lane-a >"$root/out" 2>&1; status=$?
expect "reaping the run ends its processes, leaves the other run's, and deletes the pidfile" \
    "$status $(gone "$a1") $(alive "$b1") $([ -e "$scope/lane-a.pids" ] && echo kept || echo deleted)" \
    "0 ended alive deleted"
expect "and names what it killed" "$(cat "$root/out")" "killed pid $a1"

"$reap" lane-a >"$root/out" 2>"$root/err"; status=$?
expect "a run with no pidfile exits 1 and kills nothing" "$status $(alive "$b1")" "1 alive"
expect "and says so" "$(cat "$root/err")" \
    "reap.sh: run lane-a has no pidfile at $scope/lane-a.pids, so there is nothing of its own to reap; killed nothing"

printf '%s\t%s\n' "$b1" "Thu Jan  1 00:00:00 1970" >"$scope/lane-c.pids"
"$reap" lane-c >"$root/out" 2>&1; status=$?
expect "a recorded pid that now belongs to a process started at another time is not killed" \
    "$status $(alive "$b1") $(cat "$root/out") $([ -e "$scope/lane-c.pids" ] && echo kept || echo deleted)" \
    "0 alive pid $b1 already ended deleted"

sleep 300 &
own=$!
started+=("$own")
"$reap" --record lane-d "$own" >"$root/out" 2>&1; status=$?
expect "--record takes a pid the caller started" "$status $(cut -f1 "$scope/lane-d.pids")" "0 $own"
kill "$own"; wait "$own" 2>/dev/null
"$reap" --record lane-d "$own" >"$root/out" 2>"$root/err"; status=$?
expect "--record refuses a pid that is not running" "$status $(cat "$root/err")" \
    "1 reap.sh: pid $own is not running, so run lane-d cannot record it"

orphan=$(sh -c 'sleep 300 </dev/null >/dev/null 2>&1 & echo $!')
started+=("$orphan")
"$reap" --record lane-e "$orphan" >"$root/out" 2>"$root/err"; status=$?
expect "--record refuses a running pid that is not the caller's child, and records nothing" \
    "$status $(alive "$orphan") $([ -e "$scope/lane-e.pids" ] && echo recorded || echo none)" "1 alive none"
expect "and says whose child it is not" "$(cat "$root/err")" \
    "reap.sh: pid $orphan is not a child of pid $$, which asked to record it, so run lane-e cannot record it"

mkdir -p "$root/wt-a/scripts" "$root/wt-b/scripts"
cp "$reap" "$root/wt-a/scripts/reap.sh"
cp "$reap" "$root/wt-b/scripts/reap.sh"
shared=$("$root/wt-a/scripts/reap.sh" --start shared sleep 300)
started+=("$shared")
"$root/wt-b/scripts/reap.sh" shared >"$root/out" 2>&1; status=$?
expect "a run of the same name in another checkout is another run, so its reap kills nothing" "$status $(alive "$shared")" "1 alive"
"$root/wt-a/scripts/reap.sh" shared >/dev/null 2>&1
expect "and the checkout that started it reaps it" "$(gone "$shared")" "ended"

zoned=$(TZ=America/Los_Angeles "$reap" --start lane-f sleep 300)
started+=("$zoned")
TZ=Asia/Tokyo "$reap" lane-f >"$root/out" 2>&1; status=$?
expect "a reap under another TZ than the record still matches the start time and kills" \
    "$status $(cat "$root/out") $(gone "$zoned")" "0 killed pid $zoned ended"

leader=$("$reap" --start lane-g sh -c "sleep 300 </dev/null >/dev/null 2>&1 & echo \$! >'$root/grandchild'; wait")
started+=("$leader")
for _ in $(seq 1 50); do [ -s "$root/grandchild" ] && break; sleep 0.1; done
grandchild=$(cat "$root/grandchild")
started+=("$grandchild")
"$reap" lane-g >/dev/null 2>&1
expect "reaping a process --start began also ends the children it started" "$(gone "$leader") $(gone "$grandchild")" "ended ended"

skill=$(dirname "$reap")/../.agents/skills/verify/SKILL.md
recipe=$(awk '/^```bash$/ { block = ""; inside = 1; next } /^```$/ { if (inside && block ~ /reap\.sh --start/) { printf "%s", block; exit } inside = 0 } inside { block = block $0 "\n" }' "$skill")
(
    cd "$(dirname "$reap")/.." && unset VERIFY_RUN
    eval "$(sed '$d' <<<"$recipe")"
    cp "$(pids issue-536)" "$root/recorded" 2>/dev/null
    eval "$(sed '$!d' <<<"$recipe")" >/dev/null
) >"$root/loaded" 2>&1
printed=$(grep -E '^[1-9][0-9]*$' "$root/loaded")
started+=($printed)
expect "the verify skill's load recipe, run with no VERIFY_RUN set, records every load process it prints" \
    "$(wc -l <<<"$printed" | tr -d ' ') $(cut -f1 "$root/recorded" 2>/dev/null | tr '\n' ' ')" "12 $(tr '\n' ' ' <<<"$printed")"
left=0
for pid in $printed; do [ "$(gone "$pid")" = ended ] || left=$((left + 1)); done
expect "and its reap line ends all of them" "$left" "0"

"$reap" ../lane-b >"$root/out" 2>"$root/err"; status=$?
expect "a run name that is not a plain name is a usage error" "$status $(alive "$b1")" "2 alive"

"$reap" lane-b >/dev/null 2>&1
expect "the last run reaps its own process" "$(gone "$b1")" "ended"

echo "reap: $pass passed, $fail failed"
[ "$fail" -eq 0 ]
