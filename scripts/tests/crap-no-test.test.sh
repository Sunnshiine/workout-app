#!/bin/bash
set -uo pipefail

# --no-test reuses the profile a crap.sh run wrote. With none, the failure says what to run.

script="${CRAP_SCRIPT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/crap.sh}"
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
mkdir -p "$work/scripts"
cp "$script" "$work/scripts/crap.sh"
failures=0

check() {
    if [ "$2" = "$3" ]; then echo "ok: $1"; else echo "FAIL: $1 (got '$2')"; failures=$((failures + 1)); fi
}

out=$("$work/scripts/crap.sh" gate --no-test 2>&1)
check "no profile: exits 1" "$?" 1
case $out in
    *"no coverage profile"*"plain swift test"*"scripts/crap.sh gate without --no-test"*) found=yes ;;
    *) found=no ;;
esac
check "no profile: names the cause and the command to run" "$found" yes

case $("$script" --help) in
    *"plain swift test writes none"*) found=yes ;;
    *) found=no ;;
esac
check "help explains what --no-test needs" "$found" yes

[ "$failures" -eq 0 ]
