#!/bin/bash
set -euo pipefail

usage() {
    cat <<'EOF'
Usage: scripts/mutate.sh [--sim UDID] [--filter SEL]... FILE SED_EXPR [SED_EXPR...]
       scripts/mutate.sh [--sim UDID] [--filter SEL]... [--max N] --diff BASE [PATH...]

Proves that a test pins a line: each mutant is one change to the code, and some test must fail on it.
Every mutant builds and runs in a scratch tree under the primary checkout's .build/scratch/, never
in your worktree. Your uncommitted and untracked files are part of what gets mutated. The untouched
snapshot must pass first; then each mutant runs alone.

  FILE SED_EXPR  hand-written mutants, one sed command each with its own address, such as
                 '67s/failed: /exploded: /'. An expression that changes nothing is an error.
  --diff BASE    generates mutants on the lines changed since merge-base(BASE, HEAD), uncommitted
                 edits included: true/false flips, comparison and &&/|| swaps, if-negation, guard
                 forced to its early return, a number + 1, in the .swift files under each PATH
                 (from the current directory; default Sources App WorkoutShared WorkoutWidgets).
  --max N        runs at most N generated mutants (default 40); unreachable ones never count.
  --filter SEL   the tests that judge each mutant; repeatable. Without --sim: swift test --filter
                 SEL (default the whole suite). With --sim: unit, visual, ui, or a test-sim.sh
                 TEST-ID; a bare suite name means WorkoutTrackerTests/SUITE (default unit).
  --sim UDID     runs every check through the scratch tree's scripts/test-sim.sh --sim UDID.
                 swift test compiles only Sources/, so App/, WorkoutShared/, and WorkoutWidgets/
                 need --sim. Run Sources/ without --sim (seconds) and those with --sim PATH.
MUTATE_TIMEOUT=N bounds each run in seconds (default 5 x the baseline's time, at least 120).

Prints log:, mutants: (--diff), scratch:, and baseline: lines, then a row per mutant as it ends:
  OUTCOME  FILE:LINE  OP  CHANGE  FIRST-KILLER +N | REASON
  killed       a test failed, crashed, or the run timed out; results.tsv lists every killer
  SURVIVED     no test failed, and an #error on the line breaks the build (grep '^SURVIVED')
  nocompile    the compiler rejects the mutated file
  unreachable  this build never compiles the line (#if, no target; App/ needs --sim)
  error        the runner failed without naming a failing test, or the build failed elsewhere
Exits 0 when every mutant was killed (a generated nocompile does not count); 1 when any SURVIVED,
was unreachable, hit an error, or was a hand-written nocompile, when --max left any unrun, or when
none was killed; 2 on usage or a failing baseline; 75 when every scratch tree or the simulator is
busy (the rows so far print first).
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
plural() { if [ "$1" = 1 ]; then echo "$1 $2"; else echo "$1 ${2}s"; fi; }

sim="" base="" max=40 filters=()
while [ $# -gt 0 ]; do
    case $1 in
        --sim) need_value $#; sim=$2; shift 2 ;;
        --filter) need_value $#; filters+=("$2"); shift 2 ;;
        --diff) need_value $#; base=$2; shift 2 ;;
        --max) need_value $#; max=$2; shift 2 ;;
        -h | --help) usage; exit 0 ;;
        -*) usage >&2; exit 2 ;;
        *) break ;;
    esac
done
case $max in '' | *[!0-9]* | 0) die "--max takes a whole number above 0, not '$max'" ;; esac
[ -n "$base" ] || [ $# -ge 2 ] || { usage >&2; exit 2; }

caller=$(git rev-parse --show-toplevel)
caller_physical=$(cd "$caller" && pwd -P)
# Sets rel to a path given from the current directory, made relative to the repo root.
repo_path() {
    local dir name=""
    if [ -d "$1" ]; then
        dir=$(cd "$1" && pwd -P)
    else
        dir=$(cd "$(dirname "$1")" 2>/dev/null && pwd -P) || die "$1: no such file or directory"
        name=/$(basename "$1")
    fi
    case $dir/ in
        "$caller_physical"/*) rel=${dir#"$caller_physical"}$name; rel=${rel#/}; rel=${rel:-.} ;;
        *) die "$1 is outside $caller" ;;
    esac
}
paths=()
if [ -z "$base" ]; then
    repo_path "$1"
    file=$rel
    shift
else
    for path in "$@"; do
        repo_path "$path"
        paths+=("$rel")
    done
fi
cd "$caller"

# Mirrors Package.swift: the test target compiles Sources/ and Tests/ minus UI, Visual, and GoogleAuthTests.
swift_compiles() {
    case $1 in
        Tests/Unit/GoogleAuthTests.swift) return 1 ;;
        Sources/* | Tests/Unit/* | Tests/Component/* | Tests/Support/*) return 0 ;;
        *) return 1 ;;
    esac
}
reachable() { [ -n "$sim" ] || swift_compiles "$1"; }
[ -n "$base" ] || reachable "$file" ||
    die "swift test never compiles $file; mutate it with --sim UDID, which runs scripts/test-sim.sh in the scratch tree"

swift_filters=() selections=()
for sel in ${filters[@]+"${filters[@]}"}; do
    swift_filters+=(--filter "$sel")
    case $sel in
        unit | visual | ui | all | */*) selections+=("$sel") ;;
        *) selections+=("WorkoutTrackerTests/$sel") ;;
    esac
done
[ ${#selections[@]} -gt 0 ] || selections=(unit)
if [ -n "$sim" ]; then
    runner="test-sim.sh --sim $sim ${selections[*]}"
else
    runner="swift test${swift_filters[*]+ ${swift_filters[*]}}"
fi

run=$caller/.build/mutate/$(date +%Y%m%d-%H%M%S)-$$
mkdir -p "$run"
echo "log: $run"

head=$(git rev-parse HEAD)
tree=$(scratch_snapshot)
: >"$run/mutants.tsv"
dropped=0
if [ -z "$base" ]; then
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
    runnable=$n
else
    merge_base=$(git merge-base "$base" HEAD 2>/dev/null) || die "no merge base between $base and HEAD"
    for path in ${paths[@]+"${paths[@]}"}; do
        git ls-tree -r --name-only "$tree" -- "$path" >"$run/files"
        [ -s "$run/files" ] || die "$path matches no file in your working tree (an ignored file cannot be mutated)"
    done
    [ ${#paths[@]} -gt 0 ] || paths=(Sources App WorkoutShared WorkoutWidgets)
    git diff --name-only --no-renames --diff-filter=AM "$merge_base" "$tree" -- "${paths[@]}" >"$run/files"
    : >"$run/runnable.tsv"
    : >"$run/unreachable.tsv"
    : >"$run/sources.tsv"
    k=0 changed=0
    while IFS= read -r f; do
        case $f in Sources/*.swift | App/*.swift | WorkoutShared/*.swift | WorkoutWidgets/*.swift) ;; *) continue ;; esac
        k=$((k + 1))
        git show "$tree:$f" >"$run/source$k.swift"
        printf '%s\t%s\n' "$f" "$run/source$k.swift" >>"$run/sources.tsv"
        git diff -U0 --no-color "$merge_base" "$tree" -- "$f" |
            awk '/^@@/ { n = split(substr($3, 2), r, ","); count = n > 1 ? r[2] : 1; for (i = 0; i < count; i++) print r[1] + i }' >"$run/changed$k"
        changed=$((changed + $(wc -l <"$run/changed$k")))
        rows=$run/unreachable.tsv
        ! reachable "$f" || rows=$run/runnable.tsv
        awk -v changed="$run/changed$k" -v path="$f" -f "$script_dir/mutants.awk" "$run/source$k.swift" >>"$rows"
    done <"$run/files"
    runnable=$(($(wc -l <"$run/runnable.tsv")))
    generated=$((runnable + $(wc -l <"$run/unreachable.tsv")))
    [ "$runnable" -le "$max" ] || dropped=$((runnable - max)) runnable=$max
    echo "mutants: $generated on $(plural "$changed" "changed line") in $(plural $k file) since ${merge_base:0:8}"
    [ "$generated" -gt 0 ] || exit 0
    # mutants.awk prints the whole mutated line last, so it is read from the file, never through -v,
    # which would rewrite its backslashes.
    { head -n "$max" "$run/runnable.tsv"; cat "$run/unreachable.tsv"; } | awk -F'\t' -v run="$run" '
        FNR == NR { source[$1] = $2; next }
        {
            id = "m" FNR
            mutated = $0
            for (i = 1; i <= 5; i++) sub(/^[^\t]*\t/, "", mutated)
            print id "\t" $1 "\t" $2 "\t" $3 "\t" $4 "\t" $5 > (run "/mutants.tsv")
            out = run "/" id ".swift"
            n = 0
            while ((getline text < source[$1]) > 0) print (++n == $2 ? mutated : text) > out
            close(source[$1])
            close(out)
        }' "$run/sources.tsv" -
fi

# One line for a table row: absolute paths shortened to their last component, at most 120 characters.
one_line() {
    local s
    s=$(head -1 <<<"$1" | sed -E "s#(^|[ '\"(])/[^ '\"]*/#\1#g")
    [ ${#s} -le 120 ] || s="${s:0:117}..."
    printf '%s\n' "$s"
}
read_log() { awk -v mode="$1" -v root="$scratch/" -f "$script_dir/test-log.awk" "$2"; }

# Runs a command in a new session for at most $1 seconds, then kills its whole process group and
# exits 124. close_fds=False keeps the slot lock on fd 8 in every child. A signal to this script
# kills the group too, so a hung build never outlives the run and holds its slot.
limited() {
    python3 -c 'import os, signal, subprocess, sys
p = subprocess.Popen(sys.argv[2:], start_new_session=True, close_fds=False)
def stop(*_):
    os.killpg(p.pid, signal.SIGKILL)
    sys.exit(124)
for s in (signal.SIGINT, signal.SIGTERM, signal.SIGHUP): signal.signal(s, stop)
try: rc = p.wait(timeout=max(1, int(sys.argv[1])))
except subprocess.TimeoutExpired: stop()
sys.exit(128 - rc if rc < 0 else rc)' "$@"
}

# Sets result (pass, fail, nocompile, error, timeout, busy), tests, killers (one per line), and
# reason. The whole check gets $limit seconds. With a second argument the swift runner only builds.
run_check() {
    local log=$1 build_only=${2:-} rc=0 test_log start=$SECONDS
    result="" tests=0 killers="" reason=""
    if [ -n "$sim" ]; then
        limited "$limit" "$scratch/scripts/test-sim.sh" --sim "$sim" "${selections[@]}" </dev/null >"$run/stdout" 2>"$run/stderr" || rc=$?
        cat "$run/stdout" "$run/stderr" >"$log"
        if [ $rc = 124 ]; then
            result=timeout reason="timed out after ${limit}s"
            return
        fi
        if [ $rc = 75 ]; then
            result=busy
            reason=$(cat "$run/stderr")
            return
        fi
        if [ $rc = 65 ] && grep -q '^build log: ' "$run/stderr"; then
            result=nocompile
            reason=$(read_log first-error "$run/stderr")
            return
        fi
        test_log=$(sed -n 's/^log: //p' "$run/stdout" | tail -1)
        [ -z "$test_log" ] || [ ! -f "$test_log" ] || cp "$test_log" "$log"
    else
        (cd "$scratch" && limited "$limit" swift build --build-tests) </dev/null >"$log" 2>&1 || rc=$?
        if [ $rc = 0 ] && [ -n "$build_only" ]; then
            result=pass
            return
        elif [ $rc = 0 ]; then
            (cd "$scratch" && limited $((limit - (SECONDS - start))) swift test --skip-build ${swift_filters[@]+"${swift_filters[@]}"}) \
                </dev/null >>"$log" 2>"$run/stderr" || rc=$?
            cat "$run/stderr" >>"$log"
        elif [ $rc != 124 ]; then
            result=nocompile
            reason=$(read_log first-error "$log")
            return
        fi
        if [ $rc = 124 ]; then
            result=timeout reason="timed out after ${limit}s"
            return
        fi
    fi
    killers=$(read_log failures "$log")
    tests=$(read_log count "$log")
    if [ -n "$killers" ]; then
        result=fail
    elif [ $rc = 0 ]; then
        result=pass
    else
        result=error
        reason="exit $rc: $(head -1 "$run/stderr")"
    fi
}

# A mutant that survives may sit on a line this build never compiles: an inactive #if branch, or a
# file in no target the runner builds. Rebuilds the snapshot with an #error just above the mutated
# line; when that still builds, the mutant could not have been judged, so result becomes unreachable.
probe_reach() {
    local id=$1 mfile=$2 at=$3
    git show "$tree:$mfile" >"$run/$id.orig"
    case $at in '' | *[!0-9]*) at=$(cmp "$run/$id.orig" "$run/$id.swift" | sed -n 's/.*, line //p') ;; esac
    [ -n "$at" ] || return 0
    awk -v n="$at" 'FNR == n { print "#error(\"mutate.sh reach probe\")" } { print }' "$run/$id.orig" >"$scratch/$mfile"
    run_check "$run/$id.probe.log" build-only
    git -C "$scratch" checkout -q "$tree" -- "$mfile"
    case $result in
        busy) ;;
        nocompile | timeout) result=pass reason="" ;;
        *) result=unreachable reason="compiled out of this build (#if or no target)" ;;
    esac
}

if [ $runnable -gt 0 ]; then
    scratch_claim "mutate.sh in $caller"
    scratch_sync "$head" "$tree"
    if [ "$tree" = "$(git rev-parse "$head^{tree}")" ]; then
        echo "scratch: $scratch at ${head:0:8}"
    else
        echo "scratch: $scratch at ${head:0:8} + your uncommitted changes"
    fi

    limit=${MUTATE_TIMEOUT:-1800} start=$SECONDS
    run_check "$run/baseline.log"
    limit=${MUTATE_TIMEOUT:-$((5 * (SECONDS - start) > 120 ? 5 * (SECONDS - start) : 120))}
    if [ "$result" = busy ]; then
        echo "$reason" >&2
        exit 75
    fi
    if [ "$result" != pass ] || [ "$tests" = 0 ]; then
        echo "the untouched snapshot must pass before mutating; $runner reports:" >&2
        case $result in
            fail) sed 's/^/  failed: /' <<<"$killers" >&2 ;;
            nocompile) echo "  did not compile: $reason" >&2 ;;
            error | timeout) echo "  $reason" >&2 ;;
            pass) echo "  no tests ran; check --filter" >&2 ;;
        esac
        echo "  log: $run/baseline.log" >&2
        exit 2
    fi
    echo "baseline: passed $(plural "$tests" test) ($runner)"
fi

loc_width=$(awk -F'\t' '{ w = length($2 ":" $3); if (w > max) max = w } END { print max }' "$run/mutants.tsv")
change_width=$(awk -F'\t' '{ w = length($5 ($6 == "" ? "" : " -> " $6)); if (w > max) max = w } END { print max }' "$run/mutants.tsv")
print_row() {
    local row
    row=$(printf "%-11s  %-${loc_width}s  %-7s  %-${change_width}s  %s" "$@")
    printf '%s\n' "${row%"${row##*[! ]}"}"
}

killed=0 survived=0 nocompile=0 unreachable=0 errors=0 total=0 busy=""
while IFS=$'\t' read -r id mfile line op before after <&3; do
    if reachable "$mfile"; then
        cp "$run/$id.swift" "$scratch/$mfile"
        run_check "$run/$id.log"
        git -C "$scratch" checkout -q "$tree" -- "$mfile"
        [ "$result" != pass ] || probe_reach "$id" "$mfile" "$line"
    else
        result=unreachable reason="swift test never compiles it; rerun with --sim UDID"
    fi
    if [ "$result" = busy ]; then
        busy=$reason
        break
    fi
    total=$((total + 1))
    case $result in
        fail)
            outcome=killed detail=$(head -1 <<<"$killers") more=$(($(wc -l <<<"$killers") - 1))
            [ $more = 0 ] || detail="$detail +$more"
            killed=$((killed + 1))
            printf '%s\tkilled\t%s\n' "$id" "$(tr '\n' ';' <<<"$killers" | sed 's/;$//; s/;/; /g')" >>"$run/results.tsv"
            ;;
        timeout) outcome=killed detail=$reason killed=$((killed + 1)) ;;
        pass) outcome=SURVIVED detail="" survived=$((survived + 1)) ;;
        # A broken build environment fails every build; only an error in the mutated file is the mutant's.
        nocompile) case $reason in
                "$mfile":*) outcome=nocompile detail=$reason nocompile=$((nocompile + 1)) ;;
                *) outcome=error detail=$(one_line "$reason") errors=$((errors + 1)) ;;
            esac ;;
        unreachable) outcome=unreachable detail=$reason unreachable=$((unreachable + 1)) ;;
        error) outcome=error detail=$(one_line "$reason") errors=$((errors + 1)) ;;
    esac
    [ "$outcome" = killed ] || printf '%s\t%s\t%s\n' "$id" "$outcome" "$reason" >>"$run/results.tsv"
    print_row "$outcome" "$mfile:$line" "$op" "$before${after:+ -> $after}" "$detail"
done 3<"$run/mutants.tsv"

counts=""
for pair in "$killed killed" "$survived SURVIVED" "$nocompile nocompile" "$unreachable unreachable" "$errors error"; do
    [ "${pair%% *}" = 0 ] || counts="$counts, $pair"
done
summary="$(plural $total mutant)${counts:+: ${counts#, }}"
[ -z "$busy" ] || summary="$summary; $(($(wc -l <"$run/mutants.tsv") - total)) not run (simulator busy)"
[ "$dropped" = 0 ] || summary="$summary; $dropped not run (--max $max)"
echo "$summary"
if [ -n "$busy" ]; then
    echo "$busy" >&2
    exit 75
fi
failed=$((survived + unreachable + errors + dropped))
[ -n "$base" ] || failed=$((failed + nocompile))
[ $total = 0 ] || [ $killed -gt 0 ] || failed=$((failed + 1))
[ $failed = 0 ]
