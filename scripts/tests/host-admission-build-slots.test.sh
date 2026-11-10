#!/bin/bash
set -uo pipefail

# shellcheck source=scripts/tests/host-admission-harness.sh
. "$(dirname "${BASH_SOURCE[0]}")/host-admission-harness.sh"

echo "build slots"
reset
WORKOUT_BUILD_SLOTS=1 neighbour_build
WORKOUT_BUILD_SLOTS=1 WORKOUT_ADMIT_WAIT=0 test_sim; status=$?
expect "a build waits while every slot is taken, even by a run on another simulator, and gives up with 75, not a build failure" \
    "$status $(builds)" "75 build-for-testing"
expect "the claim names the slot holders" "$(refusal)" \
    "gave up after N s waiting for the host before running on $sim: all 1 build slots are taken (WORKOUT_BUILD_SLOTS): test-sim.sh (pid $first); lsof $root/locks/build-* lists every process holding one"
kill -9 "$first"; wait "$first" 2>/dev/null
WORKOUT_BUILD_SLOTS=1 WORKOUT_ADMIT_WAIT=0 test_sim; status=$?
expect "the xcodebuild of a killed run keeps its slot until it exits" "$status $(builds)" "75 build-for-testing"
touch "$root/release"
for _ in $(seq 1 50); do
    WORKOUT_BUILD_SLOTS=1 WORKOUT_ADMIT_WAIT=0 test_sim; status=$?
    [ $status = 75 ] || break
    sleep 0.1
done
expect "the slot frees when that xcodebuild exits, and the next build runs" "$status $(builds)" "65 build-for-testing build-for-testing"

reset
WORKOUT_BUILD_SLOTS=2 neighbour_build
WORKOUT_BUILD_SLOTS=2 WORKOUT_ADMIT_WAIT=0 test_sim; status=$?
expect "a second build takes the second slot beside the first" "$status $(builds)" "65 build-for-testing build-for-testing"
touch "$root/release"; wait "$first"

reset
WORKOUT_ADMIT_WAIT=six test_sim; status=$?
expect "a knob that is not a whole number is a usage error" "$status $(cat "$root/err")" "2 WORKOUT_ADMIT_WAIT must be a whole number: six"
reset
WORKOUT_BUILD_SLOTS=0 test_sim; status=$?
expect "zero build slots is a usage error, before any build" "$status $(builds) $(cat "$root/err")" "2  WORKOUT_BUILD_SLOTS must be at least 1: 0"

echo "build-slot.sh"
build_slot() { "$repo/scripts/build-slot.sh" "$@" >"$root/out" 2>"$root/err"; }
reset
(cd "$repo" && build_slot sh -c 'echo ran; exit 3'); status=$?
expect "it runs the command and exits with the command's status, saying nothing" "$status $(cat "$root/out") $(cat "$root/err")" "3 ran "
expect "and meters it into the dev-usage ledger" \
    "$(tail -1 "$HOME/Library/Logs/WorkoutTracker/dev-usage/commands.tsv" | cut -f2-4)" "$(cd "$repo" && pwd -P)	sh -c	3"
reset
WORKOUT_BUILD_SLOTS=1 "$repo/scripts/build-slot.sh" sh -c 'touch "$1/holding"; while [ ! -f "$1/release" ]; do sleep 0.1; done' _ "$root" &
first=$!
for _ in $(seq 1 100); do [ -f "$root/holding" ] && break; sleep 0.1; done
WORKOUT_BUILD_SLOTS=1 WORKOUT_ADMIT_WAIT=0 test_sim; status=$?
expect "the command holds a build slot that test-sim.sh builds wait for" "$status $(builds) $(refusal)" \
    "75  gave up after N s waiting for the host before running on $sim: all 1 build slots are taken (WORKOUT_BUILD_SLOTS): build-slot.sh (pid $first); lsof $root/locks/build-* lists every process holding one"
WORKOUT_BUILD_SLOTS=1 WORKOUT_ADMIT_WAIT=0 build_slot touch "$root/ran"; status=$?
expect "with every slot taken it exits 75 after the max wait, without running the command" "$status $([ -f "$root/ran" ] && echo ran) $(refusal)" \
    "75  gave up after N s waiting for a build slot: all 1 build slots are taken (WORKOUT_BUILD_SLOTS): build-slot.sh (pid $first); lsof $root/locks/build-* lists every process holding one"
kill -9 "$first"; wait "$first" 2>/dev/null
WORKOUT_BUILD_SLOTS=1 WORKOUT_ADMIT_WAIT=0 build_slot touch "$root/ran"; status=$?
expect "the metered command keeps its slot when build-slot.sh is killed" "$status $([ -f "$root/ran" ] && echo ran)" "75 "
touch "$root/release"
for _ in $(seq 1 50); do WORKOUT_BUILD_SLOTS=1 WORKOUT_ADMIT_WAIT=0 build_slot true && break; sleep 0.1; done
rm -f "$root/ran"
STUB_MEM_LEVEL=12 WORKOUT_ADMIT_WAIT=0 build_slot touch "$root/ran"; status=$?
expect "with free memory under the floor it exits 75 without running the command" "$status $([ -f "$root/ran" ] && echo ran) $(refusal)" \
    "75  gave up after N s waiting for a build slot: free memory is 12%, under the floor of 25% (WORKOUT_MEM_FLOOR)"
STUB_LOAD=212.40 WORKOUT_ADMIT_WAIT=0 build_slot true; status=$?
expect "the 1-minute load holds nothing" "$status" "0"
build_slot; status=$?
expect "with no command it prints the usage and exits 2" "$status $(head -1 "$root/err")" "2 Usage: scripts/build-slot.sh <command> [arg...]"
build_slot --help; status=$?
expect "--help prints the usage on stdout and exits 0" "$status $(head -1 "$root/out")" "0 Usage: scripts/build-slot.sh <command> [arg...]"

printf '\npassed %d, failed %d\n' "$pass" "$fail"
[ "$fail" = 0 ]
