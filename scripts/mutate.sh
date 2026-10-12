#!/bin/bash
set -euo pipefail

usage() {
    cat <<'EOF'
Usage: scripts/mutate.sh [--sim UDID] [--filter SEL]... FILE SED_EXPR [SED_EXPR...]
       scripts/mutate.sh [--sim UDID] [--filter SEL]... [--max N] --diff BASE [PATH...]
       scripts/mutate.sh --clean-scratch

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
                 A line inside an #if os(iOS), os(macOS), canImport(UIKit), or canImport(AppKit)
                 branch the build compiles out is unreachable without a build.
  --max N        runs at most N generated mutants (default 40), taking each file's first mutant
                 before any file's second; unreachable ones never count.
  --filter SEL   the tests that judge each mutant; repeatable. Without --sim: swift test --filter
                 SEL (default the whole suite). With --sim: unit, visual, ui, or a test-sim.sh
                 TEST-ID; a bare suite name means WorkoutTrackerTests/SUITE (default unit).
  --sim UDID     runs every check through the scratch tree's scripts/test-sim.sh --sim UDID.
                 swift test compiles only Sources/, so App/, WorkoutShared/, and WorkoutWidgets/
                 need --sim. Run Sources/ without --sim (seconds) and those with --sim PATH.
  --clean-scratch  removes every scratch tree no run holds, with the DerivedData its --sim builds
                 left. A tree holds about 0.3 GB of .build, and 0.8 to 1.1 GB more of DerivedData
                 once --sim has built in it; SCRATCH_SLOTS trees (default 4) reach about 6 GB.
MUTATE_TIMEOUT=N bounds each run in seconds (default 5 x the baseline's time, at least 120).

Prints log:, mutants: (--diff), scratch:, and baseline: lines, then a row per mutant as it ends:
  OUTCOME  FILE:LINE  OP  CHANGE  FIRST-KILLER +N | REASON
  killed       a test failed, crashed, or the run timed out; results.tsv lists every killer
  flaky        every killer also failed on one rerun of the untouched snapshot after the rows
  SURVIVED     no test failed, and an #error on the line breaks the build (grep '^SURVIVED')
  nocompile    the compiler rejects the mutated file
  unreachable  this build never compiles the line (#if, no target; App/ needs --sim)
  error        the runner failed without naming a failing test, or the build failed elsewhere
  not run      --max left it out
The #error probe misjudges a mutant in two places: on a continuation line inside an #if
branch the build compiles out it reads SURVIVED, and inside a multi-line string literal it reads
unreachable. --diff never mutates inside a string and decides the #if branches above itself.
Exits 0 when every mutant was killed (a generated nocompile does not count); 1 when any was flaky,
SURVIVED, unreachable, an error, or a hand-written nocompile, when --max left any unrun, or when
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
        --clean-scratch) scratch_clean; exit 0 ;;
        -h | --help) usage; exit 0 ;;
        -*) usage >&2; exit 2 ;;
        *) break ;;
    esac
done
case $max in '' | *[!0-9]* | 0) die "--max takes a whole number above 0, not '$max'" ;; esac
[ -n "$base" ] || [ $# -ge 2 ] || { usage >&2; exit 2; }

caller=$(git rev-parse --show-toplevel)
caller_physical=$(cd "$caller" && pwd -P)
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

reachable() {
    [ -z "$sim" ] || return 0
    case $1 in
        Tests/Unit/GoogleAuthTests.swift) return 1 ;;
        Sources/* | Tests/Unit/* | Tests/Component/* | Tests/Support/*) return 0 ;;
        *) return 1 ;;
    esac
}
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
    : >"$run/compiled-out.tsv"
    : >"$run/unreachable.tsv"
    : >"$run/sources.tsv"
    with_reason() { awk -v why="$1" '{ print why "\t" $0 }'; }
    if [ -n "$sim" ]; then
        platform=iOS compiled_out="an #if compiles it out of the simulator build; rerun without --sim"
    else
        platform=macOS compiled_out="an #if compiles it out of swift test; rerun with --sim UDID"
    fi
    k=0 changed=0
    while IFS= read -r f; do
        case $f in Sources/*.swift | App/*.swift | WorkoutShared/*.swift | WorkoutWidgets/*.swift) ;; *) continue ;; esac
        k=$((k + 1))
        git show "$tree:$f" >"$run/source$k.swift"
        printf '%s\t%s\n' "$f" "$run/source$k.swift" >>"$run/sources.tsv"
        git diff -U0 --no-color "$merge_base" "$tree" -- "$f" |
            awk '/^@@/ { n = split(substr($3, 2), r, ","); count = n > 1 ? r[2] : 1; for (i = 0; i < count; i++) print r[1] + i }' >"$run/changed$k"
        changed=$((changed + $(wc -l <"$run/changed$k")))
        if reachable "$f"; then
            awk -v changed="$run/changed$k" -v path="$f" -v platform=$platform -v compiledOut="$run/compiled-out.tsv" \
                -f "$script_dir/mutants.awk" "$run/source$k.swift" | with_reason "" >>"$run/runnable.tsv"
        else
            awk -v changed="$run/changed$k" -v path="$f" -f "$script_dir/mutants.awk" "$run/source$k.swift" |
                with_reason "swift test never compiles it; rerun with --sim UDID" >>"$run/unreachable.tsv"
        fi
    done <"$run/files"
    generated=$(($(cat "$run/runnable.tsv" "$run/compiled-out.tsv" "$run/unreachable.tsv" | wc -l)))
    echo "mutants: $generated on $(plural "$changed" "changed line") in $(plural $k file) since ${merge_base:0:8}"
    [ "$generated" -gt 0 ] || exit 0
    awk -F'\t' -v max="$max" -v run="$run" '
        { row[NR] = $0; rank[NR] = ++seen[$2] }
        END {
            for (r = 1; taken < max; r++) {
                found = 0
                for (i = 1; i <= NR && taken < max; i++) if (rank[i] == r) { picked[i] = 1; taken++; found = 1 }
                if (!found) break
            }
            for (i = 1; i <= NR; i++) print row[i] > (run "/" (i in picked ? "picked" : "unrun") ".tsv")
        }' "$run/runnable.tsv"
    touch "$run/picked.tsv" "$run/unrun.tsv"
    runnable=$(($(wc -l <"$run/picked.tsv")))
    dropped=$(($(wc -l <"$run/unrun.tsv")))
    # mutants.awk prints the whole mutated line last, so it is read from the file, never through -v,
    # which would rewrite its backslashes.
    { cat "$run/picked.tsv"; with_reason "$compiled_out" <"$run/compiled-out.tsv"; cat "$run/unreachable.tsv"; } | awk -F'\t' -v run="$run" '
        FNR == NR { source[$1] = $2; next }
        {
            id = "m" FNR
            mutated = $0
            for (i = 1; i <= 6; i++) sub(/^[^\t]*\t/, "", mutated)
            print id "\t" $2 "\t" $3 "\t" $4 "\t" $5 "\t" $6 > (run "/mutants.tsv")
            if ($1 != "") print $1 > (run "/" id ".why")
            out = run "/" id ".swift"
            n = 0
            while ((getline text < source[$2]) > 0) print (++n == $3 ? mutated : text) > out
            close(source[$2])
            close(out)
        }' "$run/sources.tsv" -
    awk -F'\t' '{ print "-\t" $2 "\t" $3 "\t" $4 "\t" $5 "\t" $6 }' "$run/unrun.tsv" >"$run/not-run.tsv"
fi

one_line() {
    local s
    s=$(head -1 <<<"$1" | sed -E "s#(^|[ '\"(])/[^ '\"]*/#\1#g")
    [ ${#s} -le 120 ] || s="${s:0:117}..."
    printf '%s\n' "$s"
}
read_log() { awk -v mode="$1" -v root="$scratch/" -f "$script_dir/test-log.awk" "$2"; }

# close_fds=False keeps the slot lock on fd 8 in every child. SwiftPM runs the tests in a process
# group of their own, so only a kill by session reaches them. The session's leader kills its session
# when the wrapper dies, as it does when a harness SIGKILLs mutate.sh's process group.
with_timeout_py='import os, signal, subprocess, sys, time

def kill_session(sid):
    for _ in range(50):
        members = []
        for line in subprocess.run(["ps", "-axo", "pid=,stat="], capture_output=True, text=True).stdout.splitlines():
            pid, stat = line.split()
            try:
                if int(pid) != os.getpid() and not stat.startswith("Z") and os.getsid(int(pid)) == sid:
                    members.append(int(pid))
            except OSError:
                pass
        if not members:
            return
        for pid in members:
            try:
                os.kill(pid, signal.SIGKILL)
            except OSError:
                pass
        time.sleep(0.05)

def exit_like(rc):
    sys.exit(128 - rc if rc < 0 else rc)

if sys.argv[1] == "--session-of":
    child = subprocess.Popen(sys.argv[3:], close_fds=False)
    while True:
        try:
            exit_like(child.wait(timeout=0.2))
        except subprocess.TimeoutExpired:
            if os.getppid() != int(sys.argv[2]):
                kill_session(os.getpid())
                sys.exit(137)

leader = subprocess.Popen([sys.executable, "-c", os.environ["WITH_TIMEOUT_PY"], "--session-of", str(os.getpid())] + sys.argv[2:],
                          start_new_session=True, close_fds=False)
def stop(*_):
    kill_session(leader.pid)
    sys.exit(124)
for s in (signal.SIGINT, signal.SIGTERM, signal.SIGHUP):
    signal.signal(s, stop)
try:
    rc = leader.wait(timeout=max(1, int(sys.argv[1])))
except subprocess.TimeoutExpired:
    stop()
exit_like(rc)'
with_timeout() { WITH_TIMEOUT_PY=$with_timeout_py python3 -c "$with_timeout_py" "$@"; }

run_check() {
    local log=$1 build_only=${2:-} rc=0 test_log start=$SECONDS
    result="" tests=0 killers="" reason=""
    if [ -n "$sim" ]; then
        with_timeout "$limit" "$scratch/scripts/test-sim.sh" --sim "$sim" "${selections[@]}" </dev/null >"$log.stdout" 2>"$log.stderr" || rc=$?
        cat "$log.stdout" "$log.stderr" >"$log"
        if [ $rc = 124 ]; then
            result=timeout reason="timed out after ${limit}s"
            return
        fi
        if [ $rc = 75 ]; then
            result=busy
            reason=$(cat "$log.stderr")
            return
        fi
        if [ $rc = 65 ] && grep -q '^build log: ' "$log.stderr"; then
            result=nocompile
            reason=$(read_log first-error "$log.stderr")
            return
        fi
        test_log=$(sed -n 's/^log: //p' "$log.stdout" | tail -1)
        [ -z "$test_log" ] || [ ! -f "$test_log" ] || cp "$test_log" "$log"
    else
        (cd "$scratch" && with_timeout "$limit" swift build --build-tests) </dev/null >"$log" 2>&1 || rc=$?
        if [ $rc = 0 ] && [ -n "$build_only" ]; then
            result=pass
            return
        elif [ $rc = 0 ]; then
            (cd "$scratch" && with_timeout $((limit - (SECONDS - start))) swift test --skip-build ${swift_filters[@]+"${swift_filters[@]}"}) \
                </dev/null >>"$log" 2>"$log.stderr" || rc=$?
            cat "$log.stderr" >>"$log"
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
        reason="exit $rc: $(head -1 "$log.stderr")"
    fi
}

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

touch "$run/not-run.tsv"
loc_width=$(awk -F'\t' '{ w = length($2 ":" $3); if (w > max) max = w } END { print max }' "$run/mutants.tsv" "$run/not-run.tsv")
change_width=$(awk -F'\t' '{ w = length($5 ($6 == "" ? "" : " -> " $6)); if (w > max) max = w } END { print max }' "$run/mutants.tsv" "$run/not-run.tsv")
print_row() {
    local row
    row=$(printf "%-11s  %-${loc_width}s  %-7s  %-${change_width}s  %s" "$@")
    printf '%s\n' "${row%"${row##*[! ]}"}"
}

killed=0 flaky=0 survived=0 nocompile=0 unreachable=0 errors=0 total=0 busy=""
: >"$run/named-kills.tsv"
while IFS=$'\t' read -r id mfile line op before after <&3; do
    if [ -f "$run/$id.why" ]; then
        result=unreachable reason=$(cat "$run/$id.why")
    else
        cp "$run/$id.swift" "$scratch/$mfile"
        run_check "$run/$id.log"
        git -C "$scratch" checkout -q "$tree" -- "$mfile"
        [ "$result" != pass ] || probe_reach "$id" "$mfile" "$line"
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
            grep -q 'crashed)$' <<<"$killers" || awk -v id="$id" '{ print id "\t" $0 }' <<<"$killers" >>"$run/named-kills.tsv"
            ;;
        timeout) outcome=killed detail=$reason killed=$((killed + 1)) ;;
        pass) outcome=SURVIVED detail="" survived=$((survived + 1)) ;;
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
while IFS=$'\t' read -r _ mfile line op before after; do
    print_row "not run" "$mfile:$line" "$op" "$before${after:+ -> $after}"
done <"$run/not-run.tsv"

if [ -z "$busy" ] && [ -s "$run/named-kills.tsv" ]; then
    run_check "$run/recheck.log"
    if [ "$result" = fail ]; then
        echo "recheck: the untouched snapshot fails $(paste -sd , - <<<"$killers" | sed 's/,/, /g')"
        awk -F'\t' 'FNR == NR { failing[$0] = 1; next }
            { seen[$1] = 1; if (!($2 in failing)) steady[$1] = 1 }
            END { for (id in seen) if (!(id in steady)) print id }' - "$run/named-kills.tsv" <<<"$killers" >"$run/flaky-ids"
        while IFS=$'\t' read -r id mfile line op before after; do
            grep -qx "$id" "$run/flaky-ids" || continue
            flaky=$((flaky + 1)) killed=$((killed - 1))
            print_row flaky "$mfile:$line" "$op" "$before${after:+ -> $after}" \
                "$(awk -F'\t' -v id="$id" '$1 == id { printf "%s%s", sep, $2; sep = ", " }' "$run/named-kills.tsv")"
        done <"$run/mutants.tsv"
        awk -F'\t' -v OFS='\t' 'FNR == NR { flaky[$0] = 1; next } $1 in flaky { $2 = "flaky" } { print }' \
            "$run/flaky-ids" "$run/results.tsv" >"$run/results.new" && mv "$run/results.new" "$run/results.tsv"
    fi
fi

counts=""
for pair in "$killed killed" "$flaky flaky" "$survived SURVIVED" "$nocompile nocompile" "$unreachable unreachable" "$errors error"; do
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
failed=$((flaky + survived + unreachable + errors + dropped))
[ -n "$base" ] || failed=$((failed + nocompile))
[ $total = 0 ] || [ $killed -gt 0 ] || failed=$((failed + 1))
[ $failed = 0 ]
