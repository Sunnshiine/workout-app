#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat >&2 <<'EOF'
Usage: scripts/flake-hunt.sh [--repetitions N] [--load N] [FILTER]
Repeats every `swift test` test (or those matching FILTER) until one fails, up to N repetitions
each (default 200), while N busy-loop processes (default three per core) hold the CPU. Timing
races that pass on a quiet machine fail here within a few hundred repetitions.
Exits 0 when every repetition passed; otherwise prints the failing tests and exits 1.
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
swift build --build-tests >/dev/null

log=$repo/.build/flake-hunt/$(date +%Y%m%d-%H%M%S).log
mkdir -p "$(dirname "$log")"

hogs=()
trap 'kill ${hogs[@]+"${hogs[@]}"} 2>/dev/null || true' EXIT
for _ in $(seq "$load"); do
  yes >/dev/null &
  hogs+=($!)
done

set +e
swift test --skip-build ${filter[@]+"${filter[@]}"} --repeat-until fail --maximum-repetitions "$repetitions" >"$log" 2>&1
rc=$?
set -e

grep -E '^✘ Test .*(recorded an issue|failed after)|unexpected signal|^✔ Test run with|^✘ Test run with' "$log" | uniq || true
echo "log: $log"
exit $(( rc == 0 ? 0 : 1 ))
