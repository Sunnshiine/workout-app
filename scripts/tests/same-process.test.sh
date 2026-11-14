#!/usr/bin/env bash
# same-process.sh signals a saved pid only while it is still the process that was started, whatever
# locale or IFS its caller runs with.
set -uo pipefail

repo=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
# shellcheck source=scripts/same-process.sh
. "$repo/scripts/same-process.sh"
root=$(mktemp -d) || exit 3
trap 'rm -rf "$root"' EXIT
pass=0
fail=0
ok()  { pass=$((pass + 1)); printf '  ok   %s\n' "$1"; }
bad() { fail=$((fail + 1)); printf '  FAIL %s\n' "$1"; }
expect() { if [ "$2" = "$3" ]; then ok "$1"; else bad "$1"; printf '    got:  %s\n    want: %s\n' "$2" "$3"; fi; }

# A locale whose ps prints lstart in other words than C's, when the host has one.
other_locale=$(locale -a 2>/dev/null | grep -m1 -E '^(fr_FR|de_DE)\.UTF-8$')

sleep 30 &
child=$!
stamp=$(proc_stamp "$child")
expect "a live child has a stamp" "$([ -n "$stamp" ] && echo yes)" yes
if same_process "$child" "$stamp"; then ok "it is the same process"; else bad "it is the same process"; fi

if [ -n "$other_locale" ]; then
    expect "a stamp read under $other_locale is the one read under C" "$(LC_ALL=$other_locale proc_stamp "$child")" "$stamp"
    if LC_ALL=$other_locale same_process "$child" "$stamp"; then
        ok "a caller under $other_locale still finds it the same process"
    else
        bad "a caller under $other_locale still finds it the same process"
    fi
else
    echo "  skip no fr_FR or de_DE locale on this host"
fi

if (IFS=: same_process "$child" "$stamp"); then ok "a caller with IFS=: still finds it the same process"; else bad "a caller with IFS=: still finds it the same process"; fi

signal_same TERM "$child" "Thu Jan  1 00:00:00 1970"
status=$?
expect "a stamp that differs sends nothing and returns 3" "$status $(kill -0 "$child" 2>/dev/null && echo alive)" "3 alive"

signal_same TERM "$child" "" 2>"$root/err"
status=$?
expect "an empty stamp sends nothing and returns 3" "$status $(kill -0 "$child" 2>/dev/null && echo alive)" "3 alive"
expect "and says so in one line" "$(wc -l <"$root/err" | tr -d ' ') $(grep -c "no start time on record for pid $child" "$root/err")" "1 1"

signal_same TERM "$child" "$stamp"
wait "$child"
expect "the stamp it was started with reaches it" "$?" 143
if same_process "$child" "$stamp"; then bad "once it has exited it is not the same process"; else ok "once it has exited it is not the same process"; fi

printf '\n%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" = 0 ]
