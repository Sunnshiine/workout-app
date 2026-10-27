#!/bin/bash
set -uo pipefail

source_script=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/refuse-record-mode.sh
root=$(mktemp -d) || exit 3
trap 'rm -rf "$root"' EXIT
pass=0
fail=0

ok()  { pass=$((pass + 1)); printf '  ok   %s\n' "$1"; }
bad() { fail=$((fail + 1)); printf '  FAIL %s\n' "$1"; }

# Builds a fresh tree whose Tests/Visual/ holds $1 with the content $2, and prints the script's
# exit status.
status_for() {
    rm -rf "$root/repo"
    mkdir -p "$root/repo/scripts"
    cp "$source_script" "$root/repo/scripts/"
    if [ -n "$1" ]; then
        mkdir -p "$root/repo/Tests/Visual/$(dirname "$1")"
        printf '%s\n' "$2" >"$root/repo/Tests/Visual/$1"
    fi
    "$root/repo/scripts/refuse-record-mode.sh" >/dev/null 2>&1
    echo $?
}

expect() {
    local want=$1 label=$2 got
    got=$(status_for "$3" "$4")
    if [ "$got" = "$want" ]; then ok "$label"; else bad "$label, got exit $got"; fi
}

expect 0 "a suite that compares passes" Suite/AVisualTests.swift 'assertSnapshot(of: v, as: .image, record: .never)'
expect 1 "a committed record: .all fails" Suite/AVisualTests.swift '.snapshots(record: .all)'
expect 0 "only Swift can carry the flag" __Snapshots__/note.txt 'record: .all'
expect 1 "a missing Tests/Visual/ fails" "" ""

out=$("$source_script" extra 2>/dev/null; echo "exit=$?")
if [ "$out" = exit=2 ]; then ok "an argument exits 2"; else bad "an argument exits 2, got: $out"; fi

printf '%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" = 0 ]
