#!/usr/bin/env bash
# Tests scripts/lint.sh over a fixture repo. An optional argument names another lint.sh to test.
set -uo pipefail

script_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
repo=$(cd "$script_dir/../.." && pwd)
lint=${1:-$repo/scripts/lint.sh}
resolved="WorkoutTracker.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved"
violation='let x = 1'

root=$(mktemp -d) || exit 3
trap 'rm -rf "$root"' EXIT
fx="$root/fx"
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
    if printf '%s\n' "$2" | grep -Fq -- "$3"; then bad "$1 has the text: $3"; else ok "$1 has no $3"; fi
}

fresh_fixture() {
    rm -rf "$fx"
    mkdir -p "$fx/scripts" "$fx/$(dirname "$resolved")" \
        "$fx/App/Views" "$fx/Sources/Core" "$fx/Sources/Tool" "$fx/Tests/Unit" "$fx/Tests/Support"
    cp "$lint" "$fx/scripts/lint.sh"
    cp "$repo/$resolved" "$fx/$resolved"
    printf 'disabled_rules:\n  - force_unwrapping\n' >"$fx/Tests/.swiftlint.yml"
    printf 'let appRoot = 1\n' >"$fx/App/Root.swift"
    printf 'let screen = 1\n' >"$fx/App/Views/Screen.swift"
    printf 'let model = 1\n' >"$fx/Sources/Core/Model.swift"
    printf 'print(model)\n' >"$fx/Sources/Tool/main.swift"
    printf 'let modelTest = model\n' >"$fx/Tests/Unit/ModelTests.swift"
    printf 'let helper = 1\n' >"$fx/Tests/Support/Helper.swift"
    git -C "$fx" init -q
    git -C "$fx" add -A
}

run_lint() {
    "$fx/scripts/lint.sh" >"$root/stdout" 2>"$root/stderr"
    status=$?
    out=$(cat "$root/stdout")
    err=$(cat "$root/stderr")
    both="$out"$'\n'"$err"
}

echo "baseline: every tree has a linted file"
fresh_fixture
cat >"$fx/.swiftlint.yml" <<'YAML'
included:
  - App
  - Sources
  - Tests
excluded:
  - "**/Generated"
YAML
run_lint
expect_exit "baseline" "$status" 0
expect_line "baseline" "$out" "==> Clean"

echo "widened: excluded covers the Tests root and the Sources/Tool tree"
fresh_fixture
cat >"$fx/.swiftlint.yml" <<'YAML'
included:
  - App
  - Sources
  - Tests
excluded:
  - "**/Generated"
  - Tests
  - Sources/Tool
YAML
run_lint
expect_exit "widened" "$status" 1
expect_line "widened" "$err" "error: 'Tests' holds Swift files, but SwiftLint linted none of them."
expect_line "widened" "$err" "error: 'Sources/Tool' holds Swift files, but SwiftLint linted none of them."
expect_no_text "widened" "$err" "'Tests/Unit'"
expect_no_text "widened" "$err" "'Tests/Support'"
expect_no_text "widened" "$both" "==> Clean"

echo "typo: included names Tset, which holds no Swift file"
fresh_fixture
cat >"$fx/.swiftlint.yml" <<'YAML'
included:
  - App
  - Sources
  - Tset
excluded:
  - "**/Generated"
YAML
run_lint
expect_exit "typo" "$status" 1
expect_line "typo" "$err" "error: .swiftlint.yml 'included:' names 'Tset', which holds no Swift file."
expect_no_text "typo" "$both" "==> Clean"

echo "narrow: a Generated directory, a vendored directory, and a generated file inside a tree"
fresh_fixture
mkdir -p "$fx/Sources/Core/Generated" "$fx/Sources/Core/Vendor/Lib"
printf '%s\n' "$violation" >"$fx/Sources/Core/Generated/Table.swift"
printf '%s\n' "$violation" >"$fx/Sources/Core/Vendor/Lib/Lib.swift"
printf '%s\n' "$violation" >"$fx/Sources/Core/Strings.generated.swift"
cat >"$fx/.swiftlint.yml" <<'YAML'
included:
  - App
  - Sources
  - Tests
excluded:
  - "**/Generated"
  - Sources/Core/Vendor
  - Sources/Core/Strings.generated.swift
YAML
run_lint
expect_exit "narrow" "$status" 0
expect_line "narrow" "$out" "==> Clean"

echo "moved: a tree renamed on disk without git mv is still linted where it now lives"
fresh_fixture
mv "$fx/Tests/Support" "$fx/Tests/Helpers"
cat >"$fx/.swiftlint.yml" <<'YAML'
included:
  - App
  - Sources
  - Tests
excluded:
  - "**/Generated"
YAML
run_lint
expect_exit "moved" "$status" 0
expect_line "moved" "$out" "==> Clean"

echo "violation: a linted tree holds a file that breaks a rule"
fresh_fixture
printf '%s\n' "$violation" >"$fx/Sources/Core/Bad.swift"
cat >"$fx/.swiftlint.yml" <<'YAML'
included:
  - App
  - Sources
  - Tests
excluded:
  - "**/Generated"
YAML
run_lint
expect_exit "violation" "$status" 2
expect_line "violation" "$both" "$fx/Sources/Core/Bad.swift:1:5: error: Identifier Name Violation: Variable name 'x' should be between 3 and 40 characters long (identifier_name)"
expect_no_text "violation" "$both" "==> Clean"

echo
echo "$pass passed, $fail failed"
[ "$fail" -eq 0 ]
