#!/bin/bash
# shellcheck disable=SC2016,SC2012,SC2010  # producers expand $DEP_STORE_OUT themselves; the names ls lists are ours
set -uo pipefail

script=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/dep-store.sh
root=$(mktemp -d) || exit 3
root=$(cd "$root" && pwd -P)
trap 'rm -rf "$root"' EXIT
export WORKOUT_DEP_STORE=$root/store WORKOUT_DEP_STORE_GRACE_MINUTES=0
pass=0
fail=0

ok()  { pass=$((pass + 1)); printf '  ok   %s\n' "$1"; }
bad() { fail=$((fail + 1)); printf '  FAIL %s\n' "$1"; }
expect() {
    if [ "$2" = "$3" ]; then ok "$1"; else bad "$1"; printf '    got:\n%s\n    want:\n%s\n' "$2" "$3"; fi
}
wait_for() { local _; for _ in $(seq 1 200); do [ -e "$1" ] && return; sleep 0.05; done; }
tree() { (cd "$1" && find . -type f -exec shasum {} + | sort -k2 | shasum | cut -c1-12); }

printf 'pins-v1\n' >"$root/resolved"
k1=$("$script" key "$root/resolved" -s 27A266a)
k2=$("$script" key "$root/resolved" -s 27A266a)
printf 'pins-v2\n' >"$root/resolved"
k3=$("$script" key "$root/resolved" -s 27A266a)
k4=$("$script" key "$root/resolved" -s 27A300)
expect "a key is the same for the same inputs and changes with a file's bytes or a string" \
    "$([ "$k1" = "$k2" ] && echo same) $([ "$k1" != "$k3" ] && echo file-differs) $([ "$k3" != "$k4" ] && echo string-differs) ${#k1}" \
    "same file-differs string-differs 64"
got=$("$script" key "$root/missing" 2>&1)
expect "a key for a missing file is a usage error" "$? $got" "2 dep-store: not a file: $root/missing"

out=$("$script" publish "$k1" sh -c 'echo "$DEP_STORE_OUT" >"$DEP_STORE_OUT/where"; mkdir "$DEP_STORE_OUT/sub"; echo payload >"$DEP_STORE_OUT/sub/file"' 2>"$root/err")
status=$?
"$script" clone "$k1" "$root/lane-a/SourcePackages"
expect "a publish runs the producer in a private dir and a clone reproduces its tree, with stdout quiet" \
    "$status [$out] $(ls "$root/lane-a/SourcePackages" | tr '\n' ' ') $(cat "$root/lane-a/SourcePackages/sub/file") $(sed -E 's/\([0-9]+ KiB in [0-9]+ s\)/(N KiB in N s)/' "$root/err")" \
    "0 [] sub where  payload dep-store: published $k1 (N KiB in N s)"
expect "the producer wrote inside the store's staging area, never into entries" \
    "$(cat "$root/lane-a/SourcePackages/where" | sed "s#$root/store/staging/[0-9]*\.$k1\.[A-Za-z0-9]*/payload#STAGING/payload#")" "STAGING/payload"
expect "a published entry leaves no staging dir behind" "$(ls -A "$root/store/staging" | wc -l | tr -d ' ')" "0"

"$script" publish "$k1" sh -c 'echo ran >"$DEP_STORE_OUT/again"' 2>"$root/err"
expect "a second publish of the same key never runs the producer" \
    "$? $(cat "$root/err") $(ls "$root/store/entries/$k1/payload" | tr '\n' ' ')" "0 dep-store: $k1 is already published sub where "

got=$("$script" clone "$k3" "$root/lane-b/SourcePackages" 2>&1)
expect "a clone of a key nobody published exits 3 and creates nothing" "$? $got $([ -e "$root/lane-b/SourcePackages" ] || echo absent)" \
    "3 dep-store: no entry $k3 absent"

got=$("$script" clone "$k1" "$root/lane-a/SourcePackages" 2>&1)
expect "a clone refuses a destination that already exists" "$? $got" \
    "2 dep-store: $root/lane-a/SourcePackages exists; clone into a path that does not exist yet"

got=$("$script" publish "$k3" sh -c 'echo partial >"$DEP_STORE_OUT/x"; exit 7' 2>&1)
expect "a failing producer publishes nothing and its status passes through" \
    "$? $got $([ -d "$root/store/entries/$k3" ] || echo no-entry) $(ls -A "$root/store/staging" | wc -l | tr -d ' ')" \
    "7 dep-store: producer exited 7; nothing published for $k3 no-entry 0"
got=$("$script" publish "$k3" true 2>&1)
expect "a producer that writes nothing publishes nothing" "$? $got" \
    "70 dep-store: producer wrote nothing to \$DEP_STORE_OUT; nothing published for $k3"

for i in 1 2 3 4 5; do
    "$script" publish race sh -c 'sleep 0.2; for f in a b c; do echo "$0" >"$DEP_STORE_OUT/$f"; sleep 0.05; done' "producer-$i" 2>>"$root/race-err" &
done
wait
expect "five concurrent publishers on one key end with one complete entry from one producer and no staging" \
    "$(ls "$root/store/entries" | grep -c race) $(ls "$root/store/entries/race/payload" | tr '\n' ' ') $(sort -u "$root/store/entries/race/payload"/* | wc -l | tr -d ' ') $(ls -A "$root/store/staging" | wc -l | tr -d ' ') $(grep -c 'published race (' "$root/race-err") $(grep -c 'discarded' "$root/race-err")" \
    "1 a b c  1 0 1 4"

(exec "$script" publish crashed sh -c 'echo half >"$DEP_STORE_OUT/half"; touch "$0"; sleep 30' "$root/crash-started") 2>/dev/null &
crasher=$!
wait_for "$root/crash-started"
pkill -9 -P "$crasher" 2>/dev/null
kill -9 "$crasher" 2>/dev/null
wait "$crasher" 2>/dev/null
pkill -9 -f "sleep 30" 2>/dev/null
got=$("$script" clone crashed "$root/lane-c" 2>&1)
expect "a producer killed mid-build leaves a staging dir readers never see, so a clone misses" \
    "$? $got $(ls "$root/store/staging" | grep -c '\.crashed\.') $([ -e "$root/lane-c" ] || echo absent)" "3 dep-store: no entry crashed 1 absent"
"$script" publish crashed sh -c 'echo whole >"$DEP_STORE_OUT/whole"' 2>/dev/null
"$script" clone crashed "$root/lane-c"
expect "the next publish of that key succeeds and sweeps the dead producer's staging dir" \
    "$(ls "$root/lane-c" | tr '\n' ' ') $(ls -A "$root/store/staging" | wc -l | tr -d ' ')" "whole  0"

(exec "$script" publish slow sh -c 'for f in 1 2 3 4 5; do echo "$f" >"$DEP_STORE_OUT/part$f"; sleep 0.1; done') 2>/dev/null &
slow=$!
misses=0
for _ in $(seq 1 100); do
    if "$script" clone slow "$root/lane-d" 2>/dev/null; then break; fi
    misses=$((misses + 1))
    sleep 0.02
done
wait "$slow"
expect "a reader polling during a slow publish sees only misses, then the complete entry" \
    "$([ "$misses" -gt 0 ] && echo missed-first) $(ls "$root/lane-d" | tr '\n' ' ')" "missed-first part1 part2 part3 part4 part5 "

before=$(tree "$root/lane-a/SourcePackages")
"$script" prune --keep-bytes 0 2>"$root/err"
expect "a prune to zero bytes removes every entry and a lane's clone keeps its files" \
    "$(ls "$root/store/entries" | wc -l | tr -d ' ') $(tree "$root/lane-a/SourcePackages") $(tail -1 "$root/err")" \
    "0 $before dep-store: pruned 4 entries; 0 KiB stay in $root/store/entries"

for name in old mid new; do
    "$script" publish "$name" sh -c 'head -c 40000 /dev/zero >"$DEP_STORE_OUT/blob"' 2>/dev/null
done
touch -t 202001010000 "$root/store/entries/old/used"
touch -t 202101010000 "$root/store/entries/mid/used"
"$script" clone new "$root/lane-e" 2>/dev/null
per_entry=$(du -sk "$root/store/entries/new" | cut -f1)
"$script" prune --keep-bytes $((per_entry * 1024 * 2)) 2>"$root/err"
expect "a prune over budget removes the least recently cloned entries first" \
    "$(ls "$root/store/entries" | tr '\n' ' ') $(head -1 "$root/err")" \
    "mid new  dep-store: pruned old ($per_entry KiB, last cloned 2020-01-01T00:00:00)"
WORKOUT_DEP_STORE_GRACE_MINUTES=10 "$script" prune --keep-bytes 0 2>"$root/err"
expect "a prune never removes an entry cloned inside the grace window, so a clone in flight is safe" \
    "$(ls "$root/store/entries" | tr '\n' ' ') $(sed -n 2p "$root/err" | sed -E 's/cloned [0-9]+ min ago/cloned N min ago/')" \
    "new  dep-store: new was cloned N min ago, inside the 10 min grace; keeping it and every newer entry"
expect "list names each entry with its size and last clone" "$("$script" list | cut -f1,2)" "new	$per_entry KiB"

got=$("$script" clone 'bad/../key' "$root/x" 2>&1)
expect "a key that could escape the entries dir is refused" "$?" "2"

printf '\npassed %s, failed %s\n' "$pass" "$fail"
[ "$fail" -eq 0 ] || exit 1
