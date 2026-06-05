#!/usr/bin/env bash
#
# Compatibility entrypoint for the Python Ralph PR orchestrator.
#
# The shell-owned orchestration was retired after the Python path passed local
# tests and the live fake-engine GitHub dry-run. Keep this file so existing
# `ralph/ralph.sh ...` invocations continue to work while Python owns all
# selection, routing, gates, publication, and lifecycle state.
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(git -C "$SCRIPT_DIR" rev-parse --show-toplevel)"

if ! command -v uv >/dev/null 2>&1; then
  echo "error: uv is required to run Python Ralph; install uv and retry." >&2
  exit 127
fi

cd "$REPO_ROOT"
exec uv run --python 3.11 python -m ralph.orchestrator "$@"
