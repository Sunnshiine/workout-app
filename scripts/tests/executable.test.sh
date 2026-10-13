#!/bin/bash
set -uo pipefail

tests=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
not_executable=$(git -C "$tests" ls-files -s -- '*.test.sh' | awk '$1 != "100755" { print "  " $1 " scripts/tests/" $4 }')
if [ -z "$not_executable" ]; then
    echo "  ok   every scripts/tests/*.test.sh is committed executable"
    exit 0
fi
echo "  FAIL these tests are committed without the executable bit, so running one directly exits 126:"
echo "$not_executable"
echo "  fix: git update-index --chmod=+x <file>"
exit 1
