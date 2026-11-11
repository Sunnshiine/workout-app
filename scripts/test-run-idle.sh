# shellcheck shell=bash
# Sourced by test-sim.sh: the watcher that stops the test run once it sits idle after
# its last test. Reads $log, $xctest_ends, $swift_testing_ends and $idle_mark from test-sim.sh, and
# signals through same-process.sh.

# True once every selected bundle printed its end line: XCTest's top suite for each, and Swift Testing's
# run for each that has Swift Testing tests.
tests_ended() {
  awk -v xctest="$xctest_ends" -v swift="$swift_testing_ends" '
    { gsub(/\033\[[0-9;]*m/, ""); sub("^\342\200\213", "") }
    /^Test Suite \047(All|Selected) tests\047 (passed|failed)/ { x++ }
    /Test run with .* (passed|failed) after/ { s++ }
    END { exit !(x >= xctest && s >= swift) }' "$log"
}

# CPU seconds xcodebuild ($1) and its descendants have used.
tree_cpu() {
  ps -A -o pid=,ppid=,time= | awk -v root="$1" '
    { t = $3; d = 0
      if (t ~ /-/) { split(t, a, "-"); d = a[1]; t = a[2] }
      n = split(t, p, ":"); s = 0
      for (i = 1; i <= n; i++) s = s * 60 + p[i]
      cpu[$1] = s + d * 86400; parent[$1] = $2 }
    END { tree[root] = 1; grew = 1
      while (grew) { grew = 0; for (k in parent) if (!(k in tree) && (parent[k] in tree)) { tree[k] = 1; grew = 1 } }
      for (k in tree) total += cpu[k]
      printf "%.2f\n", total }'
}

# xcodebuild has sat for half an hour after its last test, waiting on nothing. Once every end line is in
# the log, a window of WORKOUT_TEST_IDLE_SECONDS with no output and under 1% of a CPU stops it. Before
# then its tree says nothing: the test runner and the app are launchd_sim's children, not xcodebuild's.
# A descendant that exits takes its seconds out of the sum, so a sum that fell is not idle. A watcher
# whose script was killed keeps bounding xcodebuild ($1, started at $2), and exits once that process is
# gone; it signals a pid only while the pid still names that process.
watch_idle() {
  local pid=$1 born=$2 size='' since='' cpu now_size now_cpu
  exec 6>&- 7>&- 8>&- 9>&- >/dev/null 2>&1
  trap 'exit 0' TERM
  while sleep "$WORKOUT_TEST_IDLE_POLL_SECONDS" & wait $!; same_process "$pid" "$born"; do
    tests_ended || continue
    now_size=$(wc -c <"$log")
    now_cpu=$(tree_cpu "$pid") || { since=''; continue; }
    if [ -z "$since" ] || [ "$now_size" != "$size" ]; then
      size=$now_size since=$SECONDS cpu=$now_cpu
      continue
    fi
    [ $((SECONDS - since)) -ge "$WORKOUT_TEST_IDLE_SECONDS" ] || continue
    if awk -v start="$cpu" -v end="$now_cpu" -v window="$WORKOUT_TEST_IDLE_SECONDS" 'BEGIN { exit !(end >= start && end - start < window / 100) }'; then
      same_process "$pid" "$born" || exit 0
      : >"$idle_mark"
      signal_same TERM "$pid" "$born"
      for _ in 1 2 3 4 5 6 7 8 9 10; do same_process "$pid" "$born" || exit 0; sleep 0.5; done
      signal_same KILL "$pid" "$born"
      exit 0
    fi
    since=$SECONDS cpu=$now_cpu
  done
}
