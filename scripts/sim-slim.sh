#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat >&2 <<'EOF2'
Usage: scripts/sim-slim.sh <UDID> [<extra list>...]
Marks every launchd job in scripts/sim-pool-disabled-jobs.txt disabled in the simulator's
/private/var/tmp/com.apple.CoreSimulator.SimDevice.<UDID>/disabled.plist, which launchd_sim reads
at each boot, by any route (ADR-0022), and the labels of each extra list too. Takes effect at the
device's next boot. Entries already there, such as the runtime's own explicit enables, stay. Exits
70 when the file cannot be written.
EOF2
  exit 2
}

[ $# -ge 1 ] || usage
here=$(cd "$(dirname "$0")" && pwd)
store=/private/var/tmp/com.apple.CoreSimulator.SimDevice.$1
# simctl clone does not copy this host file, so every device needs its own.
[ -d "$store" ] || mkdir -m 700 "$store" || { echo "sim-slim: could not create $store" >&2; exit 70; }
python3 - "$store/disabled.plist" "$here/sim-pool-disabled-jobs.txt" "${@:2}" <<'EOF2' || { echo "sim-slim: could not write the launchd disable list of $1 to $store/disabled.plist" >&2; exit 70; }
import os, plistlib, sys, tempfile
store, *lists = sys.argv[1:]
labels = [line.split("#")[0].strip() for jobs in lists for line in open(jobs)]
entries = plistlib.load(open(store, "rb")) if os.path.exists(store) else {}
entries.update((label, True) for label in labels if label)
fd, temp = tempfile.mkstemp(dir=os.path.dirname(store))
with os.fdopen(fd, "wb") as f:
    plistlib.dump(entries, f)
os.chmod(temp, 0o644)
os.replace(temp, store)
EOF2
