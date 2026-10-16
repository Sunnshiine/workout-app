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
cat >"$root/bin/sysctl" <<'STUB'
#!/bin/bash
[ "$2" = kern.memorystatus_level ] && echo "${STUB_MEM_LEVEL:-80}" || echo "{ ${STUB_LOAD:-1.00} 1.00 1.00 }"
STUB
cat >"$root/bin/pgrep" <<'STUB'
#!/bin/bash
[ "$1" = -f ] || exec /usr/bin/pgrep "$@"
[ -f "${STUB_APPS:-}" ] || exit 1
found=1
while read -r pid cmd; do
    printf '%s\n' "$cmd" | grep -qE -- "$2" && { echo "$pid"; found=0; }
done <"$STUB_APPS"
exit $found
STUB
chmod +x "$root/bin/sysctl" "$root/bin/pgrep"
export PATH="$root/bin:$PATH" HOME="$root/home" WORKOUT_HOST_LOCK_DIR="$root/locks"
unset WORKOUT_SIM_CAP WORKOUT_MEM_FLOOR WORKOUT_ADMIT_WAIT WORKOUT_BUILD_SLOTS WORKOUT_LEASE_MINUTES WORKOUT_IDLE_MINUTES STUB_APPS
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
refusal() { sed 's/^gave up after [0-9]* s/gave up after N s/' "$root/err"; }
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
cp "$scripts/test-sim.sh" "$scripts/sim-lock.sh" "$root/repo/scripts/"
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

fresh
STUB_MEM_LEVEL=12 WORKOUT_ADMIT_WAIT=0 pool create a
expect "the template build under the memory floor exits 75 before its boot, leaving the -building device Shutdown" \
    "$status $(refusal | tail -1) | $(calls) | $(listing | awk -F '\t' '$3 == "building" { print $2 }')" \
    "75 gave up after N s waiting for the host before booting $P-1: free memory is 12%, under the floor of 25% (WORKOUT_MEM_FLOOR) | create workout-template-v1-building com.apple.CoreSimulator.SimDeviceType.iPhone-17-Pro $runtime | Shutdown"
pool create a
expect "the next create finishes that Shutdown -building device instead of deleting it" "$status $(cat "$root/out") | $(calls)" \
    "0 $P-2 | ${build_calls#*$'\n'}
clone $P-1 workout-lane-a"

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
booted: 0 of cap 10"

fresh
seed workout-template-v2
pool create a
expect "a newer recipe's template survives an older script, which builds and clones its own" \
    "$status $(calls | grep -c '^delete') $(calls | tail -1) | $(listing)" \
    "0 0 clone $P-2 workout-lane-a | UDID	STATE	ROLE	NAME
$P-3	Shutdown	lane	workout-lane-a
$P-2	Shutdown	template	workout-template-v1
$P-1	Shutdown	newer-template	workout-template-v2
booted: 0 of cap 10"

fresh
seed workout-template-v2
pool create a
seed workout-template-v1-building
pool delete-template
expect "delete-template deletes this recipe's template and a crashed build, and leaves lanes and a newer recipe's template" \
    "$status $(calls) | $(listing)" \
    "0 delete $P-2
delete $P-4 | UDID	STATE	ROLE	NAME
$P-3	Shutdown	lane	workout-lane-a
$P-1	Shutdown	newer-template	workout-template-v2
booted: 0 of cap 10"
pool delete-template
expect "a second delete-template exits 0 with a note" "$status $(cat "$root/err") | $(calls)" \
    "0 sim-pool: no workout-template-v1 to delete | "
pool create b
expect "create after delete-template builds the template again" "$status $(calls | grep -c '^create workout-template-v1-building')" "0 1"

fresh
mkdir "$root/broken"
cp "$scripts/sim-pool.sh" "$scripts/sim-lock.sh" "$scripts/ensure-simulator.sh" "$root/broken/"
printf '#!/bin/bash\necho "keyboard: cannot read it" >&2\nexit 70\n' >"$root/broken/sim-keyboard.sh"
chmod +x "$root/broken/sim-keyboard.sh"
"$root/broken/sim-pool.sh" create a >"$root/out" 2>"$root/err"
expect "a template build that fails after booting exits 70 and deletes the booted half-built device" \
    "$? $(tail -1 "$root/err") | $(calls | tail -2 | tr '\n' ' ')| $(listing)" \
    "70 sim-pool: scripts/sim-keyboard.sh ensure $P-1 failed; deleting $P-1, the workout-template-v1-building that failed, so it holds no seat of the cap | shutdown $P-1 delete $P-1 | UDID	STATE	ROLE	NAME
booted: 0 of cap 10"

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

WORKOUT_SIM_CAP=0 pool --help
expect "--help prints the usage on stdout and exits 0, even beside a bad setting" "$status $(head -1 "$root/out") | $(cat "$root/err")" \
    "0 Usage: scripts/sim-pool.sh create <lane> | boot <lane> | delete <lane> | delete-template | list | "
pool create 'lane-x 1a2b3c4'
expect "a lane name with a space prints usage and exits 2" "$status $(head -1 "$root/err") | $(calls)" \
    "2 Usage: scripts/sim-pool.sh create <lane> | boot <lane> | delete <lane> | delete-template | list | "
pool delete ../x
expect "a lane name with a slash exits 2" "$status" "2"
WORKOUT_SIM_CAP=0 pool boot a
expect "a cap of zero exits 2" "$status $(cat "$root/err")" \
    "2 WORKOUT_SIM_CAP must be at least 1: 0"

printf '\npassed %s, failed %s\n' "$pass" "$fail"
[ "$fail" -eq 0 ] || exit 1
