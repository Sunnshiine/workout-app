#!/bin/bash
set -uo pipefail

if [ $# != 0 ]; then
    cat >&2 <<'USAGE'
Usage: scripts/refuse-record-mode.sh
Fails when a Swift file under Tests/Visual/ commits `record: .all`. That flag, suite- or test-level,
makes every snapshot test write its baseline instead of comparing, so the visual gate goes green
while checking nothing. Recording flips are working state only (docs/TESTING.md) and must never
land. Only Swift can carry the flag, and reading the 105 MB of baseline PNGs beside the
simulator's boot took this check 42 to 54 s. Also fails when Tests/Visual/ is missing or grep
cannot search it.
CI's visual-tests job runs it before the build.
USAGE
    exit 2
fi

cd "$(dirname "${BASH_SOURCE[0]}")/.." || exit 2
# macOS grep exits 1, not 2, on a missing directory, so the status check below cannot see one.
if [ ! -d Tests/Visual ]; then
    echo "::error::Tests/Visual/ is missing, so this guard checked nothing."
    exit 1
fi
status=0
grep -rnF --include="*.swift" "record: .all" Tests/Visual/ || status=$?
if [ "$status" -eq 0 ]; then
    echo "::error::Committed .snapshots(record: .all) found — this disarms the Visual Regression gate. Revert to record: .never."
    exit 1
fi
if [ "$status" -ne 1 ]; then
    echo "::error::grep could not search Tests/Visual/ (exit $status), so this guard checked nothing."
    exit 1
fi
