#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat >&2 <<'EOF'
Usage: scripts/warn-stale-checkout.sh
Prints one warning when this is the repository's primary checkout and HEAD is not the
last-fetched origin/main, so an agent session does not read stale files and report what it
finds there as the state of main.
Silent inside a linked worktree, on a main that is level with origin/main, and outside a git
repository. Reads only the last-fetched state and makes no network call.
Always exits 0, so a session never fails to start because of this script.
EOF
  exit 2
}

[ $# -eq 0 ] || usage

cd "${CLAUDE_PROJECT_DIR:-.}" 2>/dev/null || exit 0

# Every check below is a reason to stay silent. Falling past all of them is the warning.

git_dir=$(git rev-parse --path-format=absolute --git-dir 2>/dev/null) || exit 0
common_dir=$(git rev-parse --path-format=absolute --git-common-dir)
if [ "$git_dir" != "$common_dir" ]; then
  exit 0
fi

git rev-parse --verify --quiet origin/main >/dev/null || exit 0

counts=$(git rev-list --left-right --count origin/main...HEAD)
behind=${counts%%[[:space:]]*}
ahead=${counts##*[[:space:]]}

branch=$(git symbolic-ref --quiet --short HEAD) || branch="detached HEAD at $(git rev-parse --short HEAD)"

if [ "$branch" = main ] && [ "$behind" -eq 0 ]; then
  exit 0
fi

cat <<EOF
Stale checkout warning from scripts/warn-stale-checkout.sh

This session is running in the primary checkout, and HEAD is not the last-fetched origin/main.
Files you read here are not main's content.

  branch     $branch
  distance   $ahead ahead, $behind behind origin/main

Read main through git rather than grepping this checkout.
  git show origin/main:<path>
  git ls-tree -r --name-only origin/main

To change files, work in a worktree cut from origin/main.
  git worktree add .claude/worktrees/<name> -b <branch> origin/main
EOF
