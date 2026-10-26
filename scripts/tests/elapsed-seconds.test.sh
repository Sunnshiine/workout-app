#!/usr/bin/env bash
# sim-lock.sh's wait_until_clear reports the whole seconds it waited, read from two `date +%s`
# calls around a predicate. A second can tick between them even with WORKOUT_ADMIT_WAIT=0, so a
# test that expects `gave up after 0 s` fails at random (#1032, #1134).
set -uo pipefail

scripts=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
self=tests/$(basename "${BASH_SOURCE[0]}")
pinned='(gave up|went ahead) after [0-9]+ ?s'

# Searches the files script-tests.yml runs. Returns 0 when none pins a count, 1 after printing the
# pinned lines, and 2 when git grep cannot search.
scan() {
    local hits
    hits=$(git -C "$1" grep --untracked -nE "$pinned" -- '*.test.sh' '*-test.sh' ":!$self" 2>&1)
    case $? in
        0)
            printf '%s\n' "$hits"
            return 1
            ;;
        1) return 0 ;;
        *)
            echo "git grep could not search $1: $hits"
            return 2
            ;;
    esac
}

for sample in 'gave up after 0 s' 'gave up after 0s' 'went ahead after 12 s'; do
    if ! printf '%s waiting for free disk\n' "$sample" | grep -Eq "$pinned"; then
        echo "  FAIL the pattern misses the pinned count in '$sample', so this test proves nothing: $pinned"
        exit 1
    fi
done

unsearchable=$(scan /nonexistent)
status=$?
case "$status $unsearchable" in
    "2 git grep could not search /nonexistent"*) ;;
    *)
        echo "  FAIL a directory git grep cannot search returns $status, not 2, so a broken search would pass: $unsearchable"
        exit 1
        ;;
esac

hits=$(scan "$scripts")
case $? in
    0)
        echo "  ok   no script test pins how many seconds wait_until_clear waited"
        exit 0
        ;;
    1) ;;
    *)
        echo "  FAIL $hits"
        exit 1
        ;;
esac
echo "  FAIL these lines expect an exact count of seconds that wait_until_clear waited, which the clock decides:"
printf '%s\n' "$hits" | sed 's/^/    /'
echo "  fix: bound the count, as in sed -E 's/after [0-2] s/after N s/', and expect 'after N s'"
exit 1
