#!/bin/bash
set -uo pipefail

# shellcheck source=scripts/tests/sim-pool-harness.sh
. "$(dirname "${BASH_SOURCE[0]}")/sim-pool-harness.sh"

used() {
    mkdir -p "/tmp/workout-verify-$1"
    touch "/tmp/workout-verify-$1/lock"
    python3 -c 'import os, sys, time; t = time.time() - int(sys.argv[2]) * 60; os.utime(sys.argv[1], (t, t))' "/tmp/workout-verify-$1/lock" "$2"
}
minutes_old() { python3 -c 'import os, sys, time; print(int((time.time() - os.stat(sys.argv[1]).st_mtime) // 60))' "$1"; }
# Six booted at the cap of six these tests set: four other devices last used 60 min ago, and two lanes, $P-5 used 5 min ago
# and $P-6 30 min ago, so $P-6 is the least recently used lane. $P-7 is the Shutdown lane to boot.
crowd() {
    fresh
    rm -rf /tmp/workout-verify-"$P"-*
    for n in 1 2 3 4; do seed "iPhone 17 Pro $n" Booted; used "$P-$n" 60; done
    seed workout-lane-recent Booted; used "$P-5" 5
    seed workout-lane-stale Booted; used "$P-6" 30
    seed workout-lane-next
}
reclaimed() { printf 'shut down idle lane workout-lane-%s (%s) to free a seat: 6 other simulators are booted, at the cap of 6 (WORKOUT_SIM_CAP), and it held no run or app for %s min (WORKOUT_IDLE_MINUTES is 2)' "$1" "$2" "$3"; }

fresh
FAKE_SIM_HELD_FDS="$root/held-fds" pool create a
expect "create on a fresh Mac builds the template (boot, keyboard, shutdown, rename) and clones it Shutdown" \
    "$status $(cat "$root/out") | $(calls)" \
    "0 $P-2 | $build_calls
clone $P-1 workout-lane-a"
expect "the template's simctl create and boot hold no lock fd, so a boot outliving a killed create holds no pool lock" \
    "$(cat "$root/held-fds")" "create workout-template-v1-building holds fds:
boot $P-1 holds fds:"
expect "list shows the lane and the template, and nothing booted" "$(listing)" \
    "UDID	STATE	ROLE	NAME
$P-2	Shutdown	lane	workout-lane-a
$P-1	Shutdown	template	workout-template-v1
booted: 0 of cap 10"

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
for _ in $(seq 100); do [ ! -f "$root/shutting" ] || break; sleep 0.05; done
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
WORKOUT_SIM_CAP=6 WORKOUT_ADMIT_WAIT=0 pool boot a
expect "boot with six others booted at a cap of six exits 75 and boots nothing" "$status $(refusal) | $(calls)" \
    "75 gave up after N s waiting for the host before booting $P-2: 6 other simulators are booted, at the cap of 6 (WORKOUT_SIM_CAP) | "
pool boot a
expect "the default cap of ten admits it" "$status $(cat "$root/out")" "0 $P-2"
expect "list counts every booted device on the host" "$(listing | tail -1)" "booted: 7 of cap 10"

echo "idle seats"
export WORKOUT_SIM_CAP=6
crowd
WORKOUT_ADMIT_WAIT=0 pool boot next
expect "at the cap, boot shuts down the least recently used idle lane, never another device, then boots" \
    "$status $(cat "$root/out") | $(calls | tr '\n' ' ')| $(cat "$root/err")" \
    "0 $P-7 | shutdown $P-6 boot $P-7 bootstatus $P-7 -b | $(reclaimed stale "$P-6" 30)"
crowd
hold "/tmp/workout-verify-$P-6/lock" "test-sim.sh unit (pid 4242)"
WORKOUT_ADMIT_WAIT=0 pool boot next
release
expect "a lane whose lock a run holds is skipped for the next idle one" "$status $(calls | head -1)" "0 shutdown $P-5"
crowd
python3 -c 'import time; time.sleep(60)' -UITEST_FIXTURE &
fixture=$!
echo "$fixture" >"/tmp/workout-verify-$P-6/pid"
echo run-9 >"/tmp/workout-verify-$P-6/run"
printf '%s /Users/t/Library/Developer/CoreSimulator/Devices/%s/data/Containers/Bundle/Application/A/WorkoutTracker.app/WorkoutTracker\n' \
    "$fixture" "$P-6" >"$root/apps"
STUB_APPS=$root/apps WORKOUT_ADMIT_WAIT=0 pool boot next
expect "a lane whose verify app is inside its lease is skipped" "$status $(calls | head -1)" "0 shutdown $P-5"
crowd
echo "$fixture" >"/tmp/workout-verify-$P-6/pid"
echo run-9 >"/tmp/workout-verify-$P-6/run"
python3 -c 'import os, sys, time; t = time.time() - 61 * 60; os.utime(sys.argv[1], (t, t))' "/tmp/workout-verify-$P-6/pid"
STUB_APPS=$root/apps WORKOUT_ADMIT_WAIT=0 pool boot next
expect "a lane whose verify app outlived its lease is reclaimed, and that run is told who took it" \
    "$status $(calls | head -2 | tr '\n' ' ')| $(head -1 "$root/err") | $(sed 's/(pid [0-9]*) at .*/(pid N) at T/' "/tmp/workout-verify-$P-6/reclaimed.run-9")" \
    "0 terminate $P-6 com.sunnypatel.WorkoutTracker shutdown $P-6 | reclaimed $P-6 from verify run run-9 (pid $fixture): its lease was last renewed 61 min ago, and the lease is 60 min | sim-pool.sh, freeing a seat (pid N) at T"
kill "$fixture"; wait "$fixture" 2>/dev/null
crowd
printf '4242 /Users/t/Library/Developer/CoreSimulator/Devices/%s/data/Containers/Bundle/Application/A/Other.app/Other\n' "$P-6" >"$root/apps"
STUB_APPS=$root/apps WORKOUT_ADMIT_WAIT=0 pool boot next
expect "a lane with an app running on it, as after an XcodeBuildMCP launch, is skipped" "$status $(calls | head -1)" "0 shutdown $P-5"
crowd
printf '4243 /Users/t/Library/Developer/CoreSimulator/Devices/%s/data/Containers/Bundle/Application/A/WorkoutTracker.app/PlugIns/WorkoutWidgets.appex/WorkoutWidgets -BSServiceDomains x\n' "$P-6" >"$root/apps"
STUB_APPS=$root/apps WORKOUT_ADMIT_WAIT=0 pool boot next
expect "a lane whose only process is a widget extension, which outlives its app, is reclaimed" "$status $(calls | head -1)" "0 shutdown $P-6"
crowd
printf '4244 /Users/t/Library/Developer/CoreSimulator/Devices/%s/data/Containers/Bundle/Application/B/WorkoutTrackerUITests-Runner.app/WorkoutTrackerUITests-Runner\n' "$P-6" >"$root/apps"
STUB_APPS=$root/apps WORKOUT_ADMIT_WAIT=0 pool boot next
expect "a lane running a UI test runner is skipped" "$status $(calls | head -1)" "0 shutdown $P-5"
crowd
rm "/tmp/workout-verify-$P-6/lock"
WORKOUT_ADMIT_WAIT=0 pool boot next
expect "a lane with no lock file has no idle clock, so it is skipped" "$status $(calls | head -1)" "0 shutdown $P-5"
crowd
mkdir -p "$root/repo/scripts"
cp "$scripts/test-sim.sh" "$scripts/sim-lock.sh" "$scripts/compile-cache.sh" "$root/repo/scripts/"
printf '#!/bin/sh\npython3 -c %s "/tmp/workout-verify-%s/lock"\nexit 65\n' \
    "'import os, sys, time; t = time.time() - 30 * 60; os.utime(sys.argv[1], (t, t))'" "$P-6" >"$root/bin/xcodebuild"
chmod +x "$root/bin/xcodebuild"
"$root/repo/scripts/test-sim.sh" --sim "$P-6" unit >/dev/null 2>&1
rm "$root/bin/xcodebuild"
WORKOUT_ADMIT_WAIT=0 pool boot next
expect "a lane whose run ended inside WORKOUT_IDLE_MINUTES is not reclaimed, though the run took it long before" \
    "$status $(calls | head -1)" "0 shutdown $P-5"
crowd
hold "$root/locks/build-1" "xcodebuild (pid 4245)"
WORKOUT_BUILD_SLOTS=1 WORKOUT_ADMIT_WAIT=0 bash -c '. "$1/sim-lock.sh" && claim_sim "$2" "test-sim.sh run" 1' _ "$scripts" "$P-7" \
    >"$root/out" 2>"$root/err"; status=$?
release
expect "a build claim at the cap with every build slot taken shuts no idle lane down for a seat it cannot use yet" \
    "$status $(calls | grep -c shutdown)" "75 0"
crowd
used "$P-5" 1; used "$P-6" 1
WORKOUT_ADMIT_WAIT=0 pool boot next
expect "with every lane used inside WORKOUT_IDLE_MINUTES, boot at the cap still exits 75 and shuts nothing down" \
    "$status $(refusal) | $(calls)" \
    "75 gave up after N s waiting for the host before booting $P-7: 6 other simulators are booted, at the cap of 6 (WORKOUT_SIM_CAP) | "
WORKOUT_IDLE_MINUTES=1 WORKOUT_ADMIT_WAIT=0 pool boot next
expect "WORKOUT_IDLE_MINUTES sets how long a lane goes unused before it is idle" "$status $(calls | head -1)" "0 shutdown $P-6"
crowd
rm -f "$root/shutting"
FAKE_SIM_SLOW_SHUTDOWN="$root/shutting" WORKOUT_ADMIT_WAIT=0 "$scripts/sim-pool.sh" boot next >"$root/out" 2>"$root/err" &
booter=$!
for _ in $(seq 100); do [ ! -f "$root/shutting" ] || break; sleep 0.05; done
claim=$(WORKOUT_ADMIT_WAIT=0 bash -c '. "$1/sim-lock.sh" && claim_sim "$2" "test-sim.sh run" && echo claimed' _ "$scripts" "$P-6" 2>&1)
claim_status=$?
wait "$booter"
expect "a claim on the lane while its seat is reclaimed exits 75, and the boot goes on" \
    "$claim_status $claim | $?" \
    "75 $P-6 is held by a sim-pool.sh, freeing a seat (pid $booter); wait for it to finish, or use another simulator (lsof /tmp/workout-verify-$P-6/lock lists every process holding it) | 0"
crowd
used "$P-7" 30
WORKOUT_ADMIT_WAIT=0 pool boot next
expect "boot starts the lane's idle clock, since a raw xcodebuild after it takes no lock" \
    "$status $(minutes_old "/tmp/workout-verify-$P-7/lock")" "0 0"
used "$P-7" 30
WORKOUT_ADMIT_WAIT=0 pool boot next
expect "and restarts it on a lane already booted" "$status $(calls) $(minutes_old "/tmp/workout-verify-$P-7/lock")" "0 bootstatus $P-7 -b 0"
unset WORKOUT_SIM_CAP

fresh
seed workout-lane-load
STUB_MEM_LEVEL=12 WORKOUT_ADMIT_WAIT=0 pool boot load
expect "boot with free memory under the floor exits 75, names it, and boots nothing" "$status $(refusal) | $(calls)" \
    "75 gave up after N s waiting for the host before booting $P-1: free memory is 12%, under the floor of 25% (WORKOUT_MEM_FLOOR) | "
STUB_LOAD=212.40 STUB_MEM_LEVEL=12 WORKOUT_MEM_FLOOR=10 pool boot load
expect "the 1-minute load holds no boot, and WORKOUT_MEM_FLOOR lowers the floor" "$status $(cat "$root/out")" "0 $P-1"
xcrun simctl shutdown "$P-1"
hold "$root/locks/admit" "test-sim.sh run (pid 4244)"
WORKOUT_ADMIT_WAIT=0 pool boot load
release
expect "boot waits while a test-sim or verify claim holds the host's admit lock" "$status $(refusal) | $(calls)" \
    "75 gave up after N s waiting for the host before booting $P-1: another claim is booting a simulator (lsof $root/locks/admit lists it) | "
xcrun simctl boot "$P-1"
STUB_MEM_LEVEL=12 WORKOUT_ADMIT_WAIT=0 pool boot load
expect "boot of a lane already booted does not wait for memory" "$status $(cat "$root/out")" "0 $P-1"

printf '\npassed %s, failed %s\n' "$pass" "$fail"
[ "$fail" -eq 0 ] || exit 1
