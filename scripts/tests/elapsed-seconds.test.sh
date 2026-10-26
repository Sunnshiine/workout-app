#!/usr/bin/env bash
# sim-lock.sh's wait_until_clear reports the whole seconds it waited, read from two `date +%s`
# calls around a predicate. A second can tick between them even with WORKOUT_ADMIT_WAIT=0, so a
# test that expects `gave up after 0 s` fails at random (#1032, #1134).
set -uo pipefail

tests=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
self=$(basename "${BASH_SOURCE[0]}")
pinned='(gave up|went ahead) after [0-9]+ s'

if ! printf 'gave up after %s s waiting for free disk\n' 0 | grep -Eq "$pinned"; then
    echo "  FAIL the pattern misses a pinned count, so this test proves nothing: $pinned"
    exit 1
fi

hits=$(git -C "$tests" grep --untracked -nE "$pinned" -- . ":!$self")
if [ -z "$hits" ]; then
    echo "  ok   no script test pins how many seconds wait_until_clear waited"
    exit 0
fi
echo "  FAIL these lines expect an exact count of seconds that wait_until_clear waited, which the clock decides:"
printf '%s\n' "$hits" | sed 's/^/    /'
echo "  fix: normalize the count, as in sed -E 's/after [0-9]+ s/after N s/', and expect 'after N s'"
exit 1
