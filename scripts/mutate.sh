#!/bin/bash
set -euo pipefail

usage() {
    cat <<'EOF'
Usage: scripts/mutate.sh [--filter SEL]... FILE SED_EXPR [SED_EXPR...]

Proves that a test pins a line: each mutant is one change to the code, and some test must fail on it.
Every mutant builds and runs in a scratch tree under the primary checkout's .build/scratch/, never
in your worktree. Your uncommitted and untracked files are part of what gets mutated. The untouched
snapshot must pass first; then each mutant runs alone.

  FILE SED_EXPR  hand-written mutants, one sed command each with its own address, such as
                 '67s/failed: /exploded: /'. An expression that changes nothing is an error.
  --filter SEL   the tests that judge each mutant, as swift test --filter SEL; repeatable.
                 Default: the whole suite.

Prints log:, scratch:, and baseline: lines, then one row per mutant as it finishes:
  OUTCOME  FILE:LINE  OP  CHANGE  FIRST-KILLER +N | REASON
  killed       a test failed; results.tsv in the log dir lists every one
  SURVIVED     no test failed, so nothing pins this change (grep '^SURVIVED')
  nocompile    the mutant does not build
  error        the runner failed without naming a failing test
Exits 0 when every mutant was killed, 1 when any SURVIVED, did not compile, or hit an error,
2 on usage or a failing baseline, 75 when every scratch tree is busy.
EOF
}

script_dir=$(cd "$(dirname "$0")" && pwd)
# shellcheck source=scripts/scratch-tree.sh
. "$script_dir/scratch-tree.sh"

die() {
    echo "$1" >&2
    exit 2
}
need_value() { [ "$1" -ge 2 ] || { usage >&2; exit 2; }; }

filters=()
while [ $# -gt 0 ]; do
    case $1 in
        --filter) need_value $#; filters+=("$2"); shift 2 ;;
        -h | --help) usage; exit 0 ;;
        -*) usage >&2; exit 2 ;;
        *) break ;;
    esac
done
[ $# -ge 2 ] || { usage >&2; exit 2; }

caller=$(git rev-parse --show-toplevel)
caller_physical=$(cd "$caller" && pwd -P)
file_dir=$(cd "$(dirname "$1")" 2>/dev/null && pwd -P) || die "$1: no such directory"
case $file_dir/ in
    "$caller_physical"/*) file=${file_dir#"$caller_physical"}/$(basename "$1"); file=${file#/} ;;
    *) die "$1 is outside $caller" ;;
esac
shift
cd "$caller"

swift_filters=()
for sel in ${filters[@]+"${filters[@]}"}; do swift_filters+=(--filter "$sel"); done
runner="swift test${swift_filters[*]+ ${swift_filters[*]}}"

run=$caller/.build/mutate/$(date +%Y%m%d-%H%M%S)-$$
mkdir -p "$run"
echo "log: $run"

head=$(git rev-parse HEAD)
tree=$(scratch_snapshot)
git cat-file -e "$tree:$file" 2>/dev/null || die "$file is not in your working tree (an ignored file cannot be mutated)"
git show "$tree:$file" >"$run/orig.swift"
n=0
for expr in "$@"; do
    n=$((n + 1))
    case $expr in *$'\t'*) die "'$expr' holds a tab; write it as [[:space:]] or \\t" ;; esac
    sed "$expr" "$run/orig.swift" >"$run/m$n.swift" || die "sed rejected '$expr'"
    ! cmp -s "$run/orig.swift" "$run/m$n.swift" || die "'$expr' changed nothing in $file; check its address"
    line=$(printf '%s\n' "$expr" | sed -nE 's/^([0-9]+).*/\1/p')
    printf 'm%s\t%s\t%s\tsed\t%s\t\n' "$n" "$file" "${line:--}" "$expr" >>"$run/mutants.tsv"
done

strip_color() { sed $'s/\033\\[[0-9;]*m//g' "$1"; }
first_error() { strip_color "$1" | { grep -m1 'error:' || true; } | sed "s#$scratch/##"; }
test_count() {
    awk '/ Test run with [0-9]+ tests? / { for (i = 1; i < NF; i++) if ($i == "with") { run = $(i + 1); break } }
         /Executed [0-9]+ tests?, with/ { for (i = 1; i < NF; i++) if ($i == "Executed") executed = $(i + 1) }
         END { print run + executed }' "$1"
}

# Sets result (pass, fail, nocompile, error), tests, killers (one per line), and reason.
run_check() {
    local log=$1 rc=0
    result="" tests=0 killers="" reason=""
    if ! (cd "$scratch" && swift build --build-tests) </dev/null >"$log" 2>&1; then
        result=nocompile
        reason=$(first_error "$log")
        return
    fi
    (cd "$scratch" && swift test --skip-build ${swift_filters[@]+"${swift_filters[@]}"}) </dev/null >>"$log" 2>"$run/stderr" || rc=$?
    cat "$run/stderr" >>"$log"
    killers=$(awk -f "$script_dir/test-failures.awk" "$log")
    tests=$(test_count "$log")
    if [ -n "$killers" ]; then
        result=fail
    elif [ $rc = 0 ]; then
        result=pass
    else
        result=error
        reason="exit $rc: $(head -1 "$run/stderr")"
    fi
}

scratch_claim "mutate.sh in $caller"
scratch_sync "$head" "$tree"
if [ "$tree" = "$(git rev-parse "$head^{tree}")" ]; then
    echo "scratch: $scratch at ${head:0:8}"
else
    echo "scratch: $scratch at ${head:0:8} + your uncommitted changes"
fi

run_check "$run/baseline.log"
if [ "$result" != pass ] || [ "$tests" = 0 ]; then
    echo "the untouched snapshot must pass before mutating; $runner reports:" >&2
    case $result in
        fail) sed 's/^/  failed: /' <<<"$killers" >&2 ;;
        nocompile) echo "  did not compile: $reason" >&2 ;;
        error) echo "  $reason" >&2 ;;
        pass) echo "  no tests ran; check --filter" >&2 ;;
    esac
    echo "  log: $run/baseline.log" >&2
    exit 2
fi
echo "baseline: passed $tests tests ($runner)"

loc_width=$(awk -F'\t' '{ w = length($2 ":" $3); if (w > max) max = w } END { print max }' "$run/mutants.tsv")
change_width=$(awk -F'\t' '{ w = length($5 ($6 == "" ? "" : " -> " $6)); if (w > max) max = w } END { print max }' "$run/mutants.tsv")
print_row() {
    local row
    row=$(printf "%-11s  %-${loc_width}s  %-7s  %-${change_width}s  %s" "$@")
    printf '%s\n' "${row%"${row##*[! ]}"}"
}

killed=0 survived=0 nocompile=0 errors=0 total=0
while IFS=$'\t' read -r id mfile line op before after <&3; do
    total=$((total + 1))
    cp "$run/$id.swift" "$scratch/$mfile"
    run_check "$run/$id.log"
    git -C "$scratch" checkout -q "$tree" -- "$mfile"
    case $result in
        fail)
            outcome=killed detail=$(head -1 <<<"$killers") more=$(($(wc -l <<<"$killers") - 1))
            [ $more = 0 ] || detail="$detail +$more"
            killed=$((killed + 1))
            printf '%s\tkilled\t%s\n' "$id" "$(tr '\n' ';' <<<"$killers" | sed 's/;$//; s/;/; /g')" >>"$run/results.tsv"
            ;;
        pass) outcome=SURVIVED detail="" survived=$((survived + 1)) ;;
        nocompile) outcome=nocompile detail=$reason nocompile=$((nocompile + 1)) ;;
        error) outcome=error detail=$reason errors=$((errors + 1)) ;;
    esac
    [ "$outcome" = killed ] || printf '%s\t%s\t%s\n' "$id" "$outcome" "$detail" >>"$run/results.tsv"
    print_row "$outcome" "$mfile:$line" "$op" "$before${after:+ -> $after}" "$detail"
done 3<"$run/mutants.tsv"

counts=""
for pair in "$killed killed" "$survived SURVIVED" "$nocompile nocompile" "$errors error"; do
    [ "${pair%% *}" = 0 ] || counts="$counts, $pair"
done
[ "$total" = 1 ] && noun=mutant || noun=mutants
echo "$total $noun: ${counts#, }"
[ $((survived + nocompile + errors)) = 0 ]
