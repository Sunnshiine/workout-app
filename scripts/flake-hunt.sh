#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat >&2 <<'EOF'
Usage: scripts/flake-hunt.sh [--repetitions N] [--load N] [FILTER]
Repeats every `swift test` test (or those matching FILTER) until one fails, up to N repetitions
each (default 200), while N busy-loop processes (default three per core) hold the CPU. Timing
races that pass on a quiet machine fail here within a few hundred repetitions.
Starts the busy loops and the test process each in its own process group and records them as run
WORKOUT_RUN (default flake-hunt-<pid>), so scripts/reap.sh <run> ends this hunt's processes and their
children and no other's, even after a kill -9 of this script.
Exits 0 when every repetition passed, 1 when a test failed or the busy loops could not be recorded
(it ends them first), 2 on a usage error or a WORKOUT_RUN that is not a run name (scripts/reap.sh),
65 when the build failed or no test ran, 75 when free disk stays under WORKOUT_DISK_FLOOR
(scripts/disk-floor.sh).
EOF
  exit 2
}

repetitions=200
load=$(( $(sysctl -n hw.ncpu) * 3 ))
filter=()
while [ $# -gt 0 ]; do
  case $1 in
    --repetitions) repetitions=$2; shift ;;
    --load) load=$2; shift ;;
    -*) usage ;;
    *) filter=(--filter "$1") ;;
  esac
  shift
done

repo=$(cd "$(dirname "$0")/.." && pwd)
cd "$repo"
run=${WORKOUT_RUN:-flake-hunt-$$}
"$repo/scripts/reap.sh" --check "$run"
log=$repo/.build/flake-hunt/$(date +%Y%m%d-%H%M%S).log
mkdir -p "$(dirname "$log")"
echo "log: $log"
"$repo/scripts/disk-floor.sh"
swift build --build-tests >"$log" 2>&1 || { grep -m 20 -E "error:" "$log" >&2 || true; echo "build log: $log" >&2; exit 65; }

echo "run: $run ($repo/scripts/reap.sh $run ends its processes)"
trap '"$repo/scripts/reap.sh" "$run" >/dev/null 2>&1 || true' EXIT
hogs=()
set -m
for (( i = 0; i < load; i++ )); do
  yes >/dev/null &
  hogs+=($!)
done
set +m
[ ${#hogs[@]} = 0 ] || "$repo/scripts/reap.sh" --record "$run" "${hogs[@]}" || {
  # Nothing recorded them, so the EXIT trap's reap cannot find them.
  kill "${hogs[@]}" 2>/dev/null || true
  exit 1
}

rm -f "${log%.log}-swift-testing.xml"
set +e -m
swift test --skip-build ${filter[@]+"${filter[@]}"} --repeat-until fail --maximum-repetitions "$repetitions" \
  --xunit-output "${log%.log}.xml" </dev/null >"$log" 2>&1 &
tests=$!
set +m
# A test process that already ended, as one that matched no test can, leaves nothing to reap.
"$repo/scripts/reap.sh" --record "$run" "$tests" 2>/dev/null || true
wait "$tests"
rc=$?
set -e
# Swift Testing counts its tests in a -swift-testing sibling of the xunit path. XCTest writes that
# path only under --parallel, so its count is the log's Executed line, which the summary awk reads.
if [ "$rc" -eq 0 ] && ! grep -qs '<testsuite [^>]*tests="[1-9]' "${log%.log}-swift-testing.xml" &&
  ! awk -f "$repo/scripts/test-log-summary.awk" "$log" >/dev/null; then
  echo "flake-hunt: no test ran${filter[1]+; no test matches ${filter[1]}}; see $log" >&2
  exit 65
fi

if [ "$rc" -eq 0 ]; then
  "$repo/scripts/test-log-summary.sh" "$log"
else
  "$repo/scripts/test-log-summary.sh" --cause "$log"
fi
exit $(( rc == 0 ? 0 : 1 ))
