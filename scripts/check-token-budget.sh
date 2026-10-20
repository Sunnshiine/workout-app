#!/usr/bin/env bash
# Block a commit that stages a text file over 5,000 tokens, counted as bytes / 4.
#
# .githooks/pre-commit runs this. It reads sizes from the index, never the working tree, so it
# checks what the commit will hold, including the temporary index `git commit -a` and
# `git commit <path>` build. Git's binary detection and the token-budget=exempt attribute in
# .gitattributes decide which files are skipped.
set -euo pipefail

if [ "${1:-}" = "--help" ]; then
    cat <<'EOF'
usage: scripts/check-token-budget.sh

Exits 1 and names each staged text file over 5000 tokens (more than 20000 bytes), with how to
split it. Exits 0 when every staged file fits. Binary files and paths marked
token-budget=exempt in .gitattributes are skipped.
EOF
    exit 0
fi

limit_tokens=5000
limit_bytes=$((limit_tokens * 4))
target_tokens=4000

cd "$(git rev-parse --show-toplevel)"

candidates=()
while IFS= read -r -d '' record; do
    added=${record%%$'\t'*}
    path=${record#*$'\t'*$'\t'}
    [ "$added" = "-" ] || candidates+=("$path")
done < <(git diff --cached --no-renames --numstat -z --diff-filter=ACMRT)

[ "${#candidates[@]}" -gt 0 ] || exit 0

offenders=()
while IFS= read -r -d '' path && IFS= read -r -d '' _ && IFS= read -r -d '' value; do
    [ "$value" = "exempt" ] && continue
    size=$(git cat-file -s ":$path")
    if [ "$size" -gt "$limit_bytes" ]; then
        tokens=$(((size + 3) / 4))
        pieces=$(((tokens + limit_tokens - 1) / limit_tokens))
        offenders+=("  $path: $tokens tokens ($size bytes). Split it into at least $pieces files.")
    fi
done < <(printf '%s\0' "${candidates[@]}" | git check-attr --cached -z --stdin token-budget)

[ "${#offenders[@]}" -gt 0 ] || exit 0

{
    echo "error: these staged files are over the $limit_tokens-token limit (tokens = bytes / 4):"
    echo
    printf '%s\n' "${offenders[@]}"
    cat <<EOF

Aim for about $target_tokens tokens ($((target_tokens * 4)) bytes) per file so the next edit still fits.

How to split:
- Split along responsibilities, not at a line count. Each new file holds one cohesive concern
  and has a name that says what it is.
- Swift: App/, Sources/WorkoutTracker/, WorkoutShared/, WorkoutWidgets/, and the folders under
  Tests/ are Xcode buildable folders, so a new .swift file in the same folder compiles with no
  project edit. Move a cohesive extension or nested type into its own file named for the type
  and the concern. private and fileprivate members are not visible from another file; widen to
  internal only what the split needs.
- Swift tests: move a group of tests by behaviour into a new file in the same folder, as
  \`extension <ExistingSuite> { ... }\` or as whole top-level @Test functions. Name the file
  after the original file's stem, as <OriginalFile><Behaviour>.swift (SyncCoordinatorTests.swift
  gives SyncCoordinatorTestsOutcomeLatch.swift): swift test --filter matches a free test's file
  name, so --filter SyncCoordinatorTests keeps selecting every test it did. Never move an
  assertSnapshot call to another file; its baseline folder is named after the file. Move a
  fake or helper to Tests/Support/ only when two files need it.
- Shell: move a group of functions into a helper file next to the script and source it. Split
  a test file by the area it covers.
- Python: split modules and tests by area into sibling modules. Keep the original file as the
  entry point that imports them, so the command CI runs still runs every test.
- Markdown: move whole sections into sibling docs and link each from the original. Then run
  scripts/lint.sh to catch broken references.
- Machine-written data (lockfiles, codegen, captured output): do not split it. Add its pattern
  to .gitattributes with token-budget=exempt, in its own reviewed change.

Do not minify, strip comments or docs, shorten names, mark a hand-written file exempt, or
commit with --no-verify without the human's approval.

Then git add the new files and the shrunk original, commit again, and run scripts/lint.sh and
swift test.
EOF
} >&2
exit 1
