#!/usr/bin/env bash
set -uo pipefail

# shellcheck source=scripts/tests/lint-vocabulary-harness.sh
. "$(dirname "${BASH_SOURCE[0]}")/lint-vocabulary-harness.sh"

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

echo "closures with a return type, effects, or attributes, for await, backticks, generics, and cases declare names too"
fresh_repo
cat >"$repo/Sources/Core/New.swift" <<'EOF2'
let f1 = { (conflict: Int) -> Int in 1 }
let f2 = { conflict -> Int in 1 }
let f3 = { @MainActor (conflict: Int) in 1 }
let f4 = { @Sendable [weak self] conflict in 1 }
let f5 = { (a: Int, conflict: Int) async throws -> Int in a }
for await conflict in stream {}
for try await conflict in stream {}
let `conflict` = 1
let (a, (b, conflict)) = (1, (2, 3))
func g<conflict>(_ x: conflict) {}
enum E { case x; case conflict }
enum F { @available(*, deprecated) case conflict }
var t: [(a: Int, conflict: Int)] = []
let u = v as? (a: Int, conflict: Int)
do {} catch let E.a(conflict) {}
func h(@Foo(bar) conflict: Int) {}
let f6 = items.map {
    conflict in conflict
}
for try await (a, conflict) in pairs {}
var w: Set<(conflict: Int, b: Int)> = []
var d: [String: (a: Int, conflict: Int)] = [:]
let f7 = { (_ conflict: Int) in 1 }
EOF2
check
expect_exit "round 4 forms" "$status" 1
for line in 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 18 20 21 22 23; do
    expect_text "round 4 forms" "$out" "Sources/Core/New.swift:$line: conflict declares the kept name anew"
done

echo "a reference after a case pattern's closing paren, or in a switch case, is no declaration"
fresh_repo
cat >"$repo/Sources/Core/New.swift" <<'EOF2'
if case .a(let q) = x, check(y, conflict: 1) {}
guard case .a(let q) = x, check(q, conflict: 1) else { return }
switch x { case .a(let q) where f(q, conflict: 1): break; default: break }
switch x { case a: break; case conflict: break }
EOF2
check
expect_exit "references after patterns" "$status" 0
for line in 1 2 3 4; do
    expect_text "references after patterns" "$out" "note: Sources/Core/New.swift:$line: conflict spells"
done
echo
echo "$pass passed, $fail failed"
[ "$fail" -eq 0 ]
