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

expect_text() {
    if printf '%s\n' "$2" | grep -Fq -- "$3"; then ok "$1 has $3"; else bad "$1 is missing the text: $3"; fi
}

expect_no_text() {
    if printf '%s\n' "$2" | grep -Fq -- "$3"; then bad "$1 has the text: $3"; else ok "$1 lacks $3"; fi
}

# A repo whose glossary avoids "displayed session", "tempo", "conflict", "e1rm", "actual rpe", and
# four phrases whose last words inflect differently,
# committed as origin/main with existing names the branch did not add: displayedSessionCount, the
# kept names conflict and conflicts, and the unrelated name conflicting.
fresh_repo() {
    rm -rf "$repo"
    mkdir -p "$repo/Sources/Core" "$repo/App" "$repo/Tests" "$repo/scripts" "$repo/docs/context"
    cat >"$repo/CONTEXT.md" <<'EOF'
**Viewed Session**: The Session on screen. Avoid: displayed session.
**Sync Outcome**: What a flush did. Avoid: conflict.
**Estimated Single**: A one-rep estimate. Avoid: e1rm, actual rpe.
**Ledger**: Past Set Logs. Avoid: history, index, rate, dictation log.
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
e1rm
actual rpe
history
index
rate
dictation log

[kept]
conflict
conflicts

[unrelated]
conflicting
EOF
    cat >"$repo/Sources/Core/Old.swift" <<'EOF'
let displayedSessionCount = 1
let conflicts = 0
func refuse(conflict: Int) -> Int { conflict }
enum Reason { case heard, conflicting }
EOF
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

echo "the widget and shared targets are read too"
fresh_repo
mkdir -p "$repo/WorkoutShared" "$repo/WorkoutWidgets"
printf 'let displayedSession = 1\n' >"$repo/WorkoutShared/Shared.swift"
printf 'let displayedSession = 1\n' >"$repo/WorkoutWidgets/Widget.swift"
check
expect_exit "every target" "$status" 1
for path in WorkoutShared/Shared.swift WorkoutWidgets/Widget.swift; do
    expect_line "every target" "$out" \
        "$path:1: displayedSession spells \"displayed session\", which CONTEXT.md avoids for Viewed Session. Name it with the glossary's word."
done

echo "a phrase inside a longer real word passes"
fresh_repo
printf 'let temporaryRow = 1\nlet contempt = 2\nlet temporal = 3\n' >"$repo/Sources/Core/New.swift"
check
expect_exit "longer word" "$status" 0
expect_no_text "longer word" "$out" "temporal"

echo "a plural or past tense of the phrase's last word fails"
fresh_repo
printf 'let tempos = [1]\nlet conflicted = true\nlet conflictsCount = 2\n' >"$repo/Sources/Core/New.swift"
check
expect_exit "inflection" "$status" 1
expect_line "inflection" "$out" \
    "Sources/Core/New.swift:1: tempos spells \"tempo\", which docs/context/logging.md avoids for Cadence. Name it with the glossary's word."
expect_line "inflection" "$out" \
    "Sources/Core/New.swift:2: conflicted spells \"conflict\", which CONTEXT.md avoids for Sync Outcome. Name it with the glossary's word."
expect_line "inflection" "$out" \
    "Sources/Core/New.swift:3: conflictsCount spells \"conflict\", which CONTEXT.md avoids for Sync Outcome. Name it with the glossary's word."

echo "each English inflection of the last word fails"
fresh_repo
printf 'let histories = 1\nlet indexes = 2\nlet rated = 3\nlet rating = 4\nlet dictationLogged = 5\nlet dictationLogging = 6\nlet rater = 7\n' \
    >"$repo/Sources/Core/New.swift"
check
expect_exit "inflections" "$status" 1
for found in "1: histories spells \"history\"" "2: indexes spells \"index\"" "3: rated spells \"rate\"" \
    "4: rating spells \"rate\"" "5: dictationLogged spells \"dictation log\"" "6: dictationLogging spells \"dictation log\""; do
    expect_line "inflections" "$out" \
        "Sources/Core/New.swift:$found, which CONTEXT.md avoids for Ledger. Name it with the glossary's word."
done
expect_no_text "inflections" "$out" "rater"

echo "digits and acronyms split into the glossary's words"
fresh_repo
printf 'let e1rmValue = 1\nlet E1RMValue = 2\nlet actualRPE = 3\nlet actualRPEText = 4\n' >"$repo/Sources/Core/New.swift"
check
expect_exit "digits and acronyms" "$status" 1
expect_line "digits and acronyms" "$out" \
    "Sources/Core/New.swift:1: e1rmValue spells \"e1rm\", which CONTEXT.md avoids for Estimated Single. Name it with the glossary's word."
expect_line "digits and acronyms" "$out" \
    "Sources/Core/New.swift:2: E1RMValue spells \"e1rm\", which CONTEXT.md avoids for Estimated Single. Name it with the glossary's word."
expect_line "digits and acronyms" "$out" \
    "Sources/Core/New.swift:3: actualRPE spells \"actual rpe\", which CONTEXT.md avoids for Estimated Single. Name it with the glossary's word."
expect_line "digits and acronyms" "$out" \
    "Sources/Core/New.swift:4: actualRPEText spells \"actual rpe\", which CONTEXT.md avoids for Estimated Single. Name it with the glossary's word."

echo "renaming an avoided name to the glossary's word passes"
fresh_repo
printf 'let viewedSessionCount = 1\nlet conflicts = 0\nfunc refuse(conflict: Int) -> Int { conflict }\nenum Reason { case heard, conflicting }\n' \
    >"$repo/Sources/Core/Old.swift"
check
expect_exit "rename" "$status" 0

echo "a moved file's existing names are not new"
fresh_repo
mkdir -p "$repo/Sources/Moved"
git -C "$repo" mv Sources/Core/Old.swift Sources/Moved/Old.swift
check
expect_exit "moved, staged" "$status" 0
expect_no_text "moved, staged" "$out" "displayedSessionCount"
git -C "$repo" -c user.name=t -c user.email=t@example.com commit -qm move
printf 'let viewedSession = 2\n' >>"$repo/Sources/Moved/Old.swift"
check
expect_exit "moved, committed and edited" "$status" 0
expect_no_text "moved, committed and edited" "$out" "displayedSessionCount"

echo "comments and string literals are not identifiers"
fresh_repo
printf '// displayedSession was renamed\nlet label = "tempoLabel"\n' >"$repo/Sources/Core/New.swift"
check
expect_exit "comment and string" "$status" 0

echo "a kept name gets a note and passes, and a new name that spells its phrase fails"
fresh_repo
printf 'let total = conflicts + 1\nlet n = refuse(conflict: total)\n' >"$repo/Sources/Core/New.swift"
check
expect_exit "kept name" "$status" 0
expect_line "kept name" "$out" \
    "note: Sources/Core/New.swift:2: conflict spells \"conflict\", which CONTEXT.md avoids for Sync Outcome. It is a kept name, so this line passes. A new name must use the glossary's word."
expect_line "kept name" "$out" \
    "note: Sources/Core/New.swift:1: conflicts spells \"conflict\", which CONTEXT.md avoids for Sync Outcome. It is a kept name, so this line passes. A new name must use the glossary's word."
printf 'let conflictedWrites = conflicts\n' >"$repo/Sources/Core/New.swift"
check
expect_exit "new conflict name" "$status" 1
expect_line "new conflict name" "$out" \
    "Sources/Core/New.swift:1: conflictedWrites spells \"conflict\", which CONTEXT.md avoids for Sync Outcome. Name it with the glossary's word."

echo "a new declaration of a kept spelling is a new name and fails"
fresh_repo
printf 'let conflict = 1\n' >"$repo/Sources/Core/New.swift"
check
expect_exit "new let conflict" "$status" 1
expect_line "new let conflict" "$out" \
    "Sources/Core/New.swift:1: conflict declares the kept name anew (the tree declared it 1 time, now 2), and it spells \"conflict\", which CONTEXT.md avoids for Sync Outcome. Name it with the glossary's word."
printf 'struct Flush {\n    var conflicts: [Int] = []\n}\n' >"$repo/Sources/Core/New.swift"
check
expect_exit "new var conflicts" "$status" 1
expect_line "new var conflicts" "$out" \
    "Sources/Core/New.swift:2: conflicts declares the kept name anew (the tree declared it 1 time, now 2), and it spells \"conflict\", which CONTEXT.md avoids for Sync Outcome. Name it with the glossary's word."
printf 'func retry(conflicts: [Int]) {}\nlet drop = { (conflict: Int) in conflict }\n' >"$repo/Sources/Core/New.swift"
check
expect_exit "new parameters" "$status" 1
expect_line "new parameters" "$out" \
    "Sources/Core/New.swift:1: conflicts declares the kept name anew (the tree declared it 1 time, now 2), and it spells \"conflict\", which CONTEXT.md avoids for Sync Outcome. Name it with the glossary's word."
expect_line "new parameters" "$out" \
    "Sources/Core/New.swift:2: conflict declares the kept name anew (the tree declared it 1 time, now 2), and it spells \"conflict\", which CONTEXT.md avoids for Sync Outcome. Name it with the glossary's word."

echo "a wrapped signature's parameters are declarations too"
fresh_repo
printf 'func retry(\n    _ conflict: Int,\n    conflicts: [Int] = [max(1, 2)]\n) { _ = refuse(conflict: 1) }\nenum Refusal {\n    case stale(\n        conflicting: Int)\n}\nlet n = refuse(\n    conflict: 1)\n' \
    >"$repo/Sources/Core/New.swift"
check
expect_exit "wrapped signature" "$status" 1
expect_line "wrapped signature" "$out" \
    "Sources/Core/New.swift:2: conflict declares the kept name anew (the tree declared it 1 time, now 2), and it spells \"conflict\", which CONTEXT.md avoids for Sync Outcome. Name it with the glossary's word."
expect_line "wrapped signature" "$out" \
    "Sources/Core/New.swift:3: conflicts declares the kept name anew (the tree declared it 1 time, now 2), and it spells \"conflict\", which CONTEXT.md avoids for Sync Outcome. Name it with the glossary's word."
expect_line "wrapped signature" "$out" \
    "Sources/Core/New.swift:7: conflicting declares the unrelated name anew (the tree declared it 1 time, now 2), and it spells \"conflict\", which CONTEXT.md avoids for Sync Outcome. Name it with the glossary's word."
expect_no_text "wrapped signature" "$out" "New.swift:4: conflict declares"
expect_line "wrapped signature" "$out" \
    "note: Sources/Core/New.swift:4: conflict spells \"conflict\", which CONTEXT.md avoids for Sync Outcome. It is a kept name, so this line passes. A new name must use the glossary's word."
expect_line "wrapped signature" "$out" \
    "note: Sources/Core/New.swift:10: conflict spells \"conflict\", which CONTEXT.md avoids for Sync Outcome. It is a kept name, so this line passes. A new name must use the glossary's word."

echo "a parameter after a closure-typed one is a declaration"
fresh_repo
printf 'func retry(handler: (Int) -> Void, conflict: Int) {}\n' >"$repo/Sources/Core/New.swift"
check
expect_exit "after a closure type" "$status" 1
expect_line "after a closure type" "$out" \
    "Sources/Core/New.swift:1: conflict declares the kept name anew (the tree declared it 1 time, now 2), and it spells \"conflict\", which CONTEXT.md avoids for Sync Outcome. Name it with the glossary's word."

echo "tuples, comma chains, case patterns, labels, and capture lists declare names too"
fresh_repo
cat >"$repo/Sources/Core/New.swift" <<'EOF2'
let (a, conflict) = (1, 2)
for (offset: i, element: conflict) in [9].enumerated() {}
var b = 1, conflict = 2
if case let .stale(at: conflict) = reason {}
func f(_ x: Int, conflicts c: Int) {}
func totals() -> (conflict: Int, total: Int) { (1, 2) }
let pair: (conflict: Int, Int) = (1, 2)
let drop = { [weak self] conflict in conflict }
let list = [1, 2], k = retry(1, conflict: 1)
typealias Pair = (conflict: Int, Int)
let keep = { [conflict = 1] in conflict }
func g(@Wrapped conflict: Int) {}
EOF2
check
expect_exit "declaration forms" "$status" 1
for line in 1 2 3 4 6 7 8 10 11 12; do
    expect_text "declaration forms" "$out" "Sources/Core/New.swift:$line: conflict declares the kept name anew"
done
expect_text "declaration forms" "$out" "Sources/Core/New.swift:5: conflicts declares the kept name anew"
expect_no_text "declaration forms" "$out" "New.swift:9: conflict declares"
expect_text "declaration forms" "$out" "note: Sources/Core/New.swift:9: conflict spells"

echo "moving a kept declaration to another file is not a new one"
fresh_repo
printf 'let displayedSessionCount = 1\nfunc refuse(conflict: Int) -> Int { conflict }\nenum Reason { case heard, conflicting }\n' \
    >"$repo/Sources/Core/Old.swift"
printf 'let conflicts = 0\n' >"$repo/Sources/Core/New.swift"
check
expect_exit "moved declaration" "$status" 0
expect_line "moved declaration" "$out" \
    "note: Sources/Core/New.swift:1: conflicts spells \"conflict\", which CONTEXT.md avoids for Sync Outcome. It is a kept name, so this line passes. A new name must use the glossary's word."

echo "an unrelated name passes silently, and a new declaration of it fails"
fresh_repo
printf 'let reason = Reason.conflicting\nif case .conflicting = reason {}\n' >"$repo/Sources/Core/New.swift"
check
expect_exit "unrelated" "$status" 0
expect_no_text "unrelated" "$out" "conflicting"
printf 'enum Refusal { case stale, conflicting }\n' >"$repo/Sources/Core/New.swift"
check
expect_exit "new unrelated case" "$status" 1
expect_line "new unrelated case" "$out" \
    "Sources/Core/New.swift:1: conflicting declares the unrelated name anew (the tree declared it 1 time, now 2), and it spells \"conflict\", which CONTEXT.md avoids for Sync Outcome. Name it with the glossary's word."

echo "a name the branch adds to [unrelated] with its declaration passes"
fresh_repo
printf 'let conflictingField = 1\n' >"$repo/Sources/Core/New.swift"
printf 'conflictingField\n' >>"$repo/scripts/vocabulary-avoid.txt"
check
expect_exit "new unrelated entry" "$status" 0
expect_line "new unrelated entry" "$out" \
    "note: Sources/Core/New.swift:1: conflictingField declares a name this branch adds to [unrelated] (scripts/vocabulary-avoid.txt:18), so it passes. Review the entry with it."
printf 'let conflicting = 2\n' >>"$repo/Sources/Core/New.swift"
check
expect_exit "new unrelated entry, old name redeclared" "$status" 1

echo "a name the branch adds to [kept] is no hatch for its declaration"
fresh_repo
printf '[avoid]\nconflict\n\n[kept]\nconflict\nconflicts\nconflictCount\n\n[unrelated]\nconflicting\n' \
    >"$repo/scripts/vocabulary-avoid.txt"
printf 'let conflictCount = 1\n' >"$repo/Sources/Core/New.swift"
check
expect_exit "new kept entry" "$status" 1
expect_line "new kept entry" "$out" \
    "Sources/Core/New.swift:1: conflictCount declares the kept name anew (the tree declared it 0 times, now 1), and it spells \"conflict\", which CONTEXT.md avoids for Sync Outcome. Name it with the glossary's word."

echo "a name in two sections is a list problem, and listing it again exempts nothing"
fresh_repo
printf 'conflicts\n' >>"$repo/scripts/vocabulary-avoid.txt"
printf 'let conflicts = 2\n' >"$repo/Sources/Core/New.swift"
check
expect_exit "listed twice" "$status" 1
expect_line "listed twice" "$out" \
    "scripts/vocabulary-avoid.txt:18: conflicts is listed in [kept] at line 14 and again in [unrelated]. List it once."
expect_line "listed twice" "$out" \
    "Sources/Core/New.swift:1: conflicts declares the kept name anew (the tree declared it 1 time, now 2), and it spells \"conflict\", which CONTEXT.md avoids for Sync Outcome. Name it with the glossary's word."

echo "a kept name the branch moves to [unrelated] is not new to the list"
fresh_repo
grep -vx conflicts "$repo/scripts/vocabulary-avoid.txt" >"$root/list"
printf 'conflicts\n' >>"$root/list"
mv "$root/list" "$repo/scripts/vocabulary-avoid.txt"
printf 'let conflicts = 2\n' >"$repo/Sources/Core/New.swift"
check
expect_exit "moved to unrelated" "$status" 1
expect_line "moved to unrelated" "$out" \
    "Sources/Core/New.swift:1: conflicts declares the unrelated name anew (the tree declared it 1 time, now 2), and it spells \"conflict\", which CONTEXT.md avoids for Sync Outcome. Name it with the glossary's word."

echo "a kept name the tree no longer holds fails, so the list only shrinks"
fresh_repo
printf 'let displayedSessionCount = 1\nfunc refuse(conflict: Int) -> Int { conflict }\n// conflicts\nenum Reason { case heard, conflicting }\n' \
    >"$repo/Sources/Core/Old.swift"
git -C "$repo" -c user.name=t -c user.email=t@example.com commit -qam drop
check
expect_exit "gone kept name" "$status" 1
expect_line "gone kept name" "$out" \
    "scripts/vocabulary-avoid.txt:14: kept name conflicts is gone from the Swift this check reads. Delete it, so the list only shrinks."

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
