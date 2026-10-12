#!/bin/bash
set -euo pipefail

usage() {
    cat <<'EOF'
scripts/ci-visual-diffs.sh <run-id|PR> [--apply <name>...]

Downloads a CI run's visual-baseline-diffs artifact into .build/ci-visual-diffs/<run-id>/ and
prints one tab-separated line per failing snapshot:

  <snapshot>  <runner image>  <difference image>

<snapshot> is the baseline's path under Tests/Visual/__Snapshots__. The runner image is the render
the CI runner produced. The difference image is empty when the runner found no baseline at all.

--apply copies the runner image over each named baseline, or creates it, and prints each path it
wrote. A name is a <snapshot>, its file name, its Suite/test part, or a bare test name, and selects
every failing snapshot it matches. Nothing is written when any name matches nothing. The runner is the canonical
recorder (ADR-0007), so commit the result and let the next visual-tests run prove it.

Eight or more digits is a run id. Fewer is a PR number, which resolves to the newest finished
pull_request CI run on the PR's branch, so a dispatch or a run still going never hides it. Every
call downloads afresh, so a re-run of the same run id is never served stale.

Exits 0 when it listed or applied; 1 when gh or xcresulttool failed or the bundle broke the
expected shape; 2 on a usage error, including a name that matches nothing; and 3 when the run has
no visual-baseline-diffs artifact because visual-tests was green, skipped, or has not finished.
EOF
}

die() {
    echo "$2" >&2
    exit "$1"
}

target=""
apply=0
names=()
while [ $# -gt 0 ]; do
    case "$1" in
        -h | --help)
            usage
            exit 0
            ;;
        --apply) apply=1 ;;
        -*)
            usage >&2
            exit 2
            ;;
        *)
            if [ -z "$target" ]; then target=$1; else names+=("${1%"()"}"); fi
            ;;
    esac
    shift
done
case "$target" in "" | *[!0-9]*)
    usage >&2
    exit 2
    ;;
esac
if [ "$apply" -eq 1 ] && [ "${#names[@]}" -eq 0 ]; then
    die 2 "--apply needs at least one snapshot or test name"
fi
if [ "$apply" -eq 0 ] && [ "${#names[@]}" -gt 0 ]; then
    usage >&2
    exit 2
fi

repo=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
baselines=Tests/Visual/__Snapshots__

if [ "${#target}" -ge 8 ]; then
    run=$target
else
    branch=$(gh pr view "$target" --json headRefName,isCrossRepository \
        --jq 'select(.isCrossRepository | not) | .headRefName')
    [ -n "$branch" ] || die 1 "#$target comes from a fork, and ci-visual-diffs.sh does not handle fork PRs"
    picked=$(gh run list --workflow ci.yml --branch "$branch" --event pull_request --limit 20 \
        --json databaseId,status,conclusion,headSha \
        --jq 'map(select(.status == "completed" and .conclusion != "skipped" and .conclusion != "cancelled"))
            | max_by(.databaseId) | select(. != null) | "\(.databaseId) \(.headSha[0:8])"')
    [ -n "$picked" ] || die 3 "#$target's branch $branch has no finished CI run"
    run=${picked% *}
    echo "#$target: newest finished CI run is $run, on ${picked#* }" >&2
fi

dir=$repo/.build/ci-visual-diffs/$run
work=$dir.partial
rm -rf "$work"
mkdir -p "$work/artifact" "$work/attachments" "$work/snapshots" "$work/diffs"

if ! gh run download "$run" -n visual-baseline-diffs -D "$work/artifact" 2>"$work/gh.err"; then
    # gh says the first when the run uploaded other artifacts, the second when it uploaded none.
    if grep -qE "no artifact matches|no valid artifacts found" "$work/gh.err"; then
        die 3 "run $run has no visual-baseline-diffs artifact: its visual-tests job was green, skipped, or has not finished"
    fi
    cat "$work/gh.err" >&2
    exit 1
fi

# The artifact holds the bundle's contents at its root when the upload names the bundle alone, and
# the bundle folder itself when the upload named more than one path, as runs before this script did.
bundle=$work/artifact
[ -f "$bundle/Info.plist" ] || bundle=$work/artifact/VisualTests.xcresult
[ -f "$bundle/Info.plist" ] || die 1 "run $run's visual-baseline-diffs artifact holds no result bundle"

xcrun xcresulttool export attachments --path "$bundle" --output-path "$work/attachments" >/dev/null
failing_tests=$(xcrun xcresulttool get test-results summary --path "$bundle" --compact |
    jq -r '[.testFailures[].testIdentifierString] | unique[]')

# Swift Snapshot Testing records a failing snapshot's attachments and then the issue that names its
# baseline, so within one test run each issue owns the attachments recorded since the one before it.
# Attachment names end in _<n>_<uuid>; the bare name keys them, and the uuid names the exported file.
rows_for_test='
  def bare: sub("_[0-9]+_[0-9A-F-]{36}(?<ext>\\.[A-Za-z]+)$"; "\(.ext)");
  .testIdentifier as $test
  | ($test | split("/")[0]) as $suite
  | .testRuns[]
  | reduce .activities[] as $a ({bucket: {}, rows: []};
      if ($a.isAssociatedWithFailure // false) then
        ($a.title // "") as $text
        | ($text | capture("__Snapshots__/(?<path>[A-Za-z0-9_-]+/[A-Za-z0-9_.-]+\\.png)\"") // null) as $m
        | if $m != null then
            .rows += [[$m.path, $test, .bucket["failure.png"] // "-", .bucket["difference.png"] // "-", "-"]]
          elif ($text | test("No reference was found")) then
            (.bucket | to_entries | map(select(.key | endswith(".png")))) as $only
            | .rows += [if ($only | length) == 1
                then ["\($suite)/\($only[0].key)", $test, $only[0].value, "-", "-"]
                else ["-", $test, "-", "-", "a missing reference recorded \($only | length) images"] end]
          else
            .rows += [["-", $test, "-", "-", ($text | split("\n")[0])]]
          end
        | .bucket = {}
      else
        reduce ($a.attachments // [])[] as $x (.; .bucket[$x.name | bare] = $x.uuid)
      end)
  | .rows[]
  | @tsv'

: >"$work/index.tsv"
: >"$work/other-failures.txt"
while IFS= read -r test; do
    [ -n "$test" ] || continue
    xcrun xcresulttool get test-results activities --path "$bundle" --test-id "$test" --compact |
        jq -r "$rows_for_test"
done <<<"$failing_tests" >"$work/rows.tsv"

while IFS=$'\t' read -r snapshot test render difference note; do
    if [ "$snapshot" = - ]; then
        printf '%s\t%s\n' "$test" "$note" >>"$work/other-failures.txt"
        continue
    fi
    [ "$render" != - ] || die 1 "$test failed on $snapshot but the bundle holds no runner image for it"
    # The library names a snapshot folder after the test's source file, and a missing reference's
    # folder can only come from the suite name, so the two must agree.
    if [ "$difference" = - ] && [ ! -f "$repo/Tests/Visual/${snapshot%%/*}.swift" ]; then
        die 1 "$snapshot has no baseline, and its folder must match a file Tests/Visual/${snapshot%%/*}.swift"
    fi
    mkdir -p "$work/snapshots/${snapshot%/*}"
    cp "$work/attachments/$render".png "$work/snapshots/$snapshot"
    if [ "$difference" != - ]; then
        mkdir -p "$work/diffs/${snapshot%/*}"
        cp "$work/attachments/$difference".png "$work/diffs/$snapshot"
    fi
    printf '%s\n' "$snapshot" >>"$work/index.tsv"
done <"$work/rows.tsv"

rm -rf "$work/artifact" "$work/attachments" "$work/rows.tsv" "$work/gh.err" "$dir"
mv "$work" "$dir"
count=$(wc -l <"$dir/index.tsv" | tr -d ' ')

if [ "$apply" -eq 0 ]; then
    echo "run $run: $count failing snapshot(s) in $dir" >&2
    if [ -s "$dir/other-failures.txt" ]; then
        echo "$(wc -l <"$dir/other-failures.txt" | tr -d ' ') failure(s) that are not snapshot mismatches: $dir/other-failures.txt" >&2
    fi
    while IFS= read -r snapshot; do
        difference=""
        [ -f "$dir/diffs/$snapshot" ] && difference=$dir/diffs/$snapshot
        printf '%s\t%s\t%s\n' "$snapshot" "$dir/snapshots/$snapshot" "$difference"
    done <"$dir/index.tsv"
    exit 0
fi

[ "$count" -gt 0 ] || die 2 "run $run has no failing snapshot to apply"

# A snapshot answers to itself, its file name, Suite/test (the .<n>.png tail cut), and the test name.
selected=$(printf '%s\n' "${names[@]}" | awk -F'\t' '
    NR == FNR { s = $1; f = s; sub(/^[^\/]+\//, "", f); t = s; sub(/\.[^.\/]+\.png$/, "", t)
                b = t; sub(/^[^\/]+\//, "", b)
                rows[++n] = s; key[s, s] = key[f, s] = key[t, s] = key[b, s] = 1; next }
    { hit = 0
      for (i = 1; i <= n; i++) if (($0, rows[i]) in key) { hit = 1; want[rows[i]] = 1 }
      if (!hit) { print "no failing snapshot matches " $0 > "/dev/stderr"; bad = 1 } }
    END { if (bad) exit 2; for (i = 1; i <= n; i++) if (rows[i] in want) print rows[i] }
' "$dir/index.tsv" -) || die 2 "failing snapshots in run $run: $(tr '\n' ' ' <"$dir/index.tsv")"

while IFS= read -r snapshot; do
    mkdir -p "$repo/$baselines/${snapshot%/*}"
    cp "$dir/snapshots/$snapshot" "$repo/$baselines/$snapshot"
    echo "$baselines/$snapshot"
done <<<"$selected"
