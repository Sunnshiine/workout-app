#!/bin/bash
set -euo pipefail

usage() {
    cat <<'EOF'
scripts/changed-tests.sh [--base REV]

Prints every test whose lines this checkout changed since it left REV, committed or not,
untracked files included, in the .swift files under Tests/Unit, Tests/Component, and
Tests/Support. A test's lines run from its @Test to the line before the next @Test in its file,
so an edit to a helper between two tests selects the test above it. A new file selects every test
it declares. REV defaults to origin/main. CI passes the pull request's base, HEAD^1, and
scripts/flake-guard.sh repeats what this prints.

One row per test, sorted: the file and line of its func, a tab, and the function's base name.
Nothing printed means no test changed. A changed file that declares no test, such as a
Tests/Support fixture, and a change above a file's first test print a note to stderr and select
nothing, because the tests that share that code are not the ones the diff touched.

Exits 0, or 2 on a usage error or a REV git cannot resolve.
EOF
}

base=origin/main
while [ $# -gt 0 ]; do
    case $1 in
        --base) [ $# -ge 2 ] || { usage >&2; exit 2; }; base=$2; shift ;;
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

scope=('Tests/Unit/*.swift' 'Tests/Component/*.swift' 'Tests/Support/*.swift')
lines=$(mktemp)
trap 'rm -f "$lines"' EXIT
# One row per changed line of the post-change file. A pure deletion counts as the line above it,
# and an untracked file counts every line.
{
    git diff -U0 --no-renames --diff-filter=AM "$fork_point" -- "${scope[@]}" | awk '
        /^\+\+\+ b\// { file = substr($0, 7); next }
        /^@@ / {
            n = split(substr($3, 2), plus, ",")
            first = plus[1] + 0
            count = n > 1 ? plus[2] + 0 : 1
            if (count == 0) print file "\t" (first > 0 ? first : 1)
            for (i = 0; i < count; i++) print file "\t" first + i
        }'
    git ls-files --others --exclude-standard -- "${scope[@]}" | awk '{ print $0 "\tall" }'
} >"$lines"

cut -f1 "$lines" | LC_ALL=C sort -u | while IFS= read -r file; do
    # A test spans its @Test line to the line before the next one, so a change to a helper between
    # two tests counts toward the test above it. An @Test( whose arguments span lines names its
    # test on the next func line. BSD awk has no \b, so the boundary after @Test is spelled out.
    awk -F'\t' -v file="$file" '
        function flush() { if (touched && name != "") { print file ":" line "\t" name; selected++ } }
        FILENAME == ARGV[1] { if ($1 == file) { if ($2 == "all") all = 1; else changed[$2] = 1 } next }
        /^[[:space:]]*@Test([^[:alnum:]_]|$)/ { flush(); tests++; armed = 1; touched = 0; name = "" }
        all || FNR in changed { if (tests) touched = 1; else above = 1 }
        armed && match($0, /func [[:alpha:]_][[:alnum:]_]*/) {
            name = substr($0, RSTART + 5, RLENGTH - 5)
            line = FNR
            armed = 0
        }
        END {
            flush()
            hunt = "the tests that use it are not repeated. Hunt them with scripts/flake-hunt.sh before you commit."
            if (!tests) print "note: " file " changed and declares no test; " hunt > "/dev/stderr"
            else if (above && selected < tests) print "note: " file " changed above its first test; " hunt > "/dev/stderr"
        }' "$lines" "$file"
done | LC_ALL=C sort -u
