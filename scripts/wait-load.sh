#!/bin/bash
set -euo pipefail

usage() {
  cat >&2 <<'USAGE'
Usage: scripts/wait-load.sh [limit] [max-wait]
Waits while the host's 1-minute load is over limit (default WORKOUT_LOAD_LIMIT, else 50), for at most
max-wait seconds (default WORKOUT_ADMIT_WAIT, else 600). Exits 0 once the load is at or under the limit,
75 with the load if it never got there. test-sim.sh and verify.sh launch already wait this way, and for
booted simulators too; this is for anything else heavy, as in scripts/wait-load.sh && swift test.
USAGE
  exit 2
}

case ${1:-} in -h|--help) usage ;; esac
[ $# -le 2 ] || usage
. "$(cd "$(dirname "$0")" && pwd)/sim-lock.sh"
WORKOUT_LOAD_LIMIT=${1:-$WORKOUT_LOAD_LIMIT}
WORKOUT_ADMIT_WAIT=${2:-$WORKOUT_ADMIT_WAIT}
host_knob WORKOUT_LOAD_LIMIT 50 1
host_knob WORKOUT_ADMIT_WAIT 600 0
wait_until_clear "the load to fall to $WORKOUT_LOAD_LIMIT" load_clear "$WORKOUT_LOAD_LIMIT"
