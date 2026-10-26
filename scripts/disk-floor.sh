#!/bin/bash
set -euo pipefail

case ${1:-} in
  -h | --help)
    cat <<'EOF_HELP'
Usage: scripts/disk-floor.sh
Exits 0 once free disk on this checkout's volume and HOME's is at least WORKOUT_DISK_FLOOR (5120 MB;
0 turns it off). Until then it waits, saying why once a minute, and exits 75 after WORKOUT_ADMIT_WAIT
seconds (540). The builds that take no build slot run it first: flake-hunt.sh, check-each-commit.sh,
mutate.sh, and crap.sh. It checks free disk at that moment and reserves none.
EOF_HELP
    exit 0 ;;
  '') ;;
  *) echo "scripts/disk-floor.sh takes no arguments; see --help" >&2; exit 2 ;;
esac
. "$(cd "$(dirname "$0")" && pwd)/sim-lock.sh"
wait_until_clear "free disk" disk_clear
