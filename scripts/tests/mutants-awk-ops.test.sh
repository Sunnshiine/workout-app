#!/bin/bash
set -uo pipefail

# shellcheck source=scripts/tests/mutants-awk-harness.sh
. "$(dirname "${BASH_SOURCE[0]}")/mutants-awk-harness.sh"

echo "result empties a return to the value its declared type takes, and skips any other type"
cat >"$tmp/F.swift" <<'SWIFT'
func names() -> [String] {
    if flag {
        return conflicts
    }
    return []
}
func table() -> [String: Int] {
    return counts
}
private func pick(at row: Int) async throws -> Int? {
    return first
}
func count() -> Int {
    items.forEach { item in
        return
    }
    return items.count
}
var label: String {
    return name
}
func joined() -> [String] {
    return first +
        second
}
func make(
    a: Int
) -> Double where T: Equatable {
    return a.value
}
var ids: [Int] {
    return all
}
func send() {
    return
}
SWIFT
check "array, dictionary, optional, Int, Double, and computed returns; String, closure, Void, and a split expression are skipped" <<'ROWS'
Sources/F.swift | 2 | negate | if flag { | if !(flag) { |     if !(flag) {
Sources/F.swift | 3 | result | return conflicts | return [] |         return []
Sources/F.swift | 8 | result | return counts | return [:] |     return [:]
Sources/F.swift | 11 | result | return first | return nil |     return nil
Sources/F.swift | 17 | result | return items.count | return 0 |     return 0
Sources/F.swift | 29 | result | return a.value | return 0 |     return 0
Sources/F.swift | 32 | result | return all | return [] |     return []
ROWS

echo "coalesce changes a literal default, and a mutant another op made is not repeated"
cat >"$tmp/F.swift" <<'SWIFT'
let a = name ?? ""
let b = name ?? "none"
let c = count ?? 0
let d = flag ?? false
let e = list ?? []
let f = x ?? y
let g = values[1] ?? 4
SWIFT
check "empty and non-empty strings, an Int after another literal; const and bool already cover the rest" <<'ROWS'
Sources/F.swift | 1 | coalesce | ?? "" | ?? "mutant" | let a = name ?? "mutant"
Sources/F.swift | 2 | coalesce | ?? "none" | ?? "" | let b = name ?? ""
Sources/F.swift | 3 | const | 0 | 1 | let c = count ?? 1
Sources/F.swift | 4 | bool | false | true | let d = flag ?? true
Sources/F.swift | 7 | const | 1 | 2 | let g = values[2] ?? 4
Sources/F.swift | 7 | coalesce | ?? 4 | ?? 5 | let g = values[1] ?? 5
ROWS

echo "operand drops the right side of the first && or ||"
cat >"$tmp/F.swift" <<'SWIFT'
if a && b || c {
guard ready || retries > 0 && open else { return }
let ok = list.contains { $0 > 1 } && done
if f(a && b) {
SWIFT
check "&& stops at ||, || keeps a tighter &&, a closure operand, a parenthesized one" <<'ROWS'
Sources/F.swift | 1 | logic | && | || | if a || b || c {
Sources/F.swift | 1 | negate | if a && b || c { | if !(a && b || c) { | if !(a && b || c) {
Sources/F.swift | 1 | operand | a && b | a | if a || c {
Sources/F.swift | 2 | compare | > | >= | guard ready || retries >= 0 && open else { return }
Sources/F.swift | 2 | logic | || | && | guard ready && retries > 0 && open else { return }
Sources/F.swift | 2 | return | guard ready || retries > 0 && open else | guard false else | guard false else { return }
Sources/F.swift | 2 | const | 0 | 1 | guard ready || retries > 1 && open else { return }
Sources/F.swift | 2 | operand | ready || retries > 0 && open | ready | guard ready else { return }
Sources/F.swift | 3 | compare | > | >= | let ok = list.contains { $0 >= 1 } && done
Sources/F.swift | 3 | logic | && | || | let ok = list.contains { $0 > 1 } || done
Sources/F.swift | 3 | const | 1 | 2 | let ok = list.contains { $0 > 2 } && done
Sources/F.swift | 3 | operand | list.contains { $0 > 1 } && done | list.contains { $0 > 1 } | let ok = list.contains { $0 > 1 }
Sources/F.swift | 4 | logic | && | || | if f(a || b) {
Sources/F.swift | 4 | negate | if f(a && b) { | if !(f(a && b)) { | if !(f(a && b)) {
Sources/F.swift | 4 | operand | a && b | a | if f(a) {
ROWS

echo "always turns the first == comparison into true, outside a declaration"
cat >"$tmp/F.swift" <<'SWIFT'
if kind == .notes {
let same = a.id == b.id && open
return lhs.count == rhs.count ? lhs : rhs
extension Foo where T == Int {
case .x where y == 2:
SWIFT
check "an if, an operand of &&, a ternary test, a generic where clause, a case where clause" <<'ROWS'
Sources/F.swift | 1 | compare | == | != | if kind != .notes {
Sources/F.swift | 1 | negate | if kind == .notes { | if !(kind == .notes) { | if !(kind == .notes) {
Sources/F.swift | 1 | always | kind == .notes | true | if true {
Sources/F.swift | 2 | compare | == | != | let same = a.id != b.id && open
Sources/F.swift | 2 | logic | && | || | let same = a.id == b.id || open
Sources/F.swift | 2 | operand | a.id == b.id && open | a.id == b.id | let same = a.id == b.id
Sources/F.swift | 2 | always | a.id == b.id | true | let same = true && open
Sources/F.swift | 3 | compare | == | != | return lhs.count != rhs.count ? lhs : rhs
Sources/F.swift | 3 | always | lhs.count == rhs.count | true | return true ? lhs : rhs
Sources/F.swift | 4 | compare | == | != | extension Foo where T != Int {
Sources/F.swift | 5 | compare | == | != | case .x where y != 2:
Sources/F.swift | 5 | always | y == 2 | true | case .x where true:
ROWS

echo "no mutant removes the last use of a closure's anonymous argument"
cat >"$tmp/F.swift" <<'SWIFT'
let hit = items.first { $0.id == id }
let pair = zip(a, b).filter { $0 > 1 && $1 }
SWIFT
check "always on \$0 == id, operand dropping the only \$1" <<'ROWS'
Sources/F.swift | 1 | compare | == | != | let hit = items.first { $0.id != id }
Sources/F.swift | 2 | compare | > | >= | let pair = zip(a, b).filter { $0 >= 1 && $1 }
Sources/F.swift | 2 | logic | && | || | let pair = zip(a, b).filter { $0 > 1 || $1 }
Sources/F.swift | 2 | const | 1 | 2 | let pair = zip(a, b).filter { $0 > 2 && $1 }
ROWS

echo "clamp keeps the value a two-argument max or min clamps"
cat >"$tmp/F.swift" <<'SWIFT'
return max(value, 1)
let n = min(max(quarters, 1), 3)
let p = max(0, anchor + delta)
let q = values.max(by: <)
let r = max(a, b, c)
SWIFT
check "a floor, the outer of two clamps, a bound written first, a method, three arguments" <<'ROWS'
Sources/F.swift | 1 | const | 1 | 2 | return max(value, 2)
Sources/F.swift | 1 | clamp | max(value, 1) | value | return value
Sources/F.swift | 2 | const | 1 | 2 | let n = min(max(quarters, 2), 3)
Sources/F.swift | 2 | clamp | min(max(quarters, 1), 3) | max(quarters, 1) | let n = max(quarters, 1)
Sources/F.swift | 3 | const | 0 | 1 | let p = max(1, anchor + delta)
Sources/F.swift | 3 | clamp | max(0, anchor + delta) | (anchor + delta) | let p = (anchor + delta)
ROWS

echo "a closure keeps each anonymous argument it used, counted per closure and outside strings"
cat >"$tmp/F.swift" <<'SWIFT'
let a = rows.filter { "$0" != s && $0.ok }
let b = rows.map { $10 == x && $1 }
let c = rows.filter { ids.contains { $0 == id } && $0.ok }
let d = rows.filter { $0.ok && ready }
SWIFT
check "a \$0 in a string, \$1 beside \$10, an outer closure losing its \$0 while the inner keeps one" <<'ROWS'
Sources/F.swift | 1 | compare | != | == | let a = rows.filter { "$0" == s && $0.ok }
Sources/F.swift | 1 | logic | && | || | let a = rows.filter { "$0" != s || $0.ok }
Sources/F.swift | 2 | compare | == | != | let b = rows.map { $10 != x && $1 }
Sources/F.swift | 2 | logic | && | || | let b = rows.map { $10 == x || $1 }
Sources/F.swift | 3 | compare | == | != | let c = rows.filter { ids.contains { $0 != id } && $0.ok }
Sources/F.swift | 3 | logic | && | || | let c = rows.filter { ids.contains { $0 == id } || $0.ok }
Sources/F.swift | 4 | logic | && | || | let d = rows.filter { $0.ok || ready }
Sources/F.swift | 4 | operand | $0.ok && ready | $0.ok | let d = rows.filter { $0.ok }
ROWS

echo "a \$N in a string interpolation counts as a use, and a \$N in string text does not"
cat >"$tmp/F.swift" <<'SWIFT'
let a = rows.filter { flag && "\($0.name)".isEmpty }
let c = rows.filter { "\($0)" == name && ok }
let e = rows.filter { "\(n)" == "$0" && $0.ok }
let f = rows.filter { "\(label("$0"))" == s && $0.ok }
SWIFT
check "operand and always keep an interpolated \$0, and drop one whose only \$0 is string text" <<'ROWS'
Sources/F.swift | 1 | logic | && | || | let a = rows.filter { flag || "\($0.name)".isEmpty }
Sources/F.swift | 2 | compare | == | != | let c = rows.filter { "\($0)" != name && ok }
Sources/F.swift | 2 | logic | && | || | let c = rows.filter { "\($0)" == name || ok }
Sources/F.swift | 2 | operand | "\($0)" == name && ok | "\($0)" == name | let c = rows.filter { "\($0)" == name }
Sources/F.swift | 3 | compare | == | != | let e = rows.filter { "\(n)" != "$0" && $0.ok }
Sources/F.swift | 3 | logic | && | || | let e = rows.filter { "\(n)" == "$0" || $0.ok }
Sources/F.swift | 3 | always | "\(n)" == "$0" | true | let e = rows.filter { true && $0.ok }
Sources/F.swift | 4 | compare | == | != | let f = rows.filter { "\(label("$0"))" != s && $0.ok }
Sources/F.swift | 4 | logic | && | || | let f = rows.filter { "\(label("$0"))" == s || $0.ok }
Sources/F.swift | 4 | always | "\(label("$0"))" == s | true | let f = rows.filter { true && $0.ok }
ROWS

echo "result makes no equivalent mutant, and skips a continued return and a closure's return"
cat >"$tmp/F.swift" <<'SWIFT'
func a() -> Double {
    return 0.0
}
func b() -> Int {
    return Int.zero
}
func c() -> [Int] {
    return [ ]
}
func d() -> [Int] {
    return [Int]()
}
func e() -> [String: Int] {
    return [String: Int]()
}
func f() -> [Foo] {
    return items
        .filter { $0.ok }
}
func g() -> Int {
    return a
        + b
}
func h() -> Int {
    let x = items.map {
        return 1
    }
    return count
}
func i() -> Int {
    do {
        return try load()
    } catch is Failure {
        return count
    }
}
SWIFT
check "0.0, Int.zero, [ ], [T](), [K: V](), a .filter and a + on the next line, a multi-line closure, do and catch" <<'ROWS'
Sources/F.swift | 2 | const | 0.0 | 1.0 |     return 1.0
Sources/F.swift | 26 | const | 1 | 2 |         return 2
Sources/F.swift | 28 | result | return count | return 0 |     return 0
Sources/F.swift | 32 | result | return try load() | return 0 |         return 0
Sources/F.swift | 34 | result | return count | return 0 |         return 0
ROWS

echo "result makes no equivalent mutant from a zero-argument numeric init"
cat >"$tmp/F.swift" <<'SWIFT'
func a() -> Int {
    return Int()
}
func b() -> Double {
    return Double()
}
func c() -> CGFloat {
    return .init()
}
func d() -> Int {
    return Int(text)
}
SWIFT
check "Int(), Double(), and .init() are skipped, a converting Int(x) is not" <<'ROWS'
Sources/F.swift | 11 | result | return Int(text) | return 0 |     return 0
ROWS

echo "operand and always keep a one-line block's braces"
cat >"$tmp/F.swift" <<'SWIFT'
if a && b { }
if a == b { }
while a < b && c { step() }
SWIFT
check "an if and a while whose block closes on the same line" <<'ROWS'
Sources/F.swift | 1 | logic | && | || | if a || b { }
Sources/F.swift | 1 | negate | if a && b { | if !(a && b) { | if !(a && b) { }
Sources/F.swift | 1 | operand | a && b | a | if a { }
Sources/F.swift | 2 | compare | == | != | if a != b { }
Sources/F.swift | 2 | negate | if a == b { | if !(a == b) { | if !(a == b) { }
Sources/F.swift | 2 | always | a == b | true | if true { }
Sources/F.swift | 3 | compare | < | <= | while a <= b && c { step() }
Sources/F.swift | 3 | logic | && | || | while a < b || c { step() }
Sources/F.swift | 3 | operand | a < b && c | a < b | while a < b { step() }
ROWS

echo
echo "$pass passed, $fail failed"
[ "$fail" -eq 0 ]
