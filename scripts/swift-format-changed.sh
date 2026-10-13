#!/bin/bash
set -euo pipefail

usage() {
    cat <<'EOF'
scripts/swift-format-changed.sh [--fix] [<base>]

Runs `xcrun swift-format lint --strict` on the Swift files this checkout changes since it left
<base>, committed or not, untracked ones included. <base> defaults to origin/main. CI's lint job
runs it with the pull request's base. Files nobody touched stay as they are, so a change never
inherits the formatting debt already on main.

--fix rewrites those files with `swift-format format -i` first, then lints them.

Exits 0 when every changed file is formatted or none changed; 1 when swift-format reports a file;
and 2 on a usage error or a <base> git cannot resolve.
EOF
}

fix=""
base=""
for arg in "$@"; do
    case "$arg" in
        -h | --help) usage; exit 0 ;;
        --fix) fix=1 ;;
        -*) usage >&2; exit 2 ;;
        *) [ -z "$base" ] || { usage >&2; exit 2; }; base=$arg ;;
    esac
done
base=${base:-origin/main}

cd "$(git rev-parse --show-toplevel)"
fork_point=$(git merge-base "$base" HEAD 2>/dev/null) || {
    echo "error: git cannot find where HEAD left '$base'." >&2
    exit 2
}

changed=$(
    {
        git diff --name-only --diff-filter=d "$fork_point" -- '*.swift'
        git ls-files --others --exclude-standard -- '*.swift'
    } | { grep -v '^scripts/tests/swiftlint-custom-rules/' || true; } | sort -u
)
files=()
while IFS= read -r file; do
    [ -z "$file" ] || files+=("$file")
done <<<"$changed"

if [ "${#files[@]}" -eq 0 ]; then
    echo "No changed Swift file to check since ${fork_point:0:7}."
    exit 0
fi
[ -z "$fix" ] || xcrun swift-format format -i "${files[@]}"
if ! xcrun swift-format lint --strict "${files[@]}"; then
    echo "error: format them with: xcrun swift-format format -i ${files[*]}" >&2
    exit 1
fi
echo "swift-format: ${#files[@]} changed Swift file(s) clean since ${fork_point:0:7}."
