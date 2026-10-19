#!/bin/bash
set -uo pipefail

# shellcheck source=scripts/tests/host-admission-harness.sh
. "$(dirname "${BASH_SOURCE[0]}")/host-admission-harness.sh"

echo "build slots"
verify_build() { SIM=$sim "$repo/.agents/skills/verify/verify.sh" build; }
reset
SIM=$sim WORKOUT_BUILD_SLOTS=1 STUB_HOLD=1 "$repo/.agents/skills/verify/verify.sh" build >/dev/null 2>&1 &
first=$!
for _ in $(seq 1 100); do [ -f "$root/holding" ] && break; sleep 0.1; done
WORKOUT_BUILD_SLOTS=1 WORKOUT_ADMIT_WAIT=0 test_sim; status=$?
expect "a build waits while every slot is taken, and gives up with 75, not a build failure" "$status $(builds)" "75 build"
expect "the claim names the slot holders" "$(refusal)" \
    "gave up after N s waiting for the host before taking $sim: all 1 build slots are taken (WORKOUT_BUILD_SLOTS): verify.sh (pid $first); lsof $root/locks/build-* lists every process holding one"
WORKOUT_BUILD_SLOTS=1 WORKOUT_ADMIT_WAIT=0 verify_build >"$root/out" 2>"$root/err"
expect "verify.sh build's slot refusal reaches stderr through the build log's redirect" "$(refusal)" \
    "gave up after N s waiting for a build slot: all 1 build slots are taken (WORKOUT_BUILD_SLOTS): verify.sh (pid $first); lsof $root/locks/build-* lists every process holding one"
kill -9 "$first"; wait "$first" 2>/dev/null
WORKOUT_BUILD_SLOTS=1 WORKOUT_ADMIT_WAIT=0 test_sim; status=$?
expect "the xcodebuild of a killed run keeps its slot until it exits" "$status $(builds)" "75 build"
touch "$root/release"
for _ in $(seq 1 50); do
    WORKOUT_BUILD_SLOTS=1 WORKOUT_ADMIT_WAIT=0 test_sim; status=$?
    [ $status = 75 ] || break
    sleep 0.1
done
expect "the slot frees when that xcodebuild exits, and the next build runs" "$status $(builds)" "65 build build-for-testing"

reset
WORKOUT_BUILD_SLOTS=2 STUB_HOLD=1 test_sim &
first=$!
for _ in $(seq 1 100); do [ -f "$root/holding" ] && break; sleep 0.1; done
WORKOUT_BUILD_SLOTS=2 WORKOUT_ADMIT_WAIT=0 verify_build >"$root/out" 2>"$root/err"; status=$?
expect "verify.sh build takes the second slot beside a test-sim.sh build" "$status $(builds)" "65 build-for-testing build"
touch "$root/release"; wait "$first"

reset
STUB_MEM_LEVEL=12 WORKOUT_ADMIT_WAIT=0 verify_build >"$root/out" 2>"$root/err"; status=$?
expect "verify.sh build waits for memory as a claim does, and gives up with 75 before any xcodebuild" "$status $(builds) $(refusal)" \
    "75  gave up after N s waiting for a build slot: free memory is 12%, under the floor of 25% (WORKOUT_MEM_FLOOR)"
reset
STUB_MEM_LEVEL=12 STUB_LOW_MEM_CALLS=1 WORKOUT_ADMIT_WAIT=30 verify_build >"$root/out" 2>"$root/err"; status=$?
expect "and builds once memory frees" "$status $(builds)" "65 build"

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
    "75  gave up after N s waiting for the host before taking $sim: all 1 build slots are taken (WORKOUT_BUILD_SLOTS): build-slot.sh (pid $first); lsof $root/locks/build-* lists every process holding one"
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
