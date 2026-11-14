#!/usr/bin/env bash
set -uo pipefail

# test-sim.sh signals a run, a watchdog or a helper only by the start time it read for it, and a signal
# during its stop does not cut the stop short.
# shellcheck source=scripts/tests/test-sim-harness.sh
. "$(dirname "${BASH_SOURCE[0]}")/test-sim-harness.sh"
# shellcheck source=scripts/tests/test-sim-stopping.sh
. "$(dirname "${BASH_SOURCE[0]}")/test-sim-stopping.sh"

passing="✔ Test run with 1 test in 1 suite passed after 0.010 seconds.
** TEST EXECUTE SUCCEEDED **"
printf '%s\n' "$passing" >"$root/xcodebuild.log"

echo "test-sim.sh signals only the xcodebuild that carries the start time it read at launch"
rm -f "$release" "$root/started" "$root/recycled"
release_after "$stuck_for"
(
    STUB_LOG=$root/xcodebuild.log STUB_OUT=$root/out STUB_SEEN=$root/seen STUB_TOUCH=$root/started STUB_RC=0 \
        STUB_RELEASE="$release" STUB_RECYCLED=$root/recycled WORKOUT_TEST_RUN_LIMIT=600 WORKOUT_TEST_KILL_GRACE=1 \
        HOME=$root/home PATH="$root/recycled-bin:$root/bin:$PATH" \
        "$repo/scripts/test-sim.sh" --no-build --sim "$sim" unit >/dev/null 2>&1
    echo $? >"$root/recycled-status"
) &
recycled_run=$!
while { [ ! -e "$root/started" ] || [ -z "$(watchdogs)" ]; } && [ ! -e "$release" ]; do sleep 0.1; done
sleep 1
runs >"$root/recycled"
kill_script TERM
sleep 3
if [ -n "$(runs)" ] && [ ! -e "$release" ]; then
    ok "after SIGTERM, an xcodebuild pid whose start time changed gets no signal"
else
    bad "after SIGTERM, an xcodebuild pid whose start time changed gets no signal: $( [ -e "$release" ] && echo released || echo signalled)"
fi
touch "$release"
gone runs
wait "$recycled_run"
if [ "$(cat "$root/recycled-status" 2>/dev/null)" = 143 ]; then ok "test-sim.sh then exits 143"; else bad "test-sim.sh then exits 143: $(cat "$root/recycled-status" 2>/dev/null)"; fi
stop releaser
wait 2>/dev/null

echo "test-sim.sh signals only the watchdog that carries the start time it read at launch"
# The stub xcodebuild ignores SIGTERM, so test-sim.sh spends the kill grace stopping it, and the watchdog,
# which sees its xcodebuild unchanged, runs on through that grace unless test-sim.sh signalled it.
rm -f "$release" "$root/started" "$root/recycled"
release_after "$stuck_for"
(
    STUB_LOG=$root/xcodebuild.log STUB_OUT=$root/out STUB_SEEN=$root/seen STUB_TOUCH=$root/started STUB_RC=0 STUB_DEAF=1 \
        STUB_RELEASE="$release" STUB_RECYCLED=$root/recycled WORKOUT_TEST_RUN_LIMIT=600 WORKOUT_TEST_KILL_GRACE=5 \
        HOME=$root/home PATH="$root/recycled-bin:$root/bin:$PATH" \
        "$repo/scripts/test-sim.sh" --no-build --sim "$sim" unit >/dev/null 2>&1
    echo $? >"$root/recycled-status"
) &
recycled_run=$!
while { [ ! -e "$root/started" ] || [ -z "$(watchdogs)" ]; } && [ ! -e "$release" ]; do sleep 0.1; done
# The stub sets its SIGTERM trap half a second after it marks itself started.
sleep 1
watchdogs >"$root/recycled"
kill_script TERM
sleep 2
if [ -n "$(watchdogs)" ]; then
    ok "after SIGTERM, a watchdog pid whose start time changed gets no signal"
else
    bad "after SIGTERM, a watchdog pid whose start time changed gets no signal"
fi
wait "$recycled_run"
if [ "$(cat "$root/recycled-status" 2>/dev/null)" = 143 ] && [ ! -e "$release" ]; then
    ok "test-sim.sh exits 143 without waiting on that watchdog"
else
    bad "test-sim.sh exits 143 without waiting on that watchdog: $(cat "$root/recycled-status" 2>/dev/null), $([ -e "$release" ] && echo "waited for the release" || echo early)"
fi
if gone watchdogs; then ok "the watchdog quits once its xcodebuild is gone"; else bad "the watchdog quits once its xcodebuild is gone: $(watchdogs)"; fi
stop releaser
wait 2>/dev/null
rm -f "$release" "$root/recycled"

# The caller's `perl -e 'alarm N'` bound sends ALRM, so a second signal can be either.
for second in TERM ALRM; do
echo "a second signal, $second, while test-sim.sh stops its run does not cut the stop short"
rm -f "$release" "$root/started"
release_after "$stuck_for"
(
    STUB_LOG=$root/xcodebuild.log STUB_OUT=$root/out STUB_SEEN=$root/seen STUB_TOUCH=$root/started STUB_RC=0 STUB_DEAF=1 \
        STUB_RELEASE="$release" WORKOUT_TEST_RUN_LIMIT=600 WORKOUT_TEST_KILL_GRACE=3 HOME=$root/home PATH="$root/bin:$PATH" \
        "$repo/scripts/test-sim.sh" --no-build --sim "$sim" unit >"$root/twice" 2>&1
) &
twice_run=$!
while { [ ! -e "$root/started" ] || [ -z "$(watchdogs)" ]; } && [ ! -e "$release" ]; do sleep 0.1; done
# The stub sets its SIGTERM trap half a second after it marks itself started.
sleep 1
script=$(pgrep -f "$repo/scripts/test-sim.sh --no-build" | head -1)
script_stamp=$(proc_stamp "$script")
signal_same TERM "$script" "$script_stamp"
sleep 1
signal_same "$second" "$script" "$script_stamp"
wait "$twice_run"
if [ ! -e "$release" ] && [ -z "$(runs)" ] && tail -1 "$root/twice" | grep -q ' exit=143 '; then
    ok "test-sim.sh still kills the xcodebuild that ignores SIGTERM, and prints its result line"
else
    bad "test-sim.sh still kills the xcodebuild that ignores SIGTERM, and prints its result line: left $(runs), last line $(tail -1 "$root/twice")"
fi
left=$(pgrep -f "$repo/scripts/test-sim.sh --no-build" || true)
if [ -z "$left$(watchdogs)" ]; then
    ok "its watchdog, idle watcher and lease heartbeat are gone too"
else
    bad "its watchdog, idle watcher and lease heartbeat are gone too: test-sim.sh pids $left, watchdogs $(watchdogs)"
fi
marks=$(cd "$root/repo/.build/test-sim" 2>/dev/null && ls -- *-idle 2>/dev/null)
newest=$(ls -t "$root/repo/.build/test-sim/"*-test.log 2>/dev/null | head -1)
if [ -z "$marks" ] && [ -n "$newest" ] && tail -1 "$newest" | grep -q ' exit=143 '; then
    ok "and its cleanup finished: no idle mark is left, and the run's log ends on the result line"
else
    bad "and its cleanup finished: no idle mark is left, and the run's log ends on the result line: marks ${marks:-none}"
fi
touch "$release"
gone runs
stop releaser
wait 2>/dev/null
rm -f "$release"
done

echo "a run whose stamp was never read is still stopped by a signal"
# A signal between `xcodebuild ... &` and its stamp read leaves run_stamp empty. This ps reads no start
# time for the stub xcodebuild the first time it is asked, which is that state, with no timing window.
mkdir -p "$root/unread-bin"
cat >"$root/unread-bin/ps" <<'STUB'
#!/bin/sh
case "$*" in "-o lstart= -p "*) ;; *) exec /bin/ps "$@" ;; esac
pid=$4
[ ! -e "$STUB_UNREAD" ] || exec /bin/ps "$@"
# The job may not have exec'd yet, and then still shows test-sim.sh's command.
i=0
while [ $i -lt 40 ]; do
    case $(/bin/ps -o command= -p "$pid") in
        *"$STUB_XCODEBUILD"*) touch "$STUB_UNREAD"; exit 0 ;;
        *test-sim.sh*) sleep 0.05; i=$((i + 1)) ;;
        *) break ;;
    esac
done
exec /bin/ps "$@"
STUB
chmod +x "$root/unread-bin/ps"
rm -f "$release" "$root/started" "$root/unread"
release_after "$stuck_for"
(
    STUB_LOG=$root/xcodebuild.log STUB_OUT=$root/out STUB_SEEN=$root/seen STUB_TOUCH=$root/started STUB_RC=0 \
        STUB_RELEASE="$release" STUB_UNREAD=$root/unread STUB_XCODEBUILD=$root/bin/xcodebuild WORKOUT_TEST_RUN_LIMIT=600 \
        WORKOUT_TEST_KILL_GRACE=3 HOME=$root/home PATH="$root/unread-bin:$root/bin:$PATH" \
        "$repo/scripts/test-sim.sh" --no-build --sim "$sim" unit >/dev/null 2>&1
    echo $? >"$root/unread-status"
) &
unread_run=$!
while [ ! -e "$root/started" ] && [ ! -e "$release" ]; do sleep 0.1; done
signalled=$SECONDS
kill_script TERM
wait "$unread_run"
if [ -e "$root/unread" ] && [ ! -e "$release" ] && [ -z "$(runs)" ] && [ "$(cat "$root/unread-status")" = 143 ] \
    && [ $((SECONDS - signalled)) -lt "$gone_within" ]; then
    ok "test-sim.sh reads the stamp at the stop, ends that xcodebuild, and exits 143"
else
    bad "test-sim.sh reads the stamp at the stop, ends that xcodebuild, and exits 143: stamp $([ -e "$root/unread" ] && echo unread || echo read), $([ -e "$release" ] && echo "waited for the release" || echo early), left $(runs), status $(cat "$root/unread-status"), $((SECONDS - signalled)) s"
fi
touch "$release"
gone runs
stop releaser
wait 2>/dev/null
rm -f "$release" "$root/unread"

printf '\n%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" = 0 ]
