#!/usr/bin/env bash
set -uo pipefail

script_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
checker="$script_dir/../lint-vocabulary.py"

root=$(mktemp -d) || exit 3
trap 'rm -rf "$root"' EXIT
repo="$root/repo"
pass=0
fail=0

ok()  { pass=$((pass + 1)); printf '  ok   %s\n' "$1"; }
bad() { fail=$((fail + 1)); printf '  FAIL %s\n' "$1"; }

expect_exit() {
    if [ "$2" -eq "$3" ]; then ok "$1 exits $3"; else bad "$1 exits $3, got $2"; fi
}

expect_line() {
    if printf '%s\n' "$2" | grep -Fxq -- "$3"; then ok "$1: $3"; else bad "$1 is missing the line: $3"; fi
}

expect_no_text() {
    if printf '%s\n' "$2" | grep -Fq -- "$3"; then bad "$1 has the text: $3"; else ok "$1 lacks $3"; fi
}

# A repo whose glossary avoids "displayed session", "tempo", and "conflict", committed as
# origin/main with one existing name, displayedSessionCount, that the branch did not add.
fresh_repo() {
    rm -rf "$repo"
    mkdir -p "$repo/Sources/Core" "$repo/App" "$repo/Tests" "$repo/scripts" "$repo/docs/context"
    cat >"$repo/CONTEXT.md" <<'EOF'
**Viewed Session**: The Session on screen. Avoid: displayed session.
**Sync Outcome**: What a flush did. Avoid: conflict.
EOF
    cat >"$repo/docs/context/logging.md" <<'EOF'
**Cadence**: The coach's tempo prefix. Avoid: tempo.
**Coach Note**: Coach prose in a Notes cell.
EOF
    cat >"$repo/scripts/vocabulary-avoid.txt" <<'EOF'
[avoid]
displayed session
tempo
conflict

[kept]
conflicts

[unrelated]
conflicting
EOF
    printf 'let displayedSessionCount = 1\nlet conflicts = 0\n' >"$repo/Sources/Core/Old.swift"
    git -C "$repo" init -q
    git -C "$repo" add -A
    git -C "$repo" -c user.name=t -c user.email=t@example.com commit -qm base
    git -C "$repo" update-ref refs/remotes/origin/main HEAD
}

check() {
    (cd "$repo" && python3 "$checker" "$@") >"$root/stdout" 2>"$root/stderr"
    status=$?
    out=$(cat "$root/stdout")
    err=$(cat "$root/stderr")
}

echo "an added avoided name fails with the term and the glossary entry"
fresh_repo
printf 'var displayedSession = 1\n' >"$repo/Sources/Core/New.swift"
check
expect_exit "added name" "$status" 1
expect_line "added name" "$out" \
    "Sources/Core/New.swift:1: displayedSession spells \"displayed session\", which CONTEXT.md avoids for Viewed Session. Name it with the glossary's word."

echo "an added name in App/ fails, and one in Tests/ is not read"
fresh_repo
printf 'let tempoLabel = 1\n' >"$repo/App/View.swift"
printf 'let tempoLabel = 1\n' >"$repo/Tests/T.swift"
check
expect_exit "App and Tests" "$status" 1
expect_line "App and Tests" "$out" \
    "App/View.swift:1: tempoLabel spells \"tempo\", which docs/context/logging.md avoids for Cadence. Name it with the glossary's word."
expect_no_text "App and Tests" "$out" "Tests/T.swift"

echo "an existing avoided name the branch leaves alone passes, even in a file the branch edits"
fresh_repo
printf 'let viewedSession = 2\n' >>"$repo/Sources/Core/Old.swift"
check
expect_exit "existing name" "$status" 0
expect_no_text "existing name" "$out" "displayedSessionCount"

echo "a committed addition fails the same as an uncommitted one"
fresh_repo
printf 'let displayedSessions = [1]\n' >"$repo/Sources/Core/New.swift"
git -C "$repo" add -A
git -C "$repo" -c user.name=t -c user.email=t@example.com commit -qm add
check
expect_exit "committed" "$status" 1
expect_line "committed" "$out" \
    "Sources/Core/New.swift:1: displayedSessions spells \"displayed session\", which CONTEXT.md avoids for Viewed Session. Name it with the glossary's word."

echo "a phrase inside a longer real word passes"
fresh_repo
printf 'let temporaryRow = 1\nlet contempt = 2\n' >"$repo/Sources/Core/New.swift"
check
expect_exit "longer word" "$status" 0

echo "comments and string literals are not identifiers"
fresh_repo
printf '// displayedSession was renamed\nlet label = "tempoLabel"\n' >"$repo/Sources/Core/New.swift"
check
expect_exit "comment and string" "$status" 0

echo "a kept name gets a note and passes, and a new name that spells its phrase fails"
fresh_repo
printf 'let total = conflicts + 1\n' >"$repo/Sources/Core/New.swift"
check
expect_exit "kept name" "$status" 0
expect_line "kept name" "$out" \
    "note: Sources/Core/New.swift:1: conflicts spells \"conflict\", which CONTEXT.md avoids for Sync Outcome. It is a kept name, so this line passes. A new name must use the glossary's word."
printf 'let conflictedWrites = conflicts\n' >"$repo/Sources/Core/New.swift"
check
expect_exit "new conflict name" "$status" 1
expect_line "new conflict name" "$out" \
    "Sources/Core/New.swift:1: conflictedWrites spells \"conflict\", which CONTEXT.md avoids for Sync Outcome. Name it with the glossary's word."

echo "an unrelated name passes silently"
fresh_repo
printf 'case conflicting\n' >"$repo/Sources/Core/New.swift"
check
expect_exit "unrelated" "$status" 0
expect_no_text "unrelated" "$out" "conflicting"

echo "a kept name the tree no longer holds fails, so the list only shrinks"
fresh_repo
printf 'let displayedSessionCount = 1\n' >"$repo/Sources/Core/Old.swift"
git -C "$repo" -c user.name=t -c user.email=t@example.com commit -qam drop
check
expect_exit "gone kept name" "$status" 1
expect_line "gone kept name" "$out" \
    "scripts/vocabulary-avoid.txt:7: kept name conflicts is gone from Sources/ and App/. Delete it, so the list only shrinks."

echo "a phrase no Avoid list backs, or one inside a term's name, fails"
fresh_repo
printf '[avoid]\nworking set\ncoach note\n' >"$repo/scripts/vocabulary-avoid.txt"
check
expect_exit "list problems" "$status" 1
expect_line "list problems" "$out" \
    "scripts/vocabulary-avoid.txt:2: \"working set\" is on no Avoid list in CONTEXT.md or docs/context/. Add it there first, or drop it."
expect_line "list problems" "$out" \
    "scripts/vocabulary-avoid.txt:3: \"coach note\" is words inside the glossary term \"coach note\", so a real name would fail. Reword that Avoid list or drop the phrase."

echo "--all reads every line"
fresh_repo
check --all
expect_exit "--all" "$status" 1
expect_line "--all" "$out" \
    "Sources/Core/Old.swift:1: displayedSessionCount spells \"displayed session\", which CONTEXT.md avoids for Viewed Session. Name it with the glossary's word."

echo "a base this branch did not grow from exits 2, and a bad flag 64"
fresh_repo
check nosuchref
expect_exit "bad base" "$status" 2
expect_line "bad base" "$err" "       The vocabulary check cannot finish, so it fails rather than pass unchecked."
check --nope
expect_exit "bad flag" "$status" 64

echo
echo "$pass passed, $fail failed"
[ "$fail" -eq 0 ]
