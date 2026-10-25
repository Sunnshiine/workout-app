#!/bin/bash
set -euo pipefail

help() {
  cat <<'EOF_HELP'
Usage: scripts/build-slot.sh <command> [arg...]
Runs the command holding one of the WORKOUT_BUILD_SLOTS (2) host-wide build slots that test-sim.sh and
verify.sh builds take, as in scripts/build-slot.sh swift test. Waits first, saying why once a minute,
while free memory is under WORKOUT_MEM_FLOOR (25, percent; 0 turns it off), free disk is under
WORKOUT_DISK_FLOOR (4096 MB; 0 turns it off), or every slot is taken, and
exits 75 without running the command after WORKOUT_ADMIT_WAIT seconds (540), restarted each time a
slot changes hands. Otherwise exits with the
command's status. The command keeps the slot until it exits, even if this script is killed.
scripts/dev-usage.sh record meters the command, as "<command> <first arg>", into commands.tsv.
EOF_HELP
}

case ${1:-} in
  -h|--help) help; exit 0 ;;
  '') help >&2; exit 2 ;;
esac
here=$(cd "$(dirname "$0")" && pwd)
. "$here/sim-lock.sh"
with_build_slot "$here/dev-usage.sh" record "${1##*/}${2:+ $2}" -- "$@"
