#!/bin/bash
set -uo pipefail

# shellcheck source=scripts/tests/mutants-awk-harness.sh
. "$(dirname "${BASH_SOURCE[0]}")/mutants-awk-harness.sh"

echo "each op mutates its first match"
cat >"$tmp/F.swift" <<'SWIFT'
func f(a: Int, b: Int, flag: Bool) -> Bool {
    if a < b && flag {
        return true
    } else if a >= 17.5 {
    }
    guard a != b else { return false }
}
SWIFT
check "every op" <<'ROWS'
Sources/F.swift | 2 | compare | < | <= |     if a <= b && flag {
Sources/F.swift | 2 | logic | && | || |     if a < b || flag {
Sources/F.swift | 2 | negate | if a < b && flag { | if !(a < b && flag) { |     if !(a < b && flag) {
Sources/F.swift | 2 | operand | a < b && flag | a < b |     if a < b {
Sources/F.swift | 3 | bool | true | false |         return false
Sources/F.swift | 4 | compare | >= | > |     } else if a > 17.5 {
Sources/F.swift | 4 | negate | if a >= 17.5 { | if !(a >= 17.5) { |     } else if !(a >= 17.5) {
Sources/F.swift | 4 | const | 17.5 | 18.5 |     } else if a >= 18.5 {
Sources/F.swift | 6 | bool | false | true |     guard a != b else { return true }
Sources/F.swift | 6 | compare | != | == |     guard a == b else { return false }
Sources/F.swift | 6 | return | guard a != b else | guard false else |     guard false else { return false }
ROWS

echo "bindings and top-level condition lists are never negated or forced"
cat >"$tmp/F.swift" <<'SWIFT'
guard let c = Optional(a) else { return false }
guard a > 0, b > 0 else { return false }
if let d = Optional(b), d == 2 {
if var e = d {
if case .some = x {
if f(a, b) > 1 {
if !isEmpty { return }
SWIFT
check "if let, guard a, b else, if case" <<'ROWS'
Sources/F.swift | 1 | bool | false | true | guard let c = Optional(a) else { return true }
Sources/F.swift | 2 | bool | false | true | guard a > 0, b > 0 else { return true }
Sources/F.swift | 2 | compare | > | >= | guard a >= 0, b > 0 else { return false }
Sources/F.swift | 2 | const | 0 | 1 | guard a > 1, b > 0 else { return false }
Sources/F.swift | 3 | compare | == | != | if let d = Optional(b), d != 2 {
Sources/F.swift | 3 | const | 2 | 3 | if let d = Optional(b), d == 3 {
Sources/F.swift | 3 | always | d == 2 | true | if let d = Optional(b), true {
Sources/F.swift | 6 | compare | > | >= | if f(a, b) >= 1 {
Sources/F.swift | 6 | negate | if f(a, b) > 1 { | if !(f(a, b) > 1) { | if !(f(a, b) > 1) {
Sources/F.swift | 6 | const | 1 | 2 | if f(a, b) > 2 {
Sources/F.swift | 7 | negate | if !isEmpty { | if !(!isEmpty) { | if !(!isEmpty) { return }
ROWS

echo "string literals and comments are masked, and state ends with them"
cat >"$tmp/F.swift" <<'SWIFT'
let s = "a == b || \(a > b) true 3"
let m = a == 1 // b != 2 && true
let raw = #"a == "b" > 3"#
let s2 = "\(flag ? "yes" : "no") == done"
// if a == b { return true }
/* if a == b {
   let k = 1 > 0
*/
/// if a == b {
let t = """
    a == b && 4 > 3
    """.count > 1
let after = a > 1
SWIFT
check "== inside a string, a // tail, a \"\"\" block" <<'ROWS'
Sources/F.swift | 2 | compare | == | != | let m = a != 1 // b != 2 && true
Sources/F.swift | 2 | const | 1 | 2 | let m = a == 2 // b != 2 && true
Sources/F.swift | 2 | always | a == 1 | true | let m = true // b != 2 && true
Sources/F.swift | 12 | compare | > | >= |     """.count >= 1
Sources/F.swift | 12 | const | 1 | 2 |     """.count > 2
Sources/F.swift | 13 | compare | > | >= | let after = a >= 1
Sources/F.swift | 13 | const | 1 | 2 | let after = a > 2
ROWS

echo "non-ASCII text in code, strings, and comments"
cat >"$tmp/F.swift" <<'SWIFT'
guard let match = s.wholeMatch(of: /(\d+)(?:\s*[-–]\s*(\d+))?/), let low = Int(match.1) else { return nil }
let label = "5 × 3" + "·" + (a > 2 ? "–" : "") // ½ rep
let größe = 1
SWIFT
check "en dash in a regex literal, × in a string, ½ in a comment" <<'ROWS'
Sources/F.swift | 2 | compare | > | >= | let label = "5 × 3" + "·" + (a >= 2 ? "–" : "") // ½ rep
Sources/F.swift | 2 | const | 2 | 3 | let label = "5 × 3" + "·" + (a > 3 ? "–" : "") // ½ rep
Sources/F.swift | 3 | const | 1 | 2 | let größe = 2
ROWS

echo "operators that only look like comparisons never match"
cat >"$tmp/F.swift" <<'SWIFT'
func g<T>(_ x: Array<Int>) -> T {
let y = x.first! != 0
let same = obj === other || a !== b
let w = a << 2 >> 1
let r = 0..<n
SWIFT
check "Array<Int>, ->, x! and !=, ===, !==, <<, ..<" <<'ROWS'
Sources/F.swift | 2 | compare | != | == | let y = x.first! == 0
Sources/F.swift | 2 | const | 0 | 1 | let y = x.first! != 1
Sources/F.swift | 3 | logic | || | && | let same = obj === other && a !== b
Sources/F.swift | 3 | operand | obj === other || a !== b | obj === other | let same = obj === other
Sources/F.swift | 4 | const | 2 | 3 | let w = a << 3 >> 1
Sources/F.swift | 5 | const | 0 | 1 | let r = 1..<n
ROWS

echo "a constant is a standalone literal, bumped in its integer part"
cat >"$tmp/F.swift" <<'SWIFT'
let r = 6...10
let z = $0 + v2 + x.0 + 0x1F + 1e5
let d = 0.25
@State private var count = 3
let big = 1_000
SWIFT
check "integer, range, decimal, identifiers and tuple members" <<'ROWS'
Sources/F.swift | 1 | const | 6 | 7 | let r = 7...10
Sources/F.swift | 3 | const | 0.25 | 1.25 | let d = 1.25
Sources/F.swift | 4 | const | 3 | 4 | @State private var count = 4
Sources/F.swift | 5 | const | 1_000 | 1001 | let big = 1001
ROWS

echo "a literal directly before a colon is a dictionary key or a case label, so the next one is bumped"
cat >"$tmp/F.swift" <<'SWIFT'
let table = [1: 100, 2: 200]
case 3:
let pick = a ? 2 : 0
let named = f(x: 4)
SWIFT
check "dictionary key, case label, ternary, argument label" <<'ROWS'
Sources/F.swift | 1 | const | 100 | 101 | let table = [1: 101, 2: 200]
Sources/F.swift | 3 | const | 2 | 3 | let pick = a ? 3 : 0
Sources/F.swift | 4 | const | 4 | 5 | let named = f(x: 5)
ROWS

echo "declarations, directives, and crash or log calls are never mutated"
cat >"$tmp/F.swift" <<'SWIFT'
import Foundation
@testable import WorkoutTracker
@available(iOS 17, *)
@MainActor
#if DEBUG || targetEnvironment(simulator)
#elseif os(iOS) && true
#else
#endif
if #available(iOS 18, *) {
precondition(a > 0)
assert(a == b)
print(a == b)
fatalError("a == b")
SWIFT
check "import, attributes, #if, #available, fatalError, precondition, assert, print" </dev/null

echo "only changed lines produce rows"
cat >"$tmp/F.swift" <<'SWIFT'
if a == b {
if a == b {
SWIFT
check "changed line 2, unchanged line 1" 2 <<'ROWS'
Sources/F.swift | 2 | compare | == | != | if a != b {
Sources/F.swift | 2 | negate | if a == b { | if !(a == b) { | if !(a == b) {
Sources/F.swift | 2 | always | a == b | true | if true {
ROWS

echo "a platform's compiled-out #if branches go to compiledOut; other conditions stay compiled in"
cat >"$tmp/F.swift" <<'SWIFT'
#if os(iOS)
let total = a
    + 1
#elseif os(macOS)
let mac = true
#else
let other = true
#endif
#if !canImport(UIKit) // AppKit only
let appKit = true
#endif
#if DEBUG
let debug = true
#if canImport(AppKit)
let nested = true
#endif
#else
let release = true
#endif
let banner = """
#if os(iOS)
"""
let after = true
SWIFT
PLATFORM=macOS check "macOS: os(iOS), #else after a taken branch, and canImport(UIKit) are compiled out" <<'ROWS'
Sources/F.swift | 5 | bool | true | false | let mac = false
Sources/F.swift | 10 | bool | true | false | let appKit = false
Sources/F.swift | 13 | bool | true | false | let debug = false
Sources/F.swift | 15 | bool | true | false | let nested = false
Sources/F.swift | 18 | bool | true | false | let release = false
Sources/F.swift | 23 | bool | true | false | let after = false
compiled out: Sources/F.swift | 3 | const | 1 | 2 |     + 2
compiled out: Sources/F.swift | 7 | bool | true | false | let other = false
ROWS
PLATFORM=iOS check "iOS: os(macOS), #else, !canImport(UIKit), and canImport(AppKit) under DEBUG are compiled out" <<'ROWS'
Sources/F.swift | 3 | const | 1 | 2 |     + 2
Sources/F.swift | 13 | bool | true | false | let debug = false
Sources/F.swift | 18 | bool | true | false | let release = false
Sources/F.swift | 23 | bool | true | false | let after = false
compiled out: Sources/F.swift | 5 | bool | true | false | let mac = false
compiled out: Sources/F.swift | 7 | bool | true | false | let other = false
compiled out: Sources/F.swift | 10 | bool | true | false | let appKit = false
compiled out: Sources/F.swift | 15 | bool | true | false | let nested = false
ROWS
check "no platform compiles every branch in" <<'ROWS'
Sources/F.swift | 3 | const | 1 | 2 |     + 2
Sources/F.swift | 5 | bool | true | false | let mac = false
Sources/F.swift | 7 | bool | true | false | let other = false
Sources/F.swift | 10 | bool | true | false | let appKit = false
Sources/F.swift | 13 | bool | true | false | let debug = false
Sources/F.swift | 15 | bool | true | false | let nested = false
Sources/F.swift | 18 | bool | true | false | let release = false
Sources/F.swift | 23 | bool | true | false | let after = false
ROWS

echo "mutate.sh --help names every op this generator makes"
help=$(bash -c '. "$1" && usage' _ "$script_dir/../mutate-usage.sh")
missing=""
for op in $(sed -n 's/^# (\(.*\)) yields.*/\1/p' "$generator" | tr -d ' ' | tr ',' ' '); do
    grep -Eq "^ +$op +[^ ]" <<<"$help" || missing="$missing $op"
done
if [ -n "$(sed -n 's/^# (\(.*\)) yields.*/\1/p' "$generator")" ] && [ -z "$missing" ]; then
    ok "every op in the mutants.awk header has a row in mutate.sh --help"
else
    bad "every op in the mutants.awk header has a row in mutate.sh --help; missing:$missing"
fi

echo "a missing changed list is a usage error"
awk -v path=Sources/F.swift -f "$scan" -f "$generator" "$tmp/F.swift" >/dev/null 2>&1
status=$?
if [ "$status" -eq 2 ]; then ok "no changed list exits 2"; else bad "no changed list exits 2, got $status"; fi

echo
echo "$pass passed, $fail failed"
[ "$fail" -eq 0 ]
