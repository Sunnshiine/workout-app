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
STUB_LOAD=212.40 WORKOUT_ADMIT_WAIT=0 SIM=$sim "$repo/.agents/skills/verify/verify.sh" build >"$root/out" 2>"$root/err"; status=$?
expect "a 1-minute load of 212.40 holds no build" "$status $(builds)" "65 build"

reset
STUB_MEM_LEVEL=12 WORKOUT_ADMIT_WAIT=0 test_sim --no-build; status=$?
expect "free memory under the floor refuses after the max wait, before any xcodebuild" "$status $(builds)" "75 "
expect "the refusal names the free memory and the knob" "$(refusal)" \
    "gave up after N s waiting for the host before taking $sim: free memory is 12%, under the floor of 25% (WORKOUT_MEM_FLOOR)"

reset
STUB_MEM_LEVEL=12 STUB_LOW_MEM_CALLS=2 WORKOUT_ADMIT_WAIT=30 test_sim --no-build; status=$?
expect "a claim waits for memory to free, then goes on" "$status $(builds)" "65 test-without-building"
expect "the wait is announced, then its end" "$(sed -n '1p;2s/[0-9]* s$/N s/p' "$root/err")" \
    "waiting up to 30 s for the host before taking $sim: free memory is 12%, under the floor of 25% (WORKOUT_MEM_FLOOR)
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
    "75 gave up after N s waiting for the host before taking $sim: sysctl -n kern.memorystatus_level failed: sysctl: unknown oid 'kern.memorystatus_level'"
reset
STUB_MEM_LEVEL=n/a WORKOUT_ADMIT_WAIT=0 test_sim --no-build; status=$?
expect "a memory reading that is not a whole number holds the claim" "$status $(refusal)" \
    "75 gave up after N s waiting for the host before taking $sim: sysctl -n kern.memorystatus_level printed no free-memory percent: n/a"
reset
WORKOUT_MEM_FLOOR=-1 test_sim --no-build; status=$?
expect "a negative floor is a usage error" "$status $(cat "$root/err")" "2 WORKOUT_MEM_FLOOR must be a whole number: -1"

reset
STUB_SHUTDOWN=$sim STUB_BOOTED_OTHERS=10 WORKOUT_ADMIT_WAIT=0 test_sim --no-build; status=$?
expect "ten other booted simulators refuse a claim that would boot an eleventh" "$status $(builds)" "75 "
expect "the refusal names the count and the knob" "$(refusal)" \
    "gave up after N s waiting for the host before taking $sim: 10 other simulators are booted, at the cap of 10 (WORKOUT_SIM_CAP)"

reset
STUB_BOOTED_OTHERS=10 WORKOUT_ADMIT_WAIT=0 test_sim --no-build; status=$?
expect "a claim on a simulator already booted boots nothing, so the cap does not hold it" "$status $(builds)" "65 test-without-building"

reset
for verb in "launch session" install; do
    read -ra argv <<< "$verb"
    STUB_SHUTDOWN=$sim STUB_BOOTED_OTHERS=10 WORKOUT_ADMIT_WAIT=0 verify "${argv[@]}" >"$root/out" 2>"$root/err"; status=$?
    expect "verify.sh $verb boots a shut-down simulator only through admission" \
        "$status $(cat "$root/xcrun-calls" 2>/dev/null | grep -c 'simctl boot') $(grep '^gave up' "$root/err" | sed 's/^gave up after [0-9]* s/gave up after N s/')" \
        "75 0 gave up after N s waiting for the host before taking $sim: 10 other simulators are booted, at the cap of 10 (WORKOUT_SIM_CAP)"
done
STUB_SHUTDOWN=$sim STUB_BOOTED_OTHERS=10 WORKOUT_ADMIT_WAIT=0 verify build >"$root/out" 2>"$root/err"; status=$?
expect "verify.sh build boots nothing, so the cap does not hold it" "$status $(cat "$root/xcrun-calls" 2>/dev/null | grep -c 'simctl boot') $(builds)" "65 0 build"

reset
STUB_SHUTTING_DOWN=$sim WORKOUT_ADMIT_WAIT=0 test_sim --no-build; status=$?
expect "a simulator still shutting down waits, so the cap counts its boot" "$status $(refusal)" \
    "75 gave up after N s waiting for the host before taking $sim: $sim is shutting down"

reset
STUB_SHUTDOWN=$sim2 STUB_BOOTED_OTHERS=10 WORKOUT_BUILD_SLOTS=1 WORKOUT_ADMIT_WAIT=4 \
    "$repo/scripts/test-sim.sh" --sim "$sim2" unit >/dev/null 2>"$root/err2" &
first=$!
for _ in $(seq 1 100); do grep -q "waiting up to" "$root/err2" 2>/dev/null && break; sleep 0.1; done
STUB_SHUTDOWN=$sim2 STUB_BOOTED_OTHERS=10 WORKOUT_BUILD_SLOTS=1 WORKOUT_ADMIT_WAIT=0 test_sim; status=$?
wait "$first"
expect "a build claim waiting at the cap holds no build slot" "$status $(builds)" "65 build-for-testing"

reset
mkdir -p "$root/locks"
python3 -c 'import fcntl, sys, time
slot = open(sys.argv[1], "a")
fcntl.flock(slot, fcntl.LOCK_EX)
open(sys.argv[2], "w").close()
time.sleep(30)' "$root/locks/build-1" "$root/holding" &
building=$!
for _ in $(seq 1 100); do [ -f "$root/holding" ] && break; sleep 0.1; done
STUB_SHUTDOWN=$sim2 WORKOUT_BUILD_SLOTS=1 WORKOUT_ADMIT_WAIT=8 \
    "$repo/scripts/test-sim.sh" --sim "$sim2" unit >/dev/null 2>"$root/err2" &
first=$!
for _ in $(seq 1 100); do grep -q "waiting up to" "$root/err2" 2>/dev/null && break; sleep 0.1; done
held=$(python3 -c 'import fcntl, sys, time
admit, held = open(sys.argv[1], "a"), 0
for _ in range(500):
    try: fcntl.flock(admit, fcntl.LOCK_EX | fcntl.LOCK_NB); fcntl.flock(admit, fcntl.LOCK_UN)
    except BlockingIOError: held += 1
    time.sleep(0.01)
print(held)' "$root/locks/admit")
kill "$building"; wait "$building" "$first" 2>/dev/null
expect "a build claim waiting for a slot never takes the admit lock" "$held" "0"

slot_queue() {
    python3 -c 'import fcntl, sys, time
slot = open(sys.argv[1], "a")
fcntl.flock(slot, fcntl.LOCK_EX)
for holder in sys.argv[3:]:
    open(sys.argv[1], "w").write(holder + "\n")
    open(sys.argv[2], "w").close()
    time.sleep(2)' "$root/locks/build-1" "$root/holding" "$@" &
    building=$!
    for _ in $(seq 1 100); do [ -f "$root/holding" ] && break; sleep 0.1; done
}
reset
mkdir -p "$root/locks"
rm -f "$root/holding"
slot_queue "xcodebuild (pid 1)" "xcodebuild (pid 2)" "xcodebuild (pid 3)"
WORKOUT_BUILD_SLOTS=1 WORKOUT_ADMIT_WAIT=3 test_sim; status=$?
wait "$building"
expect "a build claim waits past WORKOUT_ADMIT_WAIT while the build slot keeps changing hands" "$status $(builds)" \
    "65 build-for-testing"
reset
mkdir -p "$root/locks"
rm -f "$root/holding"
slot_queue "xcodebuild (pid 1)" "xcodebuild (pid 1)" "xcodebuild (pid 1)"
WORKOUT_BUILD_SLOTS=1 WORKOUT_ADMIT_WAIT=3 test_sim; status=$?
wait "$building"
expect "and gives up once the slot stays with one holder for WORKOUT_ADMIT_WAIT" "$status $(refusal | sed 's/:.*//')" \
    "75 gave up after N s waiting for the host before taking $sim"

reset
STUB_SHUTDOWN=$sim STUB_BOOT_FAILS=raced test_sim --no-build; status=$?
expect "a boot that fails because another process booted the simulator goes on" "$status $(builds)" "65 test-without-building"
reset
STUB_SHUTDOWN=$sim STUB_BOOT_FAILS=booting test_sim --no-build; status=$?
expect "a boot that fails because another process is booting the simulator goes on" "$status $(builds)" "65 test-without-building"
reset
STUB_SHUTDOWN=$sim STUB_BOOT_FAILS=1 test_sim --no-build; status=$?
expect "a boot that fails leaves it shut down, exits 70, and says why" "$status $(builds) $(cat "$root/err")" \
    "70  could not boot $sim: Unable to boot device in current state: Booted"

reset
STUB_SHUTDOWN=$sim STUB_BOOT_HOLD=1 WORKOUT_BUILD_SLOTS=1 "$repo/scripts/test-sim.sh" --sim "$sim" unit >/dev/null 2>&1 &
first=$!
for _ in $(seq 1 100); do [ -f "$root/boot-holding" ] && break; sleep 0.1; done
kill -9 "$first"; wait "$first" 2>/dev/null
WORKOUT_BUILD_SLOTS=1 WORKOUT_ADMIT_WAIT=0 test_sim; status=$?
touch "$root/release"
expect "a claimer killed during its boot frees the simulator, the admit lock and its build slot at once" "$status $(builds)" \
    "65 build-for-testing"
expect "and leaves nothing but lock files in the host lock directory" "$(leftovers)" ""

reset
STUB_LIST_WARNING=1 WORKOUT_ADMIT_WAIT=0 test_sim --no-build; status=$?
expect "a warning simctl prints beside a good listing does not hold the claim" "$status $(builds)" "65 test-without-building"

reset
STUB_SHUTDOWN=$sim STUB_BOOTED_OTHERS=10 WORKOUT_ADMIT_WAIT=0 "$repo/scripts/test-sim.sh" --no-build unit >"$root/out" 2>"$root/err"; status=$?
expect "a claim the host refuses boots nothing" "$status $(cat "$root/xcrun-calls" 2>/dev/null)" "75 "
reset
STUB_SHUTDOWN=$sim STUB_BOOTED_OTHERS=9 test_sim --no-build; status=$?
expect "an admitted claim boots its shut-down simulator before the run" "$status $(cat "$root/xcrun-calls") $(builds)" \
    "65 simctl boot $sim test-without-building"
STUB_SHUTDOWN="$sim $sim2" STUB_BOOTED_OTHERS=9 WORKOUT_ADMIT_WAIT=0 \
    "$repo/scripts/test-sim.sh" --no-build --sim "$sim2" unit >"$root/out" 2>"$root/err"; status=$?
expect "the next claim counts a simulator the last claim booted" "$status $(refusal)" \
    "75 gave up after N s waiting for the host before taking $sim2: 10 other simulators are booted, at the cap of 10 (WORKOUT_SIM_CAP)"

printf '\npassed %d, failed %d\n' "$pass" "$fail"
[ "$fail" = 0 ]
