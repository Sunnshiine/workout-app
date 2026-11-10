#!/bin/bash
set -euo pipefail

help() {
  cat <<'EOF_HELP'
Usage: scripts/build-slot.sh [--as SCRIPT] [--log FILE] <command> [arg...]
Runs a heavy build or test command in one of hostgate's host-wide slots, which every repo on this Mac
shares, as in scripts/build-slot.sh swift test. hostgate labels the slot workout-app:SCRIPT
(default build-slot.sh); the repo's scripts pass their own name. --log sends the command's stdout
and stderr to FILE and leaves the waits' lines on stderr. It first waits, saying why once a
minute, while free disk is under WORKOUT_DISK_FLOOR (5120 MB; 0 turns it off), and exits 75 after
WORKOUT_ADMIT_WAIT seconds (540). hostgate then waits for its memory floor and a free slot, saying who
holds them once a minute, and exits 75 when its wait runs out (WORKOUT_ADMIT_WAIT when set, else its
own). A command already inside a slot (HOSTGATE_SLOT set) runs at once and takes no second one.
When hostgate is missing, as on CI, it prints one line naming the install command and runs the
command with no slot; when hostgate is older than scripts/hostgate-version, it says so and uses it.
Otherwise exits with the command's status.
scripts/dev-usage.sh record meters the command, as "<command> <first arg>", into commands.tsv.
EOF_HELP
}

case ${1:-} in
  -h|--help) help; exit 0 ;;
  '') help >&2; exit 2 ;;
esac
slot_label= log=()
while [ $# -gt 0 ]; do
  case $1 in
    --as) [ $# -ge 2 ] || { help >&2; exit 2; }; slot_label=$2; shift 2 ;;
    --log) [ $# -ge 2 ] || { help >&2; exit 2; }; log=(--log "$2"); shift 2 ;;
    *) break ;;
  esac
done
[ $# -gt 0 ] || { help >&2; exit 2; }
here=$(cd "$(dirname "$0")" && pwd)
. "$here/sim-lock.sh"
with_build_slot ${log[@]+"${log[@]}"} "$here/dev-usage.sh" record "${1##*/}${2:+ $2}" -- "$@"
