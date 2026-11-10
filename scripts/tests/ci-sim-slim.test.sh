#!/bin/bash
set -uo pipefail

ci=$(cd "$(dirname "${BASH_SOURCE[0]}")/../ci" && pwd)
udid=CI-SIM-SLIM-TEST-$$
store=/private/var/tmp/com.apple.CoreSimulator.SimDevice.$udid
trap 'rm -rf "$store"' EXIT
pass=0
fail=0

ok()  { pass=$((pass + 1)); printf '  ok   %s\n' "$1"; }
bad() { fail=$((fail + 1)); printf '  FAIL %s\n' "$1"; }
expect() { if [ "$2" = "$3" ]; then ok "$1"; else bad "$1"; printf '    got:\n%s\n    want:\n%s\n' "$2" "$3"; fi; }
entries() { python3 -c 'import plistlib, sys
for label, disabled in sorted(plistlib.load(open(sys.argv[1], "rb")).items()): print(label, disabled)' "$store/disabled.plist"; }
labels() { sed 's/#.*//' "$@" | awk 'NF { print $1 " True" }' | LC_ALL=C sort; }

"$ci/sim-slim.sh" "$udid"
expect "it marks every job in sim-disabled-jobs.txt disabled in the device's launchd disable list" \
    "$? $(entries | LC_ALL=C sort)" "0 $(labels "$ci/sim-disabled-jobs.txt")"

python3 -c 'import plistlib, sys
plistlib.dump({"com.apple.pairedsyncd": False}, open(sys.argv[1], "wb"))' "$store/disabled.plist"
"$ci/sim-slim.sh" "$udid" "$ci/sim-ci-disabled-jobs.txt"
expect "an extra list adds its jobs, and an explicit enable already there stays" \
    "$? $(entries | LC_ALL=C sort)" \
    "0 $( (labels "$ci/sim-disabled-jobs.txt" "$ci/sim-ci-disabled-jobs.txt"; echo "com.apple.pairedsyncd False") | LC_ALL=C sort)"

"$ci/sim-slim.sh" 2>"$store/err"
expect "with no UDID it prints the usage and exits 2" "$? $(head -1 "$store/err")" "2 Usage: scripts/ci/sim-slim.sh <UDID> [<extra list>...]"

printf '\npassed %s, failed %s\n' "$pass" "$fail"
[ "$fail" -eq 0 ] || exit 1
