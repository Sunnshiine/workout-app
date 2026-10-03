#!/usr/bin/env bash
set -euo pipefail

cd "${1:-$(dirname "${BASH_SOURCE[0]}")/..}" || exit 2
shopt -s nullglob

skills=(.agents/skills/*/SKILL.md)
if [ "${#skills[@]}" -eq 0 ]; then
    echo "error: $(pwd)/.agents/skills holds no <name>/SKILL.md, so this run would check nothing." >&2
    exit 2
fi

failures=0
for skill in "${skills[@]}"; do
    name=$(basename "$(dirname "$skill")")
    if [ ! -e ".claude/skills/$name" ] && [ ! -L ".claude/skills/$name" ]; then
        echo "error: .agents/skills/$name has no link in .claude/skills, so Claude Code cannot load it." >&2
        echo "       ln -s ../../.agents/skills/$name .claude/skills/$name" >&2
        failures=$((failures + 1))
    fi
done

for link in .claude/skills/*; do
    want="../../.agents/skills/$(basename "$link")"
    if [ "$(readlink "$link")" != "$want" ]; then
        now=$(readlink "$link" || echo "not a link")
        echo "error: $link must be the link $want. It is: $now" >&2
        failures=$((failures + 1))
    elif [ ! -f "$link/SKILL.md" ]; then
        echo "error: $link points at $want, which holds no SKILL.md. Delete the link or restore the skill." >&2
        failures=$((failures + 1))
    fi
done

if [ "$failures" -gt 0 ]; then
    exit 1
fi
echo "==> Clean: ${#skills[@]} skills, each linked from .claude/skills"
