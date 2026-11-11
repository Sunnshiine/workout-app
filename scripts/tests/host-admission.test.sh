#!/bin/bash
set -uo pipefail

# shellcheck source=scripts/tests/host-admission-harness.sh
. "$(dirname "${BASH_SOURCE[0]}")/host-admission-harness.sh"

age_minutes() { python3 -c 'import os, sys, time; t = time.time() - int(sys.argv[2]) * 60; os.utime(sys.argv[1], (t, t))' "$1" "$2"; }

own_the_app() {
    python3 -c 'import time; time.sleep(120)' -UITEST_FIXTURE &
    app=$!
    apps+=("$app")
    mkdir -p "$state"
    echo "$1" > "$state/run"
    echo "$app" > "$state/pid"
    echo "-UITEST_FIXTURE -UITEST_SESSION ${3--UITEST_DISABLE_LIVE_ACTIVITIES}" > "$state/args"
    age_minutes "$state/pid" "$2"
}

echo "lease"
reset; own_the_app abandoned-run 61
test_sim --no-build; status=$?
expect "a run unused for 61 min is reclaimed and the claim goes on" "$status $(builds)" "65 test-without-building"
expect "the reclaim names the run and its idle time" "$(head -1 "$root/err")" \
    "reclaimed $sim from verify run abandoned-run (pid $app): its lease was last renewed 61 min ago, and the lease is 60 min"
expect "the reclaim stops the abandoned run's app" "$(cat "$root/xcrun-calls" 2>/dev/null)" \
    "simctl terminate $sim com.sunnypatel.WorkoutTracker"

reset; own_the_app live-activity-run 61 ""
test_sim --no-build; status=$?
expect "a reclaimed run that had Live Activities on is uninstalled, as stop does" "$status $(cat "$root/xcrun-calls" | tr '\n' ' ')" \
    "65 simctl terminate $sim com.sunnypatel.WorkoutTracker simctl uninstall $sim com.sunnypatel.WorkoutTracker "

reset; own_the_app lane-short 2
WORKOUT_LEASE_MINUTES=1 test_sim --no-build; status=$?
expect "WORKOUT_LEASE_MINUTES sets the lease" "$status $(head -1 "$root/err")" \
    "65 reclaimed $sim from verify run lane-short (pid $app): its lease was last renewed 2 min ago, and the lease is 1 min"

reset; own_the_app active-run 59
test_sim --no-build; status=$?
expect "a run used 59 min ago refuses, before any xcodebuild" "$status $(builds)" "75 "
expect "the refusal says when it frees and how its owner takes it" "$(cat "$root/err")" \
    "a verify run active-run owns the app on $sim (pid $app), last used 59 min ago; a claim takes it once it goes 60 min unused. If it is yours, rerun with VERIFY_RUN=active-run or run: SIM=$sim VERIFY_RUN=active-run $repo/.agents/skills/verify/verify.sh stop, else use another simulator"

reset; own_the_app lane-812 5
VERIFY_RUN=lane-812 test_sim --no-build; status=$?
expect "the run's own owner takes its live app" "$status $(builds)" "65 test-without-building"
expect "the takeover says so" "$(head -1 "$root/err")" \
    "taking over the app of your own verify run lane-812 on $sim (pid $app)"

reset; own_the_app lane-812 5
VERIFY_RUN=lane-812 STUB_MEM_LEVEL=12 WORKOUT_ADMIT_WAIT=0 test_sim --no-build; status=$?
expect "a takeover the host refuses leaves the run's app recorded and announces nothing" \
    "$status $(ls "$state" | tr '\n' ' ')$(grep -c "taking over" "$root/err")" "75 args lock pid run 0"
reset; own_the_app lane-812 5 ""
VERIFY_RUN=lane-812 FAKE_HOSTGATE_GIVE_UP=1 test_sim; status=$?
expect "a takeover whose build hostgate refuses exits 75 before any xcodebuild" "$status $(builds)" "75 "
reset; own_the_app abandoned-run 61
STUB_MEM_LEVEL=12 WORKOUT_ADMIT_WAIT=0 test_sim --no-build; status=$?
expect "a reclaim the host refuses leaves the abandoned run recorded" "$status $(ls "$state" | tr '\n' ' ')" "75 args lock pid run "
reset; own_the_app abandoned-run 61
FAKE_HOSTGATE_GIVE_UP=1 test_sim; status=$?
test_sim --no-build; status="$status $?"
expect "a reclaim refused at the build slot leaves the run to the next claim, which reclaims it" \
    "$status $(grep -c 'owns the app' "$root/err")" "75 65 0"

echo "load_clear, which judges a verify.sh record take"
load_wait() { WORKOUT_ADMIT_WAIT=0 bash -c '. "$1/scripts/sim-lock.sh"; wait_until_clear "the load" load_clear "$2"' _ "$repo" "$1" 2>"$root/err"; }
reset
STUB_LOAD=80.00 load_wait 50; status=$?
expect "a load over the limit holds" "$status $(refusal)" \
    "75 gave up after N s waiting for the load: the 1-minute load is 80.00, over 50 (WORKOUT_LOAD_LIMIT)"
STUB_LOAD=50.00 load_wait 50; status=$?
expect "a load exactly at the limit is under it" "$status $(cat "$root/err")" "0 "
mkdir -p "$root/broken-awk"
printf '#!/bin/sh\necho "awk: cannot run" >&2\nexit 2\n' > "$root/broken-awk/awk"
chmod +x "$root/broken-awk/awk"
PATH="$root/broken-awk:$PATH" STUB_LOAD=1.00 load_wait 50; status=$?
expect "an awk that cannot compare the load holds, it never clears" "$status $(refusal)" \
    "75 gave up after N s waiting for the load: awk could not compare the 1-minute load 1.00 with 50 (exit 2)"
STUB_LOAD=n/a load_wait 50; status=$?
expect "a load reading that is not a number holds" "$status $(refusal)" \
    "75 gave up after N s waiting for the load: sysctl -n vm.loadavg printed no 1-minute load: { n/a 1.00 1.00 }"
STUB_SYSCTL_FAILS=1 load_wait 50; status=$?
expect "on macOS a sysctl that fails holds" "$status $(refusal)" \
    "75 gave up after N s waiting for the load: sysctl -n vm.loadavg failed: sysctl: unknown oid 'vm.loadavg'"
if gawk=$(command -v gawk); then
    mkdir -p "$root/gawk"
    ln -s "$gawk" "$root/gawk/awk"
    PATH="$root/gawk:$PATH" STUB_LOAD=80.00 load_wait 50; status=$?
    expect "under gawk, a load over the limit holds" "$status $(refusal)" \
        "75 gave up after N s waiting for the load: the 1-minute load is 80.00, over 50 (WORKOUT_LOAD_LIMIT)"
    PATH="$root/gawk:$PATH" STUB_LOAD=80.00 load_wait 100; status=$?
    expect "under gawk, a load under the limit clears and says nothing" "$status $(cat "$root/err")" "0 "
else
    echo "  skip the gawk checks: no gawk on PATH (brew install gawk)"
fi

echo "disk"
reset
STUB_DISK_FREE_MB=1000 WORKOUT_ADMIT_WAIT=0 test_sim; status=$?
expect "free disk under the floor refuses a build with 75, before any xcodebuild" "$status $(builds)" "75 "
expect "the refusal names the free and needed space and the knob" "$(refusal)" \
    "gave up after N s waiting for the host before running on $sim: free disk is 1000 MB on the volume holding $repo, under the floor of 5120 MB (WORKOUT_DISK_FLOOR) a build needs"
reset
STUB_DISK_FREE_MB=1000 STUB_LOW_DISK_PATH=$HOME WORKOUT_ADMIT_WAIT=0 test_sim; status=$?
expect "free disk under the floor on HOME's volume alone refuses the build and names HOME" "$status $(builds) $(refusal)" \
    "75  gave up after N s waiting for the host before running on $sim: free disk is 1000 MB on the volume holding $HOME, under the floor of 5120 MB (WORKOUT_DISK_FLOOR) a build needs"
reset
STUB_DISK_FREE_MB=5120 WORKOUT_ADMIT_WAIT=0 test_sim; status=$?
expect "free disk exactly at the floor is admitted" "$status $(builds)" "65 build-for-testing"
reset
STUB_DISK_FREE_MB=1000 WORKOUT_ADMIT_WAIT=0 test_sim --no-build; status=$?
expect "a run that builds nothing does not read the disk" "$status $(builds) $(cat "$root/df-calls" 2>/dev/null)" \
    "65 test-without-building "
reset
STUB_DISK_FREE_MB=1000 STUB_LOW_DISK_CALLS=1 WORKOUT_ADMIT_WAIT=30 test_sim; status=$?
expect "a build waits for disk to free, then goes on" "$status $(builds) $(head -1 "$root/err")" \
    "65 build-for-testing waiting up to 30 s for the host before running on $sim: free disk is 1000 MB on the volume holding $repo, under the floor of 5120 MB (WORKOUT_DISK_FLOOR) a build needs"
reset
STUB_DISK_FREE_MB=1000 WORKOUT_DISK_FLOOR=500 WORKOUT_ADMIT_WAIT=0 test_sim; status=$?
expect "WORKOUT_DISK_FLOOR lowers the floor" "$status $(builds)" "65 build-for-testing"
reset
STUB_DISK_FREE_MB=0 WORKOUT_DISK_FLOOR=0 WORKOUT_ADMIT_WAIT=0 test_sim; status=$?
expect "a floor of 0 never reads the disk" "$status $(cat "$root/df-calls" 2>/dev/null)" "65 "
reset
(cd "$repo" && STUB_DISK_FREE_MB=1000 WORKOUT_ADMIT_WAIT=0 "$repo/scripts/build-slot.sh" sh -c 'echo ran' >"$root/out" 2>"$root/err"); status=$?
expect "build-slot.sh refuses its command the same way, before hostgate" "$status $(cat "$root/out")$(refusal)" \
    "75 gave up after N s waiting for free disk: free disk is 1000 MB on the volume holding $repo, under the floor of 5120 MB (WORKOUT_DISK_FLOOR) a build needs"
reset
mkdir -p "$root/elsewhere"
STUB_DISK_FREE_MB=1000 STUB_LOW_DISK_PATH=$root/elsewhere WORKOUT_ADMIT_WAIT=0 "$repo/scripts/disk-floor.sh" "$root/elsewhere" 2>"$root/err"; status=$?
expect "disk-floor.sh DIR reads DIR's volume in place of the checkout's" "$status $(refusal)" \
    "75 gave up after N s waiting for free disk: free disk is 1000 MB on the volume holding $root/elsewhere, under the floor of 5120 MB (WORKOUT_DISK_FLOOR) a build needs"
"$repo/scripts/disk-floor.sh" a b 2>/dev/null; status=$?
"$repo/scripts/disk-floor.sh" --dir 2>/dev/null
expect "disk-floor.sh refuses two dirs or an option with 2" "$status $?" "2 2"
mkdir -p "$root/broken-df"
printf '#!/bin/sh\necho "df: $2: No such file or directory" >&2\nexit 1\n' >"$root/broken-df/df"
chmod +x "$root/broken-df/df"
reset
PATH="$root/broken-df:$PATH" WORKOUT_ADMIT_WAIT=0 test_sim; status=$?
expect "a df that fails holds the build" "$status $(refusal)" \
    "75 gave up after N s waiting for the host before running on $sim: df -Pk $repo failed: df: $repo: No such file or directory"

echo "help"
missing=
for knob in $(sed -n 's/^host_knob \([A-Z_]*\) .*/\1/p' "$repo/scripts/sim-lock.sh"); do
    for script in "$repo/.agents/skills/verify/verify.sh" "$repo/scripts/test-sim.sh"; do
        case $("$script" --help 2>&1) in *"$knob"*) ;; *) missing="$missing${missing:+, }$knob in ${script##*/}" ;; esac
    done
done
expect "verify.sh --help and test-sim.sh --help name every host knob sim-lock.sh reads" "${missing:-none missing}" "none missing"

printf '\npassed %d, failed %d\n' "$pass" "$fail"
[ "$fail" = 0 ]
