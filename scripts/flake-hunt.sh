#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat >&2 <<'EOF'
Usage: scripts/flake-hunt.sh [--repetitions N] [--load N] [FILTER]
Repeats every `swift test` test (or those matching FILTER) until one fails, up to N repetitions
each (default 200), while N busy-loop processes (default three per core) hold the CPU. Timing
races that pass on a quiet machine fail here within a few hundred repetitions.
Exits 0 when every repetition passed, 1 when a test failed, 65 when the build failed or no test ran.
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
log=$repo/.build/flake-hunt/$(date +%Y%m%d-%H%M%S).log
mkdir -p "$(dirname "$log")"
echo "log: $log"
swift build --build-tests >"$log" 2>&1 || { grep -m 20 -E "error:" "$log" >&2 || true; echo "build log: $log" >&2; exit 65; }

hogs=()
trap 'kill ${hogs[@]+"${hogs[@]}"} 2>/dev/null || true' EXIT
for (( i = 0; i < load; i++ )); do
  yes >/dev/null &
  hogs+=($!)
done

rm -f "${log%.log}.xml" "${log%.log}-swift-testing.xml"
set +e
swift test --skip-build ${filter[@]+"${filter[@]}"} --repeat-until fail --maximum-repetitions "$repetitions" \
  --xunit-output "${log%.log}.xml" >"$log" 2>&1
rc=$?
set -e
# XCTest writes the xunit path given and Swift Testing a -swift-testing sibling; each counts its own tests.
if [ "$rc" -eq 0 ] && ! grep -qs '<testsuite [^>]*tests="[1-9]' "${log%.log}.xml" "${log%.log}-swift-testing.xml"; then
  echo "flake-hunt: no test ran${filter[1]+; no test matches ${filter[1]}}; see $log" >&2
  exit 65
fi

"$repo/scripts/test-log-summary.sh" "$log"
exit $(( rc == 0 ? 0 : 1 ))
