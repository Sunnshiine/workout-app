#!/bin/bash
set -uo pipefail

scripts=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
root=$(mktemp -d) || exit 3
root=$(cd "$root" && pwd -P)
P=SIMPOOL$$
holder=
cleanup() {
    [ -z "$holder" ] || kill "$holder" 2>/dev/null
    rm -rf "$root" /tmp/workout-verify-"$P"-*
}
trap cleanup EXIT
mkdir -p "$root/bin" "$root/home"
cp "$scripts/tests/fake-xcrun" "$root/bin/xcrun"
export PATH="$root/bin:$PATH" HOME="$root/home" WORKOUT_HOST_LOCK_DIR="$root/locks"
export FAKE_SIM_PREFIX=$P FAKE_SIM_STORE="$root/store.json" FAKE_SIM_CALLS="$root/calls"
runtime=com.apple.CoreSimulator.SimRuntime.iOS-27-0
build_calls="create workout-template-v1-building com.apple.CoreSimulator.SimDeviceType.iPhone-17-Pro $runtime
boot $P-1
bootstatus $P-1 -b
bootstatus $P-1 -b
spawn $P-1 defaults read com.apple.keyboard.preferences AutomaticMinimizationEnabled
spawn $P-1 defaults write com.apple.keyboard.preferences AutomaticMinimizationEnabled -bool false
spawn $P-1 defaults read com.apple.keyboard.preferences AutomaticMinimizationEnabled
shutdown $P-1
rename $P-1 workout-template-v1"
pass=0
fail=0

ok()  { pass=$((pass + 1)); printf '  ok   %s\n' "$1"; }
bad() { fail=$((fail + 1)); printf '  FAIL %s\n' "$1"; }

fresh() { rm -f "$root/store.json" "$root/calls"; }
seed() {
    xcrun simctl create "$1" 'iPhone 17 Pro' "$runtime" >/dev/null
    [ "${2:-}" != Booted ] || xcrun simctl boot "$(xcrun simctl list devices -j | python3 -c '
import json, sys
print([d["udid"] for ds in json.load(sys.stdin)["devices"].values() for d in ds][-1])')"
    rm -f "$root/calls"
}
pool() {
    rm -f "$root/calls"
    "$scripts/sim-pool.sh" "$@" >"$root/out" 2>"$root/err"
    status=$?
}
calls() { cat "$root/calls" 2>/dev/null; }
listing() { "$scripts/sim-pool.sh" list; }
expect() {
    if [ "$2" = "$3" ]; then
        ok "$1"
    else
        bad "$1"
        printf '    got:\n%s\n    want:\n%s\n    stderr:\n%s\n' "$2" "$3" "$(cat "$root/err")"
    fi
}
hold() {
    mkdir -p "$(dirname "$1")"
    python3 -c 'import fcntl, sys, time
f = open(sys.argv[1], "a")
fcntl.flock(f, fcntl.LOCK_EX)
open(sys.argv[1], "w").write(sys.argv[2] + "\n")
open(sys.argv[3], "w").close()
time.sleep(120)' "$1" "$2" "$root/held" &
    holder=$!
    while [ ! -f "$root/held" ]; do sleep 0.05; done
    rm -f "$root/held"
}
release() { kill "$holder"; wait "$holder" 2>/dev/null; holder=; }

fresh
pool create a
expect "create on a fresh Mac builds the template (boot, keyboard, shutdown, rename) and clones it Shutdown" \
    "$status $(cat "$root/out") | $(calls)" \
    "0 $P-2 | $build_calls
clone $P-1 workout-lane-a"
expect "list shows the lane and the template, and nothing booted" "$(listing)" \
    "UDID	STATE	ROLE	NAME
$P-2	Shutdown	lane	workout-lane-a
$P-1	Shutdown	template	workout-template-v1
booted: 0 of cap 6"

pool create a
expect "a second create prints the same UDID and clones nothing" "$status $(cat "$root/out") | $(calls)" "0 $P-2 | "

pool boot a
expect "boot boots the lane and prints its UDID" "$status $(cat "$root/out") | $(calls)" \
    "0 $P-2 | boot $P-2
bootstatus $P-2 -b"
expect "the lane carries the template's keyboard setting" \
    "$(xcrun simctl spawn "$P-2" defaults read com.apple.keyboard.preferences AutomaticMinimizationEnabled)" "0"

xcrun simctl boot "$P-1"
pool create b
expect "a booted template is shut down before the clone" "$status $(cat "$root/out") | $(calls)" \
    "0 $P-3 | shutdown $P-1
clone $P-1 workout-lane-b"

FAKE_SIM_CLONE_405_ONCE="$root/405" pool create c
expect "a clone refused with 405 is retried once" "$status $(cat "$root/out") | $(calls) | $(tail -1 "$root/err")" \
    "0 $P-4 | clone $P-1 workout-lane-c
clone $P-1 workout-lane-c | sim-pool: $P-1 booted before the clone; shutting it down and cloning again"

mkdir -p "/tmp/workout-verify-$P-3"
pool delete b
expect "delete removes the device and its verify dir" "$status $(calls) | $([ -d "/tmp/workout-verify-$P-3" ] && echo kept)" \
    "0 delete $P-3 | "
pool delete b
expect "a second delete exits 0 with a note" "$status $(cat "$root/err") | $(calls)" \
    "0 sim-pool: no device is named workout-lane-b; nothing to delete | "

hold "/tmp/workout-verify-$P-4/lock" "test-sim.sh unit (pid 4242)"
pool delete c
release
expect "delete while a run holds the simulator exits 75 and deletes nothing" \
    "$status $(cat "$root/err") | $(calls) | $(listing | grep -c "$P-4")" \
    "75 $P-4 is held by a test-sim.sh unit (pid 4242); wait for it to finish, or use another simulator (lsof /tmp/workout-verify-$P-4/lock lists every process holding it) |  | 1"

xcrun simctl boot "$P-4"
FAKE_SIM_SLOW_SHUTDOWN="$root/shutting" "$scripts/sim-pool.sh" delete c >"$root/out" 2>"$root/err" &
deleter=$!
while [ ! -f "$root/shutting" ]; do sleep 0.05; done
claim=$(bash -c '. "$1/sim-lock.sh" && claim_sim "$2" "test-sim.sh run" && echo claimed' _ "$scripts" "$P-4" 2>&1)
claim_status=$?
wait "$deleter"
status=$?
expect "a claim while delete shuts the simulator down exits 75, and the delete finishes" \
    "$claim_status $claim | $status $(listing | grep -c "$P-4")" \
    "75 $P-4 is held by a sim-pool.sh delete c (pid $deleter); wait for it to finish, or use another simulator (lsof /tmp/workout-verify-$P-4/lock lists every process holding it) | 0 0"

seed workout-lane-fx
python3 -c 'import time; time.sleep(60)' -UITEST_FIXTURE &
fixture=$!
mkdir -p "/tmp/workout-verify-$P-5"
echo "$fixture" >"/tmp/workout-verify-$P-5/pid"
echo run-7 >"/tmp/workout-verify-$P-5/run"
pool delete fx
kill "$fixture"
wait "$fixture" 2>/dev/null
expect "delete while a verify run's app is live exits 75 and deletes nothing" \
    "$status $(cat "$root/err") | $(calls) | $(listing | grep -c "$P-5")" \
    "75 sim-pool: a verify run run-7 owns the app on $P-5 (pid $fixture); if it is yours, run: SIM=$P-5 VERIFY_RUN=run-7 $(dirname "$scripts")/.agents/skills/verify/verify.sh stop, and delete again |  | 1"

for n in 1 2 3 4 5 6; do seed "iPhone 17 Pro $n" Booted; done
xcrun simctl shutdown "$P-2"
rm -f "$root/calls"
WORKOUT_ADMIT_WAIT=0 pool boot a
expect "boot with six others booted exits 75 and boots nothing" "$status $(cat "$root/err") | $(calls)" \
    "75 sim-pool: gave up booting $P-2 after 0 s: 6 other simulators are booted, at the cap of 6 (WORKOUT_SIM_CAP) | "
WORKOUT_SIM_CAP=7 pool boot a
expect "a cap of seven admits it" "$status $(cat "$root/out")" "0 $P-2"
expect "list counts every booted device on the host" "$(listing | tail -1)" "booted: 7 of cap 6"

fresh
seed workout-template-v1-building Booted
pool create a
expect "a -building device a crash left is deleted and the template rebuilt" "$status $(cat "$root/out") | $(calls)" \
    "0 $P-3 | shutdown $P-1
delete $P-1
${build_calls//$P-1/$P-2}
clone $P-2 workout-lane-a"

fresh
seed workout-template-v0
seed workout-lane-old
pool create a
expect "an older template is deleted after the new one is built, and its clones stay" "$status $(calls | tail -2) | $(listing)" \
    "0 delete $P-1
clone $P-3 workout-lane-a | UDID	STATE	ROLE	NAME
$P-4	Shutdown	lane	workout-lane-a
$P-2	Shutdown	lane	workout-lane-old
$P-3	Shutdown	template	workout-template-v1
booted: 0 of cap 6"

fresh
"$scripts/sim-pool.sh" create a >"$root/out-a" 2>&1 &
"$scripts/sim-pool.sh" create b >"$root/out-b" 2>&1 &
wait
expect "two concurrent creates on a fresh Mac build one template" \
    "$(grep -c '^create workout-template' "$root/calls") $(listing | sed '1d;$d' | cut -f3,4 | tr '\n\t' '  ')" \
    "1 lane workout-lane-a lane workout-lane-b template workout-template-v1 "

fresh
seed workout-lane-dup
seed workout-lane-dup
pool create dup
expect "two devices with a lane's name exit 70 and name both" "$status $(cat "$root/err")" \
    "70 sim-pool: 2 devices are named workout-lane-dup: $P-1 $P-2 delete all but one with xcrun simctl delete <UDID>"

pool boot nope
expect "boot of a lane with no device exits 1" "$status $(cat "$root/err")" \
    "1 sim-pool: no device is named workout-lane-nope; run scripts/sim-pool.sh create nope"

fresh
FAKE_SIM_NO_RUNTIME=1 pool create a
expect "a Mac without the iOS 27.0 runtime exits 69" "$status $(tail -1 "$root/err")" \
    "69 no available iOS 27.0 runtime. available: none"

hold "$root/locks/sim-pool" "sim-pool.sh create z (pid 4243)"
WORKOUT_ADMIT_WAIT=0 pool create a
release
expect "a held pool lock exits 75 and names the holder" "$status $(cat "$root/err") | $(calls)" \
    "75 sim-pool: waited 0 s for the pool lock, held by sim-pool.sh create z (pid 4243) (lsof $root/locks/sim-pool lists it) | "

pool create 'lane-x 1a2b3c4'
expect "a lane name with a space prints usage and exits 2" "$status $(head -1 "$root/err") | $(calls)" \
    "2 Usage: scripts/sim-pool.sh create <lane> | boot <lane> | delete <lane> | list | "
pool delete ../x
expect "a lane name with a slash exits 2" "$status" "2"
WORKOUT_SIM_CAP=0 pool boot a
expect "a cap of zero exits 2" "$status $(cat "$root/err")" \
    "2 sim-pool: WORKOUT_SIM_CAP must be a whole number of at least 1: 0"

printf '\npassed %s, failed %s\n' "$pass" "$fail"
[ "$fail" -eq 0 ] || exit 1
