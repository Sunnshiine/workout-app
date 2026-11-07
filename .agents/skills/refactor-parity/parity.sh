#!/bin/bash
# Runs every scenario under scenarios/ through the workout CLI built at BASE and at HEAD
# (default: this tree's working state) and diffs what each prints and persists. A refactor
# should change nothing observable, so any diff is a behaviour change.
set -euo pipefail

usage() {
    cat <<'EOF'
usage: .agents/skills/refactor-parity/parity.sh [--keep] [<base> [<head>]] [scenario.txt ...]

Builds `workout` at BASE and HEAD in a scratch tree (cached by tree hash under
.build/parity/bin), runs each scenario in one fixed home with a frozen clock, and prints a
unified diff of the two transcripts. BASE defaults to the merge base of HEAD and origin/main.
HEAD defaults to the working tree, uncommitted edits included. Scenarios default to every file in
scenarios/ beside this script. Exit 0: no diff. 1: a diff. 2: usage or build failure.

A scenario line is a workout command without the `workout`, or one of:
  coach <cell> <value...>   set a cell of the first tab in workbook.json, as the coach would
  observe                   status, session for every Session, and sheet
A scenario with a command BASE rejects as a usage error (64) and HEAD accepts is skipped.
EOF
}

keep=0
while [ $# -gt 0 ]; do
    case $1 in
        --keep) keep=1; shift ;;
        -h | --help) usage; exit 0 ;;
        -*) usage >&2; exit 2 ;;
        *) break ;;
    esac
done

script_dir=$(cd "$(dirname "$0")" && pwd)
caller=$(git rev-parse --show-toplevel)
# shellcheck source=scripts/scratch-tree.sh
. "$caller/scripts/scratch-tree.sh"
cd "$caller"

if [ $# -gt 0 ] && [[ $1 != *.txt ]]; then
    base=$(git rev-parse --verify "$1^{commit}") || exit 2
    shift
else
    base=$(git merge-base HEAD origin/main) || { echo "no merge base with origin/main; pass BASE" >&2; exit 2; }
fi
head_commit=HEAD head_tree=""
if [ $# -gt 0 ] && [[ $1 != *.txt ]]; then
    head_commit=$(git rev-parse --verify "$1^{commit}") || exit 2
    shift
else
    head_tree=$(scratch_snapshot)
fi
scenarios=("$@")
[ ${#scenarios[@]} -gt 0 ] || scenarios=("$script_dir"/scenarios/*.txt)

cache=$caller/.build/parity/bin
mkdir -p "$cache"

# Prints the cached binary for COMMIT (plus TREE when given), building it in the scratch slot.
binary_for() {
    local key=${2:-$(git rev-parse "$1^{tree}")}
    if [ ! -x "$cache/$key/workout" ]; then
        [ -n "${scratch:-}" ] || scratch_claim "refactor-parity/parity.sh"
        scratch_sync "$1" "${2:-}"
        (cd "$scratch" && swift build --product workout >&2) || { echo "build failed at $1" >&2; exit 2; }
        mkdir -p "$cache/$key"
        cp "$scratch/.build/debug/workout" "$cache/$key/workout"
    fi
    echo "$cache/$key/workout"
}

coach() {
    python3 - "$home/workbook.json" "$@" <<'PY'
import json, sys
path, cell, value = sys.argv[1], sys.argv[2], " ".join(sys.argv[3:])
book = json.load(open(path))
cells = next(iter(book["tabs"].values()))["cells"]
if value: cells[cell] = value
else: cells.pop(cell, None)
json.dump(book, open(path, "w"), indent=2, sort_keys=True)
PY
}

# Runs one command, appending it, its exit code, stdout, stderr, and a digest of the home's
# files to the transcript. Returns the command's exit code.
step() {
    local status=0
    printf '$ %s\n' "$*" >>"$out"
    "$bin" "$@" >>"$out" 2>"$work/stderr" || status=$?
    printf -- '-- exit %s\n' "$status" >>"$out"
    [ ! -s "$work/stderr" ] || { echo "-- stderr"; cat "$work/stderr"; } >>"$out"
    (cd "$home" && shasum workbook.json settings.json manifest.json 2>/dev/null) | sed 's/^/-- /' >>"$out" || true
    return "$status"
}

observe() {
    step status || true
    for id in $("$bin" status 2>/dev/null | python3 -c 'import json,sys; print(" ".join(s["id"] for s in json.load(sys.stdin).get("sessions", [])))'); do
        step session "$id" || true
    done
    step sheet || true
}

# Runs SCENARIO with BIN into OUT. Returns 64 when BIN rejected a command as a usage error.
run() {
    bin=$1 scenario=$2 out=$3
    : >"$out"
    rm -rf "$home"
    local line status usage=0
    while IFS= read -r line || [ -n "$line" ]; do
        case $line in '' | '#'*) continue ;; esac
        eval "set -- $line"
        case $1 in
            coach) shift; printf '$ coach %s\n' "$*" >>"$out"; coach "$@" ;;
            observe) observe ;;
            *) status=0; step "$@" || status=$?; [ "$status" != 64 ] || usage=64 ;;
        esac
    done <"$scenario"
    for f in workbook.json settings.json manifest.json; do
        printf '== %s\n' "$f" >>"$out"
        cat "$home/$f" >>"$out" 2>/dev/null || echo "(absent)" >>"$out"
    done
    return $usage
}

base_bin=$(binary_for "$base")
head_bin=$(binary_for "$head_commit" "$head_tree")

work=$(mktemp -d "${TMPDIR:-/tmp}/parity.XXXXXX")
[ $keep = 1 ] || trap 'rm -rf "$work"' EXIT
home=$work/home
export WORKOUT_HOME=$home WORKOUT_NOW=2026-05-28T20:26:40Z TZ=America/New_York LC_ALL=en_US.UTF-8

diffs=0 skipped=0 clean=0
for scenario in "${scenarios[@]}"; do
    name=$(basename "$scenario" .txt)
    base_status=0 head_status=0
    run "$base_bin" "$scenario" "$work/$name.base" || base_status=$?
    run "$head_bin" "$scenario" "$work/$name.head" || head_status=$?
    if [ "$base_status" = 64 ] && [ "$head_status" != 64 ]; then
        echo "skip $name: base rejects a command head accepts"
        skipped=$((skipped + 1))
    elif diff -u --label "$name@base" --label "$name@head" "$work/$name.base" "$work/$name.head"; then
        clean=$((clean + 1))
    else
        diffs=$((diffs + 1))
    fi
done
echo "parity: $clean clean, $diffs differ, $skipped skipped (base ${base:0:8}, head ${head_tree:+working tree of }$(git rev-parse --short "$head_commit"))"
[ $keep = 0 ] || echo "transcripts: $work"
[ $diffs = 0 ]
