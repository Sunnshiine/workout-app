#!/bin/bash
set -euo pipefail

if [ $# != 1 ]; then
    cat >&2 <<'USAGE'
Usage: scripts/keyboard-lane-paths.sh <base>
Prints run=true on stdout when the diff from <base> to HEAD touches a session view
(App/Views/Session*, App/Views/SmartValuePills.swift, App/Views/ActiveSetCard.swift) or a UI test
(Tests/UI/), and run=false otherwise, and names the paths that matched on stderr. CI's
visual-tests job appends stdout to GITHUB_OUTPUT and runs KeyboardLaneUITests on run=true.
Exits 2 on bad arguments and with git's status when the diff fails.
USAGE
    exit 2
fi

changed=$(git diff --name-only "$1" HEAD)
matched=$(printf '%s\n' "$changed" | grep -E '^(App/Views/(Session|SmartValuePills|ActiveSetCard)|Tests/UI/)') || [ $? = 1 ]
if [ -z "$matched" ]; then
    echo "keyboard lane: no session-view path changed" >&2
    echo run=false
    exit 0
fi
echo "keyboard lane: runs for" >&2
printf '%s\n' "$matched" | sed 's/^/  /' >&2
echo run=true
