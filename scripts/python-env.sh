#!/usr/bin/env bash
set -uo pipefail

usage() {
  cat >&2 <<'EOF'
Usage: scripts/python-env.sh
A Claude Code SessionStart hook. Syncs the checkout's .venv from pyproject.toml and uv.lock, then
appends a line to $CLAUDE_ENV_FILE that puts .venv/bin first on PATH, so a bare python3 in this
session's shells imports Pillow and numpy.
Outside Claude Code, run `uv run python3` instead; it syncs the same .venv.
Prints one line only when the sync fails. Always exits 0, so a session never fails to start
because of this script.
EOF
  exit 2
}

[ $# -eq 0 ] || usage

root=${CLAUDE_PROJECT_DIR:-.}
cd "$root" 2>/dev/null && root=$PWD || exit 0
[ -f pyproject.toml ] || exit 0

if ! out=$(uv sync --frozen --quiet 2>&1); then
  echo "scripts/python-env.sh: uv sync failed, so python3 is the system one without Pillow or numpy." \
    "Run \`uv run python3\` instead. ${out%%$'\n'*}"
  exit 0
fi

[ -n "${CLAUDE_ENV_FILE:-}" ] || exit 0
bin=$root/.venv/bin
# The hook fires again on resume and compaction, appending to the same file.
printf 'case ":$PATH:" in *:%q:*) ;; *) export PATH=%q:"$PATH" ;; esac\n' "$bin" "$bin" >> "$CLAUDE_ENV_FILE"
exit 0
