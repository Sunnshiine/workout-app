#!/bin/bash
set -uo pipefail

# shellcheck source=scripts/tests/host-admission-harness.sh
. "$(dirname "${BASH_SOURCE[0]}")/host-admission-harness.sh"

echo "admission"
reset
STUB_LOAD=212.40 WORKOUT_ADMIT_WAIT=0 test_sim --no-build; status=$?
expect "a 1-minute load of 212.40 holds no claim, and the claim prints nothing" "$status $(builds) $(grep -c . "$root/err")" \
    "65 test-without-building 1"

reset
STUB_MEM_LEVEL=12 WORKOUT_ADMIT_WAIT=0 test_sim --no-build; status=$?
expect "free memory under the floor refuses after the max wait, before any xcodebuild" "$status $(builds)" "75 "
expect "the refusal names the free memory and the knob" "$(refusal)" \
    "gave up after N s waiting for the host before running on $sim: free memory is 12%, under the floor of 25% (WORKOUT_MEM_FLOOR)"

reset
STUB_MEM_LEVEL=12 STUB_LOW_MEM_CALLS=2 WORKOUT_ADMIT_WAIT=30 test_sim --no-build; status=$?
expect "a claim waits for memory to free, then goes on" "$status $(builds)" "65 test-without-building"
expect "the wait is announced, then its end" "$(sed -n '1p;2s/[0-9]* s$/N s/p' "$root/err")" \
    "waiting up to 30 s for the host before running on $sim: free memory is 12%, under the floor of 25% (WORKOUT_MEM_FLOOR)
went ahead after N s"

reset
STUB_MEM_LEVEL=12 STUB_LOW_MEM_CALLS=1 WORKOUT_ADMIT_WAIT=3 bash -c '. "$1/scripts/sim-lock.sh"; sleep 4; wait_until_clear "memory" mem_clear' _ "$repo" 2>"$root/err"; status=$?
expect "a wait's budget starts when the wait does, so time spent before it, as on a cache build, is not counted" \
    "$status $(sed -n '2s/[0-9]* s$/N s/p' "$root/err")" "0 went ahead after N s"

reset
STUB_MEM_LEVEL=25 WORKOUT_ADMIT_WAIT=0 test_sim --no-build; status=$?
expect "free memory exactly at the floor is admitted" "$status $(builds)" "65 test-without-building"
reset
STUB_MEM_LEVEL=12 WORKOUT_MEM_FLOOR=10 test_sim --no-build; status=$?
expect "WORKOUT_MEM_FLOOR lowers the floor, and a clear claim prints nothing" "$status $(builds) $(grep -c . "$root/err")" \
    "65 test-without-building 1"
reset
STUB_SYSCTL_FAILS=1 WORKOUT_MEM_FLOOR=0 test_sim --no-build; status=$?
expect "a floor of 0 never reads memory, so even a failing sysctl holds nothing" "$status $(builds) $(cat "$root/mem-calls" 2>/dev/null)" \
    "65 test-without-building "
reset
STUB_SYSCTL_FAILS=1 WORKOUT_ADMIT_WAIT=0 test_sim --no-build; status=$?
expect "on macOS a sysctl that fails holds the claim" "$status $(refusal)" \
    "75 gave up after N s waiting for the host before running on $sim: sysctl -n kern.memorystatus_level failed: sysctl: unknown oid 'kern.memorystatus_level'"
reset
STUB_MEM_LEVEL=n/a WORKOUT_ADMIT_WAIT=0 test_sim --no-build; status=$?
expect "a memory reading that is not a whole number holds the claim" "$status $(refusal)" \
    "75 gave up after N s waiting for the host before running on $sim: sysctl -n kern.memorystatus_level printed no free-memory percent: n/a"
reset
WORKOUT_MEM_FLOOR=-1 test_sim --no-build; status=$?
expect "a negative floor is a usage error" "$status $(cat "$root/err")" "2 WORKOUT_MEM_FLOOR must be a whole number: -1"

reset
STUB_HOLD=1 test_sim &
first=$!
for _ in $(seq 1 100); do [ -f "$root/holding" ] && break; sleep 0.1; done
FAKE_SIMLOCK_WHO=neighbour WORKOUT_ADMIT_WAIT=0 "$repo/scripts/test-sim.sh" --no-build --sim "$sim" unit >"$root/out" 2>"$root/err"; status=$?
expect "another agent's run on your leased simulator is refused before it runs" "$status $(builds)" "2 build-for-testing"
touch "$root/release"; wait "$first"

printf '\npassed %d, failed %d\n' "$pass" "$fail"
[ "$fail" = 0 ]
