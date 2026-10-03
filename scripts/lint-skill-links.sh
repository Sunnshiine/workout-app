#!/usr/bin/env bash
# Claude Code loads a repo skill only through .claude/skills/<name>, a link to .agents/skills/<name>.
# A skill with no link never loads, and a link to a deleted skill loads nothing.
#
#   scripts/lint-skill-links.sh         check this checkout
#   scripts/lint-skill-links.sh <root>  check another tree (the tests use this)
set -euo pipefail

cd "${1:-$(dirname "${BASH_SOURCE[0]}")/..}"
shopt -s nullglob

skills=(.agents/skills/*/)
if [ "${#skills[@]}" -eq 0 ]; then
    echo "error: $(pwd)/.agents/skills holds no skill folder, so this run would check nothing." >&2
    exit 2
fi

failures=0
for dir in "${skills[@]}"; do
    name=$(basename "$dir")
    if [ ! -e ".claude/skills/$name" ] && [ ! -L ".claude/skills/$name" ]; then
        echo "error: .agents/skills/$name has no link in .claude/skills, so Claude Code cannot load it." >&2
        echo "       ln -s ../../.agents/skills/$name .claude/skills/$name" >&2
        failures=$((failures + 1))
    fi
done

for link in .claude/skills/*; do
    want="../../.agents/skills/$(basename "$link")"
    if [ ! -L "$link" ] || [ "$(readlink "$link")" != "$want" ] || [ ! -d "$link" ]; then
        now=$(readlink "$link" || echo "not a link")
        echo "error: $link must be a link to $want, an existing skill folder. It is: $now" >&2
        failures=$((failures + 1))
    fi
done

if [ "$failures" -gt 0 ]; then
    exit 1
fi
echo "==> Clean: ${#skills[@]} skills, each linked from .claude/skills"
