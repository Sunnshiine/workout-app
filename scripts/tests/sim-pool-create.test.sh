#!/bin/bash
set -uo pipefail

# shellcheck source=scripts/tests/sim-pool-harness.sh
. "$(dirname "${BASH_SOURCE[0]}")/sim-pool-harness.sh"

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
find "$scripts" -maxdepth 1 -type f -exec cp {} "$root/broken/" \;
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

store() { printf '/private/var/tmp/com.apple.CoreSimulator.SimDevice.%s/disabled.plist' "$1"; }
entries() { python3 -c 'import plistlib, sys
for label, off in sorted(plistlib.load(open(sys.argv[1], "rb")).items()): print(label, off)' "$(store "$1")"; }
jobs=$(sed 's/#.*//' "$scripts/sim-pool-disabled-jobs.txt" | awk 'NF { print $1 " True" }' | LC_ALL=C sort)

fresh
pool create a
expect "create marks every job in sim-pool-disabled-jobs.txt disabled in the new lane's launchd disable list" \
    "$status $(entries "$(cat "$root/out")")" "0 $jobs"

seed workout-lane-b
udid=$(listing | awk -F '\t' '$4 == "workout-lane-b" { print $1 }')
mkdir -p "$(dirname "$(store "$udid")")"
python3 -c 'import plistlib, sys
plistlib.dump({"com.apple.pairedsyncd": False, "com.apple.PosterBoard": False}, open(sys.argv[1], "wb"))' "$(store "$udid")"
pool create b
expect "create on an existing lane disables the jobs too, and keeps the runtime's own entries for other jobs" \
    "$status $(entries "$udid" | grep -E '^com.apple.(pairedsyncd|PosterBoard) ') $(entries "$udid" | grep -c ' True$')" \
    "0 com.apple.PosterBoard True
com.apple.pairedsyncd False $(printf '%s\n' "$jobs" | grep -c .)"

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
