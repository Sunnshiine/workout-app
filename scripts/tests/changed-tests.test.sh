#!/bin/bash
set -uo pipefail

script_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
root=$(mktemp -d) || exit 3
trap 'rm -rf "$root"' EXIT
repo=$root/repo
mkdir -p "$repo/scripts" "$repo/Tests/Unit" "$repo/Tests/Component" "$repo/Tests/Support"
cp "$script_dir/../changed-tests.sh" "$repo/scripts/"
pass=0
fail=0

ok()  { pass=$((pass + 1)); printf '  ok   %s\n' "$1"; }
bad() { fail=$((fail + 1)); printf '  FAIL %s\n' "$1"; }

cat >"$repo/Tests/Unit/TopLevelTests.swift" <<'SWIFT'
import Testing
@MainActor
@Test func aTopLevelTest() async throws { #expect(true) }
@Test func aTestToDelete() { #expect(true) }
@Test func aTestToRename() { #expect(true) }
@Test func anUntouchedTest() { #expect(true) }
@Test func aMultiLineTest() {
    let one = 1
    #expect(one == 1)
}
private func aHelperAfterTheTests() -> Int { 1 }
SWIFT
cat >"$repo/Tests/Unit/NestedTests.swift" <<'SWIFT'
import Testing
@Suite("Display name")
struct NestedTests {
    @Test func aNestedTest() { #expect(true) }
    @Test(
        arguments: [1, 2]
    )
    func aParametrizedTest(n: Int) { #expect(n > 0) }
    func aHelperThatIsNoTest() {}
}
SWIFT
cat >"$repo/Tests/Support/HeldThing.swift" <<'SWIFT'
@MainActor final class HeldThing { func hold() {} }
SWIFT
cat >"$repo/Tests/Component/UntouchedTests.swift" <<'SWIFT'
import Testing
@Test func anUntouchedTest() { #expect(true) }
SWIFT
git -C "$repo" init -q -b main
git -C "$repo" config user.email test@example.com
git -C "$repo" config user.name test
git -C "$repo" config commit.gpgsign false
git -C "$repo" add -A && git -C "$repo" commit -qm base
base=$(git -C "$repo" rev-parse HEAD)

check() {
    local name=$1 want=$2 want_err=$3 out err
    out=$(cd "$repo" && scripts/changed-tests.sh --base "$base" 2>"$root/err")
    local status=$?
    err=$(cat "$root/err")
    if [ "$status" -eq 0 ] && [ "$out" = "$want" ] && [ "$err" = "$want_err" ]; then
        ok "$name"
    else
        bad "$name: exit $status"
        printf '    stdout:\n%s\n    want:\n%s\n    stderr:\n%s\n    want stderr:\n%s\n' "$out" "$want" "$err" "$want_err"
    fi
}

check "nothing changed prints nothing" "" ""

sed -i '' -e '/aTestToDelete/d' -e 's/aTestToRename/aRenamedTest/' "$repo/Tests/Unit/TopLevelTests.swift"
check "an edit selects the test it touches; its untouched siblings and the test it deleted are not" \
"Tests/Unit/TopLevelTests.swift:4	aRenamedTest" ""

git -C "$repo" checkout -q -- Tests/Unit
sed -i '' '/aTestToDelete/d' "$repo/Tests/Unit/TopLevelTests.swift"
check "deleting a whole test selects nothing" "" ""

git -C "$repo" checkout -q -- Tests/Unit
sed -i '' '/let one = 1/d' "$repo/Tests/Unit/TopLevelTests.swift"
check "deleting a line inside a test selects that test" "Tests/Unit/TopLevelTests.swift:7	aMultiLineTest" ""

git -C "$repo" checkout -q -- Tests/Unit
sed -i '' 's/-> Int { 1 }/-> Int { 2 }/' "$repo/Tests/Unit/TopLevelTests.swift"
check "a change to a helper after a test selects nothing and says so on stderr" "" \
"note: Tests/Unit/TopLevelTests.swift changed outside its tests; the tests that use it are not repeated. Hunt them with scripts/flake-hunt.sh before you commit."

git -C "$repo" checkout -q -- Tests/Unit
sed -i '' -e 's/arguments: \[1, 2\]/arguments: [1, 2, 3]/' -e 's/func aHelperThatIsNoTest() {}/func aHelperThatIsNoTest() { _ = 1 }/' \
    "$repo/Tests/Unit/NestedTests.swift"
printf 'extension NestedTests {\n    @Test func aTestInAnExtension() { #expect(true) }\n}\n' >>"$repo/Tests/Unit/NestedTests.swift"
git -C "$repo" commit -qam "extend the nested tests"
check "a committed change selects by base name a multi-line @Test( whose arguments changed and a test in an extension" \
"Tests/Unit/NestedTests.swift:12	aTestInAnExtension
Tests/Unit/NestedTests.swift:8	aParametrizedTest" \
"note: Tests/Unit/NestedTests.swift changed outside its tests; the tests that use it are not repeated. Hunt them with scripts/flake-hunt.sh before you commit."

git -C "$repo" reset -q --hard "$base"
sed -i '' 's/@Suite("Display name")/@Suite("Renamed")/' "$repo/Tests/Unit/NestedTests.swift"
check "a change above a file's first test selects nothing and says so on stderr" "" \
"note: Tests/Unit/NestedTests.swift changed outside its tests; the tests that use it are not repeated. Hunt them with scripts/flake-hunt.sh before you commit."

git -C "$repo" reset -q --hard "$base"
printf 'import Testing\n@Test func aBrandNewTest() { #expect(true) }\n@Test func anotherBrandNewTest() { #expect(true) }\n' \
    >"$repo/Tests/Unit/BrandNewTests.swift"
mkdir -p "$repo/Tests/UI"
printf 'import Testing\n@Test func aUITest() { #expect(true) }\n' >"$repo/Tests/UI/SmokeTests.swift"
rm "$repo/Tests/Component/UntouchedTests.swift"
check "an untracked test file selects every test it declares, with no note; a deleted file and Tests/UI select nothing" \
"Tests/Unit/BrandNewTests.swift:2	aBrandNewTest
Tests/Unit/BrandNewTests.swift:3	anotherBrandNewTest" ""

git -C "$repo" checkout -q -- Tests/Component
rm -rf "$repo/Tests/Unit/BrandNewTests.swift" "$repo/Tests/UI"
echo 'extension HeldThing { func release() {} }' >>"$repo/Tests/Support/HeldThing.swift"
check "a changed Tests/Support file selects nothing and says so on stderr" "" \
"note: Tests/Support/HeldThing.swift changed and declares no test; the tests that use it are not repeated. Hunt them with scripts/flake-hunt.sh before you commit."

out=$(cd "$repo" && scripts/changed-tests.sh --base no-such-rev 2>&1)
status=$?
if [ "$status" -eq 2 ] && [ "$out" = "error: git cannot find where HEAD left 'no-such-rev'." ]; then
    ok "a base git cannot resolve exits 2 with the error line"
else
    bad "a base git cannot resolve exits 2 with the error line: exit $status"
    printf '    output:\n%s\n' "$out"
fi

printf '\npassed %s, failed %s\n' "$pass" "$fail"
[ "$fail" -eq 0 ] || exit 1
