# shellcheck shell=bash
# Starting, stopping and watching the test-sim.sh runs of the bounds and stamp suites. Source it after
# test-sim-harness.sh.

# stop NAME...: SIGTERM each process this test started and saved as $NAME, with its stamp in $NAME_stamp.
stop() {
    local name pid stamp stamp_var
    for name in "$@"; do
        pid=${!name}
        stamp_var=${name}_stamp
        stamp=${!stamp_var:-}
        signal_same TERM "$pid" "$stamp"
    done
    return 0
}
# release_after SECONDS: touches $release after SECONDS from one process, saved as releaser, so stop
# ends it and leaves no sleep behind.
release_after() {
    perl -e 'sleep shift; open my $f, ">", shift' "$1" "$release" &
    releaser=$!
    releaser_stamp=$(proc_stamp "$releaser")
}
# kill_script SIG: signals the test-sim.sh this test started, found and stamped at once.
kill_script() {
    local pid
    pid=$(pgrep -f "$repo/scripts/test-sim.sh --no-build" | head -1)
    [ -n "$pid" ] && signal_same "$1" "$pid" "$(proc_stamp "$pid")"
}

release=$root/release
# GONE_WITHIN bounds how long a check waits for a process to quit. STUCK_FOR, well past it, is
# how long a stub xcodebuild that nothing stops runs before it ends itself, so a check fails rather
# than hangs.
gone_within=${GONE_WITHIN:-20}
stuck_for=${STUCK_FOR:-$((gone_within * 4))}
watchdogs() { pgrep -f "$root/repo/.build/test-sim/.*overran" || true; }
runs() { pgrep -f "$root/bin/xcodebuild" || true; }
gone() {
    local deadline=$((SECONDS + gone_within))
    while [ -n "$("$1")" ] && [ $SECONDS -lt $deadline ]; do sleep 0.1; done
    [ -z "$("$1")" ]
}

