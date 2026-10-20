#!/bin/bash
set -uo pipefail

# shellcheck source=scripts/tests/host-admission-harness.sh
. "$(dirname "${BASH_SOURCE[0]}")/host-admission-harness.sh"

reset
mkdir -p "$root/herd"
cat >"$root/herd/xcrun" <<STUB
#!/bin/sh
[ "\$*" = "simctl list devices available -j" ] || exec "$root/bin/xcrun" "\$@"
echo listed >> "$root/herd-listed"
[ "\$(wc -l < "$root/herd-listed")" -eq 2 ] || exec "$root/bin/xcrun" "\$@"
listing=\$("$root/bin/xcrun" "\$@")
touch "$root/release"
i=0
while [ ! -f "$root/booted" ] && [ \$i -lt 100 ]; do sleep 0.1; i=\$((i + 1)); done
printf '%s\\n' "\$listing"
STUB
chmod +x "$root/herd/xcrun"
rm -f "$root/herd-listed"
STUB_SHUTDOWN="$sim $sim2" STUB_BOOTED_OTHERS=9 STUB_BOOT_HOLD=1 test_sim --no-build &
first=$!
for _ in $(seq 1 100); do [ -f "$root/boot-holding" ] && break; sleep 0.1; done
PATH="$root/herd:$PATH" STUB_SHUTDOWN="$sim $sim2" STUB_BOOTED_OTHERS=9 WORKOUT_ADMIT_WAIT=0 \
    "$repo/scripts/test-sim.sh" --no-build --sim "$sim2" unit >/dev/null 2>"$root/err2"; status=$?
wait "$first"; status="$? $status"
expect "two claims that both counted 5 booted boot one simulator between them, not two" \
    "$status $(grep -c 'simctl boot' "$root/xcrun-calls")" "65 75 1"

reset; rm -f "$root/herd-listed"
STUB_SHUTDOWN="$sim $sim2" STUB_BOOTED_OTHERS=9 STUB_BOOT_HOLD=1 test_sim --no-build &
first=$!
for _ in $(seq 1 100); do [ -f "$root/boot-holding" ] && break; sleep 0.1; done
PATH="$root/herd:$PATH" STUB_SHUTDOWN="$sim $sim2" STUB_BOOTED_OTHERS=9 WORKOUT_BUILD_SLOTS=1 WORKOUT_ADMIT_WAIT=5 \
    "$repo/scripts/test-sim.sh" --sim "$sim2" unit >/dev/null 2>"$root/err2" &
second=$!
wait "$first"; rm -f "$root/builds"
for _ in $(seq 1 100); do grep -q "waiting up to" "$root/err2" 2>/dev/null && break; sleep 0.1; done
STUB_SHUTDOWN="$sim $sim2" STUB_BOOTED_OTHERS=9 WORKOUT_BUILD_SLOTS=1 WORKOUT_ADMIT_WAIT=0 test_sim; status=$?
wait "$second"
expect "a build claim the recount turns away gives its build slot back" "$status $(builds)" "65 build-for-testing"

reset
STUB_SHUTDOWN="$sim $sim2" STUB_BOOTED_OTHERS=9 STUB_BOOT_HOLD=1 test_sim --no-build &
first=$!
for _ in $(seq 1 100); do [ -f "$root/boot-holding" ] && break; sleep 0.1; done
STUB_SHUTDOWN="$sim $sim2" STUB_BOOTED_OTHERS=9 WORKOUT_ADMIT_WAIT=0 \
    "$repo/scripts/test-sim.sh" --no-build --sim "$sim2" unit >/dev/null 2>"$root/err2"; status=$?
touch "$root/release"; wait "$first"
expect "a claim holds the admit lock through its boot, so no other boot starts meanwhile" \
    "$status $(grep -c 'simctl boot' "$root/xcrun-calls") $(tail -1 "$root/err2" | sed 's/^gave up after [0-9]* s/gave up after N s/')" \
    "75 1 gave up after N s waiting for the host before taking $sim2: another claim is booting a simulator (lsof $root/locks/admit lists it)"

reset
mkdir -p "$root/locks"
python3 -c 'import fcntl, sys, time
admit = open(sys.argv[1], "a")
fcntl.flock(admit, fcntl.LOCK_EX)
open(sys.argv[2], "w").close()
time.sleep(30)' "$root/locks/admit" "$root/holding" &
admitting=$!
for _ in $(seq 1 100); do [ -f "$root/holding" ] && break; sleep 0.1; done
STUB_SHUTDOWN=$sim2 WORKOUT_BUILD_SLOTS=1 WORKOUT_ADMIT_WAIT=25 \
    "$repo/scripts/test-sim.sh" --sim "$sim2" unit >/dev/null 2>"$root/err2" &
first=$!
for _ in $(seq 1 100); do grep -q "waiting up to" "$root/err2" 2>/dev/null && break; sleep 0.1; done
held=$(python3 -c 'import fcntl, sys, time
slot, held = open(sys.argv[1], "a"), 0
for _ in range(400):
    try: fcntl.flock(slot, fcntl.LOCK_EX | fcntl.LOCK_NB); fcntl.flock(slot, fcntl.LOCK_UN)
    except BlockingIOError: held += 1
    time.sleep(0.01)
print(held)' "$root/locks/build-1")
kill "$admitting"; wait "$admitting" "$first" 2>/dev/null
expect "a build claim waiting for the admit lock holds its build slot for no more than a probe" \
    "$([ "$held" -lt 20 ] && echo "under 20 of 400 samples" || echo "$held of 400 samples")" "under 20 of 400 samples"

reset
STUB_SHUTDOWN=$sim2 STUB_SLOW_LIST_CALL=3 WORKOUT_BUILD_SLOTS=1 WORKOUT_ADMIT_WAIT=0 \
    "$repo/scripts/test-sim.sh" --sim "$sim2" unit >/dev/null 2>"$root/err2" &
first=$!
for _ in $(seq 1 100); do [ -f "$root/listing-slowly" ] && break; sleep 0.1; done
STUB_HOLD=1 WORKOUT_BUILD_SLOTS=1 WORKOUT_ADMIT_WAIT=0 test_sim &
second=$!
wait "$first"; status=$?
touch "$root/release"; wait "$second"; status="$status $?"
expect "a build claim takes its slot under the admit lock before it boots, so a build that starts meanwhile waits" \
    "$status $(grep -c 'simctl boot' "$root/xcrun-calls" 2>/dev/null)" "65 75 1"

reset
mkdir -p "$root/locks"
python3 -c 'import fcntl, sys, time
admit, build = open(sys.argv[1], "a"), open(sys.argv[2], "a")
fcntl.flock(admit, fcntl.LOCK_EX)
fcntl.flock(build, fcntl.LOCK_SH)
open(sys.argv[3], "w").close()
time.sleep(30)' "$root/locks/admit" "$root/locks/build-1" "$root/holding" &
admitting=$!
for _ in $(seq 1 100); do [ -f "$root/holding" ] && break; sleep 0.1; done
STUB_SHUTDOWN=$sim WORKOUT_BUILD_SLOTS=1 WORKOUT_ADMIT_WAIT=0 test_sim; status=$?
kill "$admitting"; wait "$admitting" 2>/dev/null
expect "a build claim waiting on a boot blames the boot, never another claim's slot probe" "$status $(refusal)" \
    "75 gave up after N s waiting for the host before taking $sim: another claim is booting a simulator (lsof $root/locks/admit lists it)"

went=0
for _ in 1 2 3 4 5; do
    reset
    STUB_PROBE_ON_LIST_CALL=2 WORKOUT_BUILD_SLOTS=1 WORKOUT_ADMIT_WAIT=0 test_sim
    [ $? != 65 ] || went=$((went + 1))
done
expect "a build on a booted simulator outlasts another claim's shared probe of its slot" "$went of 5" "5 of 5"

reset
STUB_SHUTDOWN=$sim STUB_SLOW_LIST_CALL=3 "$repo/scripts/test-sim.sh" --no-build --sim "$sim" unit >/dev/null 2>&1 &
first=$!
for _ in $(seq 1 100); do [ -f "$root/listing-slowly" ] && break; sleep 0.1; done
kill -9 "$first"; wait "$first" 2>/dev/null
STUB_SHUTDOWN="$sim $sim2" WORKOUT_ADMIT_WAIT=0 "$repo/scripts/test-sim.sh" --no-build --sim "$sim2" unit >/dev/null 2>"$root/err2"; status=$?
expect "a claimer killed during its listing under the admit lock frees it at once" "$status $(grep -c 'simctl boot' "$root/xcrun-calls")" "65 1"
expect "and leaves nothing but lock files in the host lock directory" "$(leftovers)" ""
sleep 3

reset
mkdir -p "$root/locks"
python3 -c 'import fcntl, sys, time
admit = open(sys.argv[1], "a")
fcntl.flock(admit, fcntl.LOCK_EX)
open(sys.argv[2], "w").close()
time.sleep(30)' "$root/locks/admit" "$root/holding" &
admitting=$!
for _ in $(seq 1 100); do [ -f "$root/holding" ] && break; sleep 0.1; done
STUB_SHUTDOWN=$sim WORKOUT_ADMIT_WAIT=0 test_sim --no-build; status=$?
expect "claims that boot a simulator are admitted one at a time" "$status $(refusal)" \
    "75 gave up after N s waiting for the host before taking $sim: another claim is booting a simulator (lsof $root/locks/admit lists it)"
WORKOUT_ADMIT_WAIT=0 test_sim --no-build; status=$?
expect "a claim on a booted simulator does not wait behind another claim's boot" "$status $(builds)" "65 test-without-building"
STUB_SHUTDOWN=$sim STUB_BOOTED_OTHERS=10 WORKOUT_ADMIT_WAIT=0 test_sim --no-build; status=$?
expect "a claim the cap refuses never waits for the admit lock" "$status $(refusal)" \
    "75 gave up after N s waiting for the host before taking $sim: 10 other simulators are booted, at the cap of 10 (WORKOUT_SIM_CAP)"
kill "$admitting"; wait "$admitting" 2>/dev/null

reset
STUB_LIST_GARBAGE_FROM_CALL=2 WORKOUT_ADMIT_WAIT=0 test_sim --no-build; status=$?
expect "a simulator listing that is no device list holds the claim" "$status $(refusal | sed 's/device list: .*/device list: .../')" \
    "75 gave up after N s waiting for the host before taking $sim: xcrun simctl list devices printed no device list: ..."
reset
PYTHONPROFILEIMPORTTIME=1 STUB_SHUTDOWN=$sim STUB_BOOTED_OTHERS=10 WORKOUT_ADMIT_WAIT=0 test_sim --no-build; status=$?
expect "what python prints on stderr never reaches the booted count, so the cap still holds" "$status $(refusal)" \
    "75 gave up after N s waiting for the host before taking $sim: 10 other simulators are booted, at the cap of 10 (WORKOUT_SIM_CAP)"
reset
STUB_LIST_OK_CALLS=1 WORKOUT_ADMIT_WAIT=0 test_sim --no-build; status=$?
expect "a simulator listing that fails holds the claim" "$status $(refusal)" \
    "75 gave up after N s waiting for the host before taking $sim: xcrun simctl list devices failed: An error was encountered processing the command (domain=com.apple.CoreSimulator.SimError, code=405)"

reset
WORKOUT_SIM_CAP=six test_sim --no-build; status=$?
expect "a knob that is not a whole number is a usage error" "$status $(cat "$root/err")" "2 WORKOUT_SIM_CAP must be a whole number: six"
reset
WORKOUT_BUILD_SLOTS=0 test_sim; status=$?
expect "zero build slots is a usage error, before any build" "$status $(builds) $(cat "$root/err")" "2  WORKOUT_BUILD_SLOTS must be at least 1: 0"

printf '\npassed %d, failed %d\n' "$pass" "$fail"
[ "$fail" = 0 ]
