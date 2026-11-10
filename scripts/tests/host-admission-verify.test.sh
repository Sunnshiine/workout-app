#!/bin/bash
# verify.sh's side of host admission: its builds, and a run another claim reclaimed. SIM names the
# caller's own Simlock lease, as the harness seeds it.
set -uo pipefail

# shellcheck source=scripts/tests/host-admission-harness.sh
. "$(dirname "${BASH_SOURCE[0]}")/host-admission-harness.sh"

reclaim_note() { tail -1 "$root/err" | sed -E 's/\(pid [0-9]+\) at [0-9-]+ [0-9:]+;/(pid N) at T;/'; }
age_minutes() { python3 -c 'import os, sys, time; t = time.time() - int(sys.argv[2]) * 60; os.utime(sys.argv[1], (t, t))' "$1" "$2"; }
minutes_old() { python3 -c 'import os, sys, time; print(int((time.time() - os.stat(sys.argv[1]).st_mtime) // 60))' "$1"; }
verify_build() { verify build >"$root/out" 2>"$root/err"; }

own_the_app() {
    python3 -c 'import time; time.sleep(120)' -UITEST_FIXTURE &
    app=$!
    apps+=("$app")
    mkdir -p "$state"
    echo "$1" > "$state/run"
    echo "$app" > "$state/pid"
    echo "-UITEST_FIXTURE -UITEST_SESSION -UITEST_DISABLE_LIVE_ACTIVITIES" > "$state/args"
    age_minutes "$state/pid" "$2"
}

echo "build"
reset
STUB_LOAD=212.40 WORKOUT_ADMIT_WAIT=0 verify_build; status=$?
expect "a 1-minute load of 212.40 holds no build" "$status $(builds)" "65 build"
reset
verify_build; status=$?
expect "verify.sh build runs in a slot labelled workout-app:verify.sh" "$status $(builds) | $(slots)" \
    "65 build | label=workout-app:verify.sh wait=- nested=no xcodebuild build"
reset
FAKE_HOSTGATE_SAY="hostgate: waiting up to 540 s for a slot" verify_build
expect "hostgate's wait lines reach stderr through the build log's redirect" "$(grep -c 'waiting up to 540 s' "$root/err")" "1"
reset
FAKE_HOSTGATE_GIVE_UP=1 verify_build; status=$?
expect "a build hostgate gives up on exits 75 before any xcodebuild, naming why" "$status $(builds) $(tail -1 "$root/err")" \
    "75  hostgate: gave up waiting for a slot held by workout-app:neighbour"

echo "a reclaimed run"
reset; own_the_app abandoned-run 61
test_sim --no-build
rm -f "$root/xcrun-calls"
VERIFY_RUN=abandoned-run verify stop >"$root/out" 2>"$root/err"; status=$?
expect "the reclaimed run's stop says who reclaimed it and when, and touches nothing" \
    "$status $(cat "$root/xcrun-calls" 2>/dev/null)$(cat "$root/out")$(reclaim_note)" \
    "75 run abandoned-run was reclaimed by test-sim.sh run (pid N) at T; launch again: SIM=$sim VERIFY_RUN=abandoned-run $repo/.agents/skills/verify/verify.sh launch <fixture>"
went=
for verb in doctor tree "find x" "tap --id x" "hold x" "type x" "swipe up" "shot s" "burst b" "axe describe-ui"; do
    read -ra argv <<< "$verb"
    VERIFY_RUN=abandoned-run verify "${argv[@]}" >/dev/null 2>"$root/err"; status=$?
    [ "$status $(reclaim_note)" = "75 run abandoned-run was reclaimed by test-sim.sh run (pid N) at T; launch again: SIM=$sim VERIFY_RUN=abandoned-run $repo/.agents/skills/verify/verify.sh launch <fixture>" ] \
        || went="$went${went:+, }$verb"
done
expect "every command that acts on the reclaimed run's app refuses the same way" "${went:-none went on}" "none went on"
verify shot s >/dev/null 2>"$root/err"; status=$?
expect "a command that names no run is the recorded run, so it refuses too and files no evidence" \
    "$status $(ls "$repo/.claude/work/evidence" 2>/dev/null)" "75 "
expect "and is told to launch a run of its own, not to take the reclaimed run's name" "$(reclaim_note)" \
    "run abandoned-run was reclaimed by test-sim.sh run (pid N) at T; launch again: SIM=$sim $repo/.agents/skills/verify/verify.sh launch <fixture>"
VERIFY_RUN=abandoned-run verify build >/dev/null 2>"$root/err"; status=$?
expect "build acts on no run's app, so the reclaimed run may still build" "$status $(builds)" "65 test-without-building build"

reset; own_the_app abandoned-run 61
VERIFY_RUN=lane-new verify launch session >/dev/null 2>"$root/err"; status=$?
expect "a launch reclaims the run's simulator, then starts its own run" "$status $(cat "$state/run")" "70 lane-new"
VERIFY_RUN=abandoned-run verify tree >/dev/null 2>"$root/err"; status=$?
expect "the reclaimed run is told which run reclaimed it" "$status $(reclaim_note)" \
    "75 run abandoned-run was reclaimed by verify.sh launch of run lane-new (pid N) at T; launch again: SIM=$sim VERIFY_RUN=abandoned-run $repo/.agents/skills/verify/verify.sh launch <fixture>"
VERIFY_RUN=lane-new verify tree >/dev/null 2>"$root/err"
expect "the reclaiming run goes on" "$(grep -c reclaimed "$root/err")" "0"
VERIFY_RUN=abandoned-run verify launch session >/dev/null 2>"$root/err"
VERIFY_RUN=abandoned-run verify tree >/dev/null 2>"$root/err"
expect "a launch of the reclaimed run takes its name back" "$(grep -c reclaimed "$root/err")" "0"

reset; own_the_app abandoned-run 61
FAKE_HOSTGATE_GIVE_UP=1 test_sim; status=$?
verify tree >/dev/null 2>&1
test_sim --no-build; status="$status $?"
expect "a reclaim refused at the build slot stays reclaimed, though a verify.sh call that names no run follows" \
    "$status $(grep -c 'owns the app' "$root/err")" "75 65 0"

echo "renewal"
reset; own_the_app lane-812 59
VERIFY_RUN=lane-813 verify tree >/dev/null 2>&1
expect "a verify.sh call for another run does not renew the lease" "$(minutes_old "$state/pid")" "59"
VERIFY_RUN=lane-812 verify tree >/dev/null 2>&1
expect "a verify.sh call for the run renews its lease" "$(minutes_old "$state/pid")" "0"
age_minutes "$state/pid" 59
verify tree >/dev/null 2>&1
expect "a verify.sh call that names no run renews the recorded one" "$(minutes_old "$state/pid")" "0"
age_minutes "$state/pid" 61
verify tree >/dev/null 2>"$root/err"
expect "a verify.sh call that names no run does not revive an expired lease" "$(minutes_old "$state/pid")" "61"
expect "and says how to renew it" "$(head -1 "$root/err")" \
    "the lease of verify run lane-812 on $sim expired: last renewed 61 min ago, and the lease is 60 min, so a claim may take its app; if the run is yours, name it with VERIFY_RUN=lane-812 to keep it"
rm "$state/pid"
verify tree >/dev/null 2>&1
expect "renewing never recreates a stopped run's pid file" "$(ls "$state" | tr '\n' ' ')" "args run "

printf '\npassed %d, failed %d\n' "$pass" "$fail"
[ "$fail" = 0 ]
