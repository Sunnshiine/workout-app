#!/usr/bin/env bash
set -uo pipefail

# shellcheck source=scripts/tests/lint-vocabulary-harness.sh
. "$(dirname "${BASH_SOURCE[0]}")/lint-vocabulary-harness.sh"

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
echo
echo "$pass passed, $fail failed"
[ "$fail" -eq 0 ]
