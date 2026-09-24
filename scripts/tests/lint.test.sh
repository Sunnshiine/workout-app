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

expect_text() {
    if printf '%s\n' "$2" | grep -Fq -- "$3"; then ok "$1 has $3"; else bad "$1 is missing the text: $3"; fi
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

# Writes the baseline config. Each argument is one more `excluded:` entry.
baseline_config() {
    cat >"$fx/.swiftlint.yml" <<'YAML'
included:
  - App
  - Sources
  - Tests
excluded:
  - "**/Generated"
YAML
    for entry in "$@"; do printf '  - %s\n' "$entry" >>"$fx/.swiftlint.yml"; done
}

# Runs the fixture's lint.sh, or the path given, which reaches the same script another way.
run_lint() {
    "${1:-$fx/scripts/lint.sh}" >"$root/stdout" 2>"$root/stderr"
    status=$?
    out=$(cat "$root/stdout")
    err=$(cat "$root/stderr")
    both="$out"$'\n'"$err"
}

echo "baseline: every tree has a linted file"
fresh_fixture
baseline_config
run_lint
expect_exit "baseline" "$status" 0
expect_line "baseline" "$out" "==> Clean"

echo "widened: excluded covers the Tests root and the Sources/Tool tree"
fresh_fixture
baseline_config Tests Sources/Tool
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
expect_line "typo" "$err" "       SwiftLint would skip it and still exit 0, so the gate would lint less than it"
expect_line "typo" "$err" "       claims. Correct the path or drop the entry."
expect_no_text "typo" "$both" "==> Clean"

echo "miscased: included names tests, which git does not know, and excluded covers a tree inside it"
fresh_fixture
cat >"$fx/.swiftlint.yml" <<'YAML'
included:
  - App
  - Sources
  - tests
excluded:
  - "**/Generated"
  - tests/Unit
YAML
run_lint
expect_exit "miscased" "$status" 1
expect_line "miscased" "$err" "error: .swiftlint.yml 'included:' names 'tests', which holds no Swift file."
expect_no_text "miscased" "$both" "==> Clean"

echo "spelled: included roots written as ./App and Sources/ name the same trees"
fresh_fixture
cat >"$fx/.swiftlint.yml" <<'YAML'
included:
  - ./App
  - Sources/
  - Tests
excluded:
  - "**/Generated"
YAML
run_lint
expect_exit "spelled" "$status" 0
expect_line "spelled" "$out" "==> Clean"

echo "narrow: a Generated directory, a vendored directory, and a generated file inside a tree"
fresh_fixture
mkdir -p "$fx/Sources/Core/Generated" "$fx/Sources/Core/Vendor/Lib"
printf '%s\n' "$violation" >"$fx/Sources/Core/Generated/Table.swift"
printf '%s\n' "$violation" >"$fx/Sources/Core/Vendor/Lib/Lib.swift"
printf '%s\n' "$violation" >"$fx/Sources/Core/Strings.generated.swift"
baseline_config Sources/Core/Vendor Sources/Core/Strings.generated.swift
run_lint
expect_exit "narrow" "$status" 0
expect_line "narrow" "$out" "==> Clean"

echo "generated at the first level: a Generated directory directly inside a root is a tree"
fresh_fixture
mkdir -p "$fx/Tests/Generated"
printf 'let mock = 1\n' >"$fx/Tests/Generated/Mocks.swift"
git -C "$fx" add -A
baseline_config
run_lint
expect_exit "generated" "$status" 1
expect_line "generated" "$err" "error: 'Tests/Generated' holds Swift files, but SwiftLint linted none of them."
expect_no_text "generated" "$both" "==> Clean"

echo "moved: a tree renamed on disk without git mv is still linted where it now lives"
fresh_fixture
mv "$fx/Tests/Support" "$fx/Tests/Helpers"
baseline_config
run_lint
expect_exit "moved" "$status" 0
expect_line "moved" "$out" "==> Clean"

echo "untracked: a new tree git has not staged yet still counts"
fresh_fixture
mkdir -p "$fx/Sources/NewTool"
printf 'print(model)\n' >"$fx/Sources/NewTool/main.swift"
baseline_config Sources/NewTool
run_lint
expect_exit "untracked" "$status" 1
expect_line "untracked" "$err" "error: 'Sources/NewTool' holds Swift files, but SwiftLint linted none of them."
expect_no_text "untracked" "$both" "==> Clean"

echo "ignored: a Swift file under a git-ignored directory is not a tree"
fresh_fixture
mkdir -p "$fx/Sources/.build"
printf '.build/\n' >"$fx/.gitignore"
printf 'let cached = 1\n' >"$fx/Sources/.build/Cache.swift"
baseline_config '"**/.build"'
run_lint
expect_exit "ignored" "$status" 0
expect_line "ignored" "$out" "==> Clean"

echo "symlinked: the checkout is reached through a symlink"
fresh_fixture
baseline_config
ln -s "$fx" "$root/link"
run_lint "$root/link/scripts/lint.sh"
expect_exit "symlinked" "$status" 0
expect_line "symlinked" "$out" "==> Clean"

echo "no git: git cannot list the Swift files, so no tree can be checked"
fresh_fixture
rm -rf "$fx/.git"
baseline_config Sources/Tool
run_lint
expect_exit "no git" "$status" 128
expect_text "no git" "$err" "fatal: not a git repository"
expect_no_text "no git" "$both" "==> Clean"

echo "corrupt index: git finds the repo but cannot list its files"
fresh_fixture
printf 'junk' >"$fx/.git/index"
baseline_config Sources/Tool
run_lint
expect_exit "corrupt index" "$status" 128
expect_text "corrupt index" "$err" "index file smaller than expected"
expect_no_text "corrupt index" "$both" "==> Clean"

echo "violation: a linted tree breaks a rule while excluded: also covers a tree"
fresh_fixture
printf '%s\n' "$violation" >"$fx/Sources/Core/Bad.swift"
baseline_config Sources/Tool
run_lint
expect_exit "violation" "$status" 2
expect_text "violation" "$both" "$fx/Sources/Core/Bad.swift:1:5: error:"
expect_text "violation" "$both" "(identifier_name)"
expect_no_text "violation" "$both" "holds Swift files"
expect_no_text "violation" "$both" "==> Clean"

echo "concurrent: two runs at once in one checkout both pass"
fresh_fixture
baseline_config
for pair in 1 2 3; do
    "$fx/scripts/lint.sh" >"$root/first" 2>&1 &
    first=$!
    "$fx/scripts/lint.sh" >"$root/second" 2>&1 &
    second=$!
    wait "$first"
    expect_exit "concurrent pair $pair, first run" "$?" 0
    wait "$second"
    expect_exit "concurrent pair $pair, second run" "$?" 0
done

echo
echo "$pass passed, $fail failed"
[ "$fail" -eq 0 ]
