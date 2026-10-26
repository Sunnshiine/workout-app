#!/bin/bash
set -euo pipefail

usage() {
    cat <<'EOF'
scripts/changed-tests.sh [--base REV] [--ui]

Prints every test whose lines this checkout changed since it left REV, committed or not,
untracked files included, in the .swift files under Tests/Unit, Tests/Component, and
Tests/Support. A test's lines run from its @Test to the brace that closes its func. Deleting a
whole test selects nothing. A new file selects every test it declares. REV defaults to
origin/main. CI passes the pull request's base, HEAD^1, and scripts/flake-guard.sh repeats what
this prints.

One row per test, sorted: the file and line of its func, a tab, and the function's base name.
Nothing printed means no test changed. A changed file that declares no test, such as a
Tests/Support fixture, and a change outside every test of a file, such as a helper or an
attribute above an @Test, print a note to stderr and select nothing, because the tests that share
that code are not the ones the diff touched.

--ui prints instead the XCTest methods, func test...(), in the .swift files under Tests/UI. A
test's lines run from its func line to the brace that closes it, so an attribute such as
@MainActor above it sits outside, and its row names it Class/testName after its enclosing class or
extension, the tail of a -only-testing:WorkoutTrackerUITests/Class/testName identifier. A change
outside every test, such as WorkoutUITestSupport.swift, prints the note with scripts/test-sim.sh
as its advice, since flake-hunt.sh runs swift test alone, and selects nothing.

Exits 0, or 2 on a usage error or a REV git cannot resolve.
EOF
}

base=origin/main
ui=
while [ $# -gt 0 ]; do
    case $1 in
        --base) [ $# -ge 2 ] || { usage >&2; exit 2; }; base=$2; shift ;;
        --ui) ui=1 ;;
        -h | --help) usage; exit 0 ;;
        *) usage >&2; exit 2 ;;
    esac
    shift
done

cd "$(git rev-parse --show-toplevel)"
fork_point=$(git merge-base "$base" HEAD 2>/dev/null) || {
    echo "error: git cannot find where HEAD left '$base'." >&2
    exit 2
}

# BSD awk reads escapes in a -v value, so start spells a literal paren as [(].
if [ -n "$ui" ]; then
    scope=('Tests/UI/*.swift')
    start='^[[:space:]]*func test[[:alnum:]_]*[(]'
    hunt='Repeat them with scripts/test-sim.sh before you commit.'
else
    scope=('Tests/Unit/*.swift' 'Tests/Component/*.swift' 'Tests/Support/*.swift')
    start='^[[:space:]]*@Test([^[:alnum:]_]|$)'
    hunt='Hunt them with scripts/flake-hunt.sh before you commit.'
fi
lines=$(mktemp)
trap 'rm -f "$lines"' EXIT
# One row per changed line of the post-change file, or per pure deletion with "deleted" in a third
# column. An untracked file counts every line.
{
    git diff -U0 --no-renames --diff-filter=AM "$fork_point" -- "${scope[@]}" | awk '
        /^\+\+\+ b\// { file = substr($0, 7); next }
        /^@@ / {
            n = split(substr($3, 2), plus, ",")
            first = plus[1] + 0
            count = n > 1 ? plus[2] + 0 : 1
            if (count == 0) print file "\t" first "\tdeleted"
            for (i = 0; i < count; i++) print file "\t" first + i
        }'
    git ls-files --others --exclude-standard -- "${scope[@]}" | awk '{ print $0 "\tall" }'
} >"$lines"

cut -f1 "$lines" | LC_ALL=C sort -u | while IFS= read -r file; do
    # A test spans its start line, its @Test or under --ui its func, to the brace that closes its
    # func at the start line's indent, or to the func line when the body opens and closes there,
    # counting no brace in a string or comment. A deletion counts only when the lines on both sides
    # of it belong to the same test, so deleting a whole test selects nothing. An @Test( whose
    # arguments span lines names its test on the next func line. BSD awk has no \b, so the boundary
    # after @Test is spelled out. Under --ui a row names the class or extension the test sits in.
    awk -F'\t' -v file="$file" -v start="$start" -v ui="$ui" -v hunt="$hunt" '
        FILENAME == ARGV[1] {
            if ($1 != file) next
            if ($2 == "all") all = 1
            else if ($3 == "deleted") deleted[$2] = 1
            else changed[$2] = 1
            next
        }
        !inside && match($0, /^[[:space:]]*([[:alnum:]@_]+ +)*(class|extension) [[:alpha:]_][[:alnum:]_]*/) {
            n = split(substr($0, RSTART, RLENGTH), words, /[[:space:]]+/)
            if (words[n] != "func" && words[n] != "var") type = words[n]
        }
        !inside && $0 ~ start {
            tests++
            class[tests] = type
            inside = 1
            armed = 1
            match($0, /^[[:space:]]*/)
            indent = substr($0, 1, RLENGTH)
        }
        { if (inside) of[FNR] = tests; last = FNR }
        inside && armed && match($0, /func [[:alpha:]_][[:alnum:]_]*/) {
            name[tests] = substr($0, RSTART + 5, RLENGTH - 5)
            line[tests] = FNR
            armed = 0
            code = $0
            gsub(/"([^"\\]|\\.)*"/, "", code)
            sub(/\/\/.*/, "", code)
            opens = gsub(/\{/, "{", code)
            if (opens && opens == gsub(/\}/, "}", code)) inside = 0
            next
        }
        inside && !armed && index($0, indent "}") == 1 { inside = 0 }
        END {
            for (l = 1; l <= last; l++) {
                if (!all && !(l in changed)) continue
                if (of[l]) touched[of[l]] = 1
                else outside = 1
            }
            for (l in deleted) if (of[l] && of[l] == of[l + 1]) touched[of[l]] = 1
            for (t = 1; t <= tests; t++) if (t in touched && name[t] != "") {
                print file ":" line[t] "\t" (ui ? class[t] "/" : "") name[t]
                selected++
            }
            hunt = "the tests that use it are not repeated. " hunt
            if (!tests) print "note: " file " changed and declares no test; " hunt > "/dev/stderr"
            else if (outside && selected < tests) print "note: " file " changed outside its tests; " hunt > "/dev/stderr"
        }' "$lines" "$file"
done | LC_ALL=C sort -u
