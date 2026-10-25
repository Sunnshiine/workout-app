#!/usr/bin/env bash
set -uo pipefail

script_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
tool="$script_dir/../tests-for.py"

tmp=$(mktemp -d) || exit 3
trap 'rm -rf "$tmp"' EXIT
pass=0
fail=0

ok()  { pass=$((pass + 1)); printf '  ok   %s\n' "$1"; }
bad() { fail=$((fail + 1)); printf '  FAIL %s\n' "$1"; }

expect() {
    if [ "$2" = "$3" ]; then ok "$1"; else bad "$1"; printf '    want: %s\n    got:  %s\n' "${3//$'\n'/ | }" "${2//$'\n'/ | }"; fi
}

root=$tmp/repo
mkdir -p "$root/WorkoutTracker.xcodeproj" "$root/App/Views" "$root/Sources/Core" \
    "$root/Tests/Visual" "$root/Tests/UI" "$root/Tests/Unit" "$root/Tests/Support"
target() {
    printf '\t\tAA /* %s */ = {\n\t\t\tisa = PBXNativeTarget;\n\t\t\tfileSystemSynchronizedGroups = (\n' "$1"
    shift 1
    local name=$1
    shift
    for folder in "$@"; do printf '\t\t\t\tBB /* %s */,\n' "$folder"; done
    printf '\t\t\t);\n\t\t\tname = %s;\n\t\t\tproductName = %s;\n\t\t};\n' "$name" "$name"
}
{
    target App WorkoutTracker App
    target Snap WorkoutTrackerSnapshotTests Visual Support
    target UI WorkoutTrackerUITests UI
    target Unit WorkoutTrackerTests Unit Support
} >"$root/WorkoutTracker.xcodeproj/project.pbxproj"

cat >"$root/App/Views/Card.swift" <<'SWIFT'
struct Card: View {
    enum History { case none }
    var body: some View { Badge().accessibilityIdentifier("card-button") }
}
SWIFT
cat >"$root/App/Views/Badge.swift" <<'SWIFT'
#if DEBUG
    struct Badge: View {
        var body: some View { Text("{") }
    }
#endif
SWIFT
printf 'struct Orphan {}\n' >"$root/App/Views/Orphan.swift"
printf 'struct Ledger {}\n' >"$root/Sources/Core/Ledger.swift"
printf 'extension Ledger {\n    func total() {}\n}\n' >"$root/Sources/Core/LedgerTotals.swift"
cat >"$root/Tests/Visual/CardVisualTests.swift" <<'SWIFT'
@Suite(.snapshots(record: .never))
struct CardVisualTests {
    @Test func cardMatchesBaseline() { _ = Card() }
}
SWIFT
cat >"$root/Tests/Visual/CardHost.swift" <<'SWIFT'
enum History { case none }
enum CardHost { static func make() -> Card { Card() } }
SWIFT
cat >"$root/Tests/Visual/HostedLayoutTests.swift" <<'SWIFT'
@Suite
struct HostedLayoutTests {
    @Test func fits() { _ = CardHost.make() }
}
// Orphan is mentioned only in this comment.
SWIFT
cat >"$root/Tests/UI/FlowUITests.swift" <<'SWIFT'
final class FlowUITests: XCTestCase {
    func testTapsTheCard() { app.buttons["card-button"].tap() }
}
SWIFT
cat >"$root/Tests/Unit/HistoryTests.swift" <<'SWIFT'
@Suite
struct HistoryTests {
    @Test func readsHistory() { _ = History.self; _ = Ledger() }
}
SWIFT
cat >"$root/Tests/Unit/LedgerTests.swift" <<'SWIFT'
@MainActor
@Test(arguments: [(1, 2)]) func ledgerAddsUp(pair: (Int, Int)) { _ = Ledger() }
SWIFT
git -C "$root" init -q -b main
git -C "$root" add -A
git -C "$root" -c user.name=t -c user.email=t@t commit -qm base

run() { (cd "$root" && "$tool" "$@" 2>"$tmp/err"); }

expect "a view prints the suites that name its top-level type, through a test helper, and its accessibility ID" \
    "$(run App/Views/Card.swift)" \
    "WorkoutTrackerSnapshotTests/CardVisualTests
WorkoutTrackerSnapshotTests/HostedLayoutTests
WorkoutTrackerUITests/FlowUITests"
expect "a test helper's type reaches only suites in its own folder" \
    "$(run Tests/Visual/CardHost.swift)" "WorkoutTrackerSnapshotTests/HostedLayoutTests"
card=$(run App/Views/Card.swift)
expect "a view no suite names takes the suites of the view that uses it" "$(run App/Views/Badge.swift)" "$card"
expect "and says which view on stderr" "$(cat "$tmp/err")" \
    "tests-for: no suite names App/Views/Badge.swift, so these are the suites of App/Views/Card.swift"
expect "a comment does not count, and an uncovered file prints nothing" "$(run App/Views/Orphan.swift)" ""
expect "and says the UI tests launch it, on stderr" "$(cat "$tmp/err")" \
    "tests-for: no suite reaches App/Views/Orphan.swift; every WorkoutTrackerUITests test launches the app"
printf 'struct Unused {}\n' >"$root/Sources/Core/Unused.swift"
run Sources/Core/Unused.swift >/dev/null
expect "an uncovered Sources file says no suite covers it" "$(cat "$tmp/err")" \
    "tests-for: no suite covers Sources/Core/Unused.swift"
expect "a file of extensions takes the suites of the type it extends" \
    "$(run Sources/Core/LedgerTotals.swift)" "WorkoutTrackerTests/HistoryTests
WorkoutTrackerTests/ledgerAddsUp()"
expect "a test file prints its own suites" \
    "$(run Tests/UI/FlowUITests.swift)" "WorkoutTrackerUITests/FlowUITests"
expect "a test function name prints its full ID" \
    "$(run testTapsTheCard)" "WorkoutTrackerUITests/FlowUITests/testTapsTheCard"
expect "a test function outside every type prints as <target>/<name>()" \
    "$(run ledgerAddsUp)" "WorkoutTrackerTests/ledgerAddsUp()"
expect "a path works from a subdirectory" \
    "$(cd "$root/App" && "$tool" Views/Orphan.swift ../Tests/UI/FlowUITests.swift 2>/dev/null)" \
    "WorkoutTrackerUITests/FlowUITests"

printf '\n' >>"$root/App/Views/Badge.swift"
expect "with no file, reads the files changed since HEAD left the base" \
    "$(run --base main)" "$card"

run --nope >/dev/null
expect "an unknown option exits 2" "$?" 2
run --help >"$tmp/help"
expect "--help exits 0" "$?" 0
expect "--help leads with what it prints" "$(head -1 "$tmp/help")" \
    "Print the test IDs that cover the given files, one per line, for scripts/test-sim.sh."

printf '\n%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
