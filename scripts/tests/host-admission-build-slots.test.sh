#!/bin/bash
# Every heavy build runs in a host-wide hostgate slot (scripts/build-slot.sh), with the harness's fake
# hostgate (fake-hostgate) standing in for the real one. hostgate's own tests cover the slots.
set -uo pipefail

# shellcheck source=scripts/tests/host-admission-harness.sh
. "$(dirname "${BASH_SOURCE[0]}")/host-admission-harness.sh"

build_slot() { "$repo/scripts/build-slot.sh" "$@" >"$root/out" 2>"$root/err"; }
# PATH with no hostgate on it, as on a CI runner; the harness's other stubs stay.
no_hostgate() {
    mv "$root/bin/hostgate" "$root/hostgate.off"
    PATH=$(printf '%s' "$PATH" | tr ':' '\n' | while IFS= read -r d; do [ -x "$d/hostgate" ] || printf '%s:' "$d"; done | sed 's/:$//') "$@"
    local status=$?
    mv "$root/hostgate.off" "$root/bin/hostgate"
    return $status
}
install_line="gh api -H 'Accept: application/vnd.github.raw' repos/Sunnshiine/hostgate/contents/install | sh"

echo "test-sim.sh"
reset
test_sim; status=$?
expect "the build runs in a slot labelled workout-app:test-sim.sh, and the test run in none" "$status $(builds) | $(slots)" \
    "65 build-for-testing | label=workout-app:test-sim.sh wait=- nested=no xcodebuild build-for-testing"
reset
FAKE_HOSTGATE_SAY="hostgate: waiting up to 540 s for a slot" test_sim
expect "hostgate's wait lines reach stderr, not the build log" \
    "$(grep -c 'waiting up to 540 s' "$root/err") $(cat "$repo"/.build/test-sim/*-build.log | grep -c 'waiting up to')" "1 0"
reset
FAKE_HOSTGATE_GIVE_UP=1 test_sim; status=$?
expect "a build hostgate gives up on exits 75 before any xcodebuild, not as a build failure" \
    "$status $(builds) $(grep -c 'build log' "$root/err")" "75  0"
expect "and its give-up line is the refusal" "$(grep -m1 '^hostgate:' "$root/err")" \
    "hostgate: gave up waiting for a slot held by workout-app:neighbour"
expect "then one line names the next step" "$(grep -c 'no host-wide build slot came free in time.*hostgate status.*WORKOUT_ADMIT_WAIT' "$root/err")" "1"
reset
WORKOUT_ADMIT_WAIT=30 test_sim
expect "WORKOUT_ADMIT_WAIT, when set, is hostgate's wait" "$(slots)" \
    "label=workout-app:test-sim.sh wait=30 nested=no xcodebuild build-for-testing"
reset
test_sim --no-build; status=$?
expect "--no-build takes no slot" "$status $(builds) $(slots)" "65 test-without-building "

echo "build-slot.sh"
reset
(cd "$repo" && build_slot sh -c 'echo ran; exit 3'); status=$?
expect "it runs the command in a slot and exits with the command's status, saying nothing" \
    "$status $(cat "$root/out") $(cat "$root/err")" "3 ran "
expect "the slot is labelled workout-app:build-slot.sh" "$(cut -d' ' -f1-3 "$root/hostgate.log")" \
    "label=workout-app:build-slot.sh wait=- nested=no"
expect "and it meters the command into the dev-usage ledger" \
    "$(tail -1 "$WORKOUT_DEV_USAGE_DIR/commands.tsv" | cut -f2-4)" "$(cd "$repo" && pwd -P)	sh -c	3"
reset
build_slot --as crap.sh true
expect "--as names the calling script in the label" "$(cut -d' ' -f1 "$root/hostgate.log")" "label=workout-app:crap.sh"
reset
build_slot --log "$root/build.log" sh -c 'echo out; echo err >&2'; status=$?
expect "--log takes the command's stdout and stderr" "$status $(tr '\n' ' ' < "$root/build.log")" "0 out err "
reset
build_slot "$repo/scripts/build-slot.sh" --as inner.sh true; status=$?
expect "a build-slot.sh inside a slot takes no second one" "$status $(cut -d' ' -f1-3 "$root/hostgate.log" | tr '\n' ';')" \
    "0 label=workout-app:build-slot.sh wait=- nested=no;label=workout-app:inner.sh wait=- nested=yes;"
reset
HOSTGATE_SLOT=1 WORKOUT_DISK_FLOOR=99999999 WORKOUT_ADMIT_WAIT=0 build_slot true; status=$?
expect "a build-slot.sh inside a slot runs at once, as its caller already waited for disk" "$status" "0"
reset
FAKE_HOSTGATE_GIVE_UP=1 build_slot touch "$root/ran"; status=$?
expect "when hostgate gives up it exits 75 without running the command" "$status $([ -f "$root/ran" ] && echo ran)" "75 "
reset
(cd "$repo" && build_slot sh -c 'exit 75'); status=$?
expect "a command's own 75 is its status, with no slot line" "$status $(grep -c 'came free' "$root/err")" "75 0"

echo "hostgate missing or old"
reset
no_hostgate build_slot sh -c 'echo ran; exit 3'; status=$?
expect "with no hostgate it says so once, loudly, and runs the command anyway with its status" \
    "$status $(cat "$root/out") $(grep -c . "$root/err") $(cat "$root/err")" \
    "3 ran 1 hostgate is not on PATH, so this build takes no host-wide slot and may stall every other agent; install it: $install_line"
reset
no_hostgate test_sim; status=$?
expect "test-sim.sh builds without hostgate, after the same line" "$status $(builds) $(grep -c 'hostgate is not on PATH' "$root/err")" \
    "65 build-for-testing 1"
reset
FAKE_HOSTGATE_BROKEN=1 build_slot sh -c 'echo ran; exit 3'; status=$?
expect "a hostgate that fails before it starts the command says so, names the install, and runs it anyway" \
    "$status $(cat "$root/out") $(grep -c 'hostgate run failed (exit 1) before it started the build.*reinstall it: ' "$root/err")" "3 ran 1"
reset
FAKE_HOSTGATE_BROKEN=1 test_sim; status=$?
expect "test-sim.sh builds through a broken hostgate rather than calling it a build failure" \
    "$status $(builds) $(grep -c 'hostgate run failed' "$root/err")" "65 build-for-testing 1"
reset
FAKE_HOSTGATE_BROKEN=69 build_slot touch "$root/ran"; status=$?
expect "a required check hostgate refuses on is its 69, and the command does not run" "$status $([ -f "$root/ran" ] && echo ran)" "69 "
reset
FAKE_HOSTGATE_VERSION=0.9.9 build_slot true; status=$?
expect "an older hostgate gets a loud line and still runs the command through it" \
    "$status $(cat "$root/err") | $(cut -d' ' -f1 "$root/hostgate.log")" \
    "0 hostgate 0.9.9 is older than the $(cat "$repo/scripts/hostgate-version") this repo pins (scripts/hostgate-version); update it: $install_line | label=workout-app:build-slot.sh"
said=
for version in 1.0.0 1.0.1 1.2.0 10.0.0; do
    reset
    FAKE_HOSTGATE_VERSION=$version build_slot true
    [ ! -s "$root/err" ] || said="$said $version"
done
expect "the pinned version and newer ones say nothing" "${said:-none}" "none"
said=
for version in 0.10.0 0.99.99 dev 1.0; do
    reset
    FAKE_HOSTGATE_VERSION=$version build_slot true
    grep -q "is older than" "$root/err" || said="$said $version"
done
expect "older and unreadable versions each get the line" "${said:-all}" "all"
reset
echo 2.0.0 > "$repo/scripts/hostgate-version"
build_slot true
expect "the pin is the one in scripts/hostgate-version" "$(grep -c 'older than the 2.0.0' "$root/err")" "1"
git -C "$repo" checkout -q scripts/hostgate-version

echo "admission before hostgate"
reset
STUB_LOAD=212.40 WORKOUT_ADMIT_WAIT=0 build_slot true; status=$?
expect "the 1-minute load holds nothing" "$status" "0"
reset
STUB_MEM_LEVEL=12 WORKOUT_ADMIT_WAIT=0 build_slot true; status=$?
expect "free memory is hostgate's to judge, so the wrapper does not wait for it" "$status $(grep -c . "$root/hostgate.log")" "0 1"
reset
WORKOUT_ADMIT_WAIT=six test_sim; status=$?
expect "a knob that is not a whole number is a usage error" "$status $(cat "$root/err")" "2 WORKOUT_ADMIT_WAIT must be a whole number: six"

echo "usage"
build_slot; status=$?
expect "with no command it prints the usage and exits 2" "$status $(head -1 "$root/err")" \
    "2 Usage: scripts/build-slot.sh [--as SCRIPT] [--log FILE] <command> [arg...]"
build_slot --as crap.sh; status=$?
expect "--as with no command is a usage error" "$status" "2"
build_slot --help; status=$?
expect "--help prints the usage on stdout and exits 0" "$status $(head -1 "$root/out")" \
    "0 Usage: scripts/build-slot.sh [--as SCRIPT] [--log FILE] <command> [arg...]"

printf '\npassed %d, failed %d\n' "$pass" "$fail"
[ "$fail" = 0 ]
