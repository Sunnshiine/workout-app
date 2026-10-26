#!/bin/bash
set -euo pipefail

case ${1:-} in
  -h | --help)
    cat <<'EOF_HELP'
Usage: scripts/disk-floor.sh [dir]
Exits 0 once free disk on the volume holding dir (default this checkout) and on HOME's is at least
WORKOUT_DISK_FLOOR (5120 MB; 0 turns it off). Until then it waits, saying why once a minute, and
exits 75 after WORKOUT_ADMIT_WAIT seconds (540). The builds that take no build slot run it first:
flake-hunt.sh, check-each-commit.sh and mutate.sh (on their scratch tree), and crap.sh. It checks
free disk at that moment and reserves none.
EOF_HELP
    exit 0 ;;
  -*) echo "scripts/disk-floor.sh: unknown option $1; see --help" >&2; exit 2 ;;
esac
[ $# -le 1 ] || { echo "scripts/disk-floor.sh takes at most one dir; see --help" >&2; exit 2; }
. "$(cd "$(dirname "$0")" && pwd)/sim-lock.sh"
[ $# = 0 ] || sim_lock_checkout=$1
wait_until_clear "free disk" disk_clear
