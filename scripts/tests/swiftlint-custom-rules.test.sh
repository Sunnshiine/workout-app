#!/usr/bin/env bash
# Lint the fixture tree with the pinned SwiftLint and compare every custom-rule violation to the
# table below, so a rule edit that stops flagging a pinned shape, or starts flagging a pinned pass,
# fails here with the rule, file, and line.
#
#   scripts/tests/swiftlint-custom-rules.test.sh [CONFIG]
#
# CONFIG defaults to the repo's .swiftlint.yml. Pass a mutated copy to prove a case is load-bearing.
#
# The fixtures sit outside App/, Sources/, and Tests/ because those are compiled and linted at
# error. Each file is passed by path: SwiftLint lints a named file even outside root `included:`,
# while a named directory is filtered through it. A rule's own `included:` and `excluded:` regexes
# match the absolute path, so the fixture tree repeats the segments they scope on.
set -uo pipefail

script_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
repo=$(cd "$script_dir/../.." && pwd)
fixtures="$script_dir/swiftlint-custom-rules"

if [ "$#" -gt 1 ]; then
    echo "usage: scripts/tests/swiftlint-custom-rules.test.sh [CONFIG]" >&2
    exit 64
fi
config="${1:-$repo/.swiftlint.yml}"
if [ ! -f "$config" ]; then
    echo "error: no SwiftLint config at $config" >&2
    exit 64
fi

version=$("$repo/scripts/lint.sh" --print-version) || exit 3
swiftlint="${SWIFTLINT_CACHE_DIR:-$HOME/.cache/workout-swiftlint}/$version/SwiftLintBinary.artifactbundle/macos/swiftlint"
if [ ! -x "$swiftlint" ]; then
    echo "error: no SwiftLint $version at $swiftlint; run scripts/lint.sh once to fetch it." >&2
    exit 3
fi
reported=$("$swiftlint" version)
if [ "$reported" != "$version" ]; then
    echo "error: $swiftlint reports $reported but the project pins $version." >&2
    exit 3
fi
if ! command -v jq >/dev/null; then
    echo "error: jq is not on PATH." >&2
    exit 3
fi

work=$(mktemp -d) || exit 3
trap 'rm -rf "$work"' EXIT
pass=0
fail=0

ok()  { pass=$((pass + 1)); printf '  ok   %s\n' "$1"; }
bad() { fail=$((fail + 1)); printf '  FAIL %s\n' "$1"; }

# A row is "rule path:line". Every case is a function named for its outcome, so the nearest
# `func` at or above the line names the case a row lands in.
case_at() {
    local location=${1#* }
    sed -n "1,${location##*:}p" "$fixtures/${location%:*}" 2>/dev/null |
        grep -o 'func [A-Za-z_][A-Za-z0-9_]*' | tail -1 | cut -c6-
}
by_line() { LC_ALL=C sort -t: -k1,1 -k2,2n; }

rules="fixture_dates_are_literal
font_construction_via_theme
no_uppercase_microlabels
optional_bool_needs_a_nil_answer
platform_guard_on_test_declaration
polling_loops_are_bounded
unstructured_task_is_held"

expected_rows() {
    cat <<'EXPECTED'
font_construction_via_theme App/Views/FontConstructionViaTheme.swift:5
font_construction_via_theme App/Views/FontConstructionViaTheme.swift:9
font_construction_via_theme App/Views/FontConstructionViaTheme.swift:13
font_construction_via_theme App/Views/FontConstructionViaTheme.swift:17
font_construction_via_theme Sources/WorkoutTracker/FontConstructionViaTheme.swift:5

no_uppercase_microlabels App/Views/NoUppercaseMicrolabels.swift:5
no_uppercase_microlabels App/Views/NoUppercaseMicrolabels.swift:9

platform_guard_on_test_declaration Tests/PlatformGuardOnTestDeclaration.swift:5
platform_guard_on_test_declaration Tests/PlatformGuardOnTestDeclaration.swift:12
platform_guard_on_test_declaration Tests/PlatformGuardOnTestDeclaration.swift:19
platform_guard_on_test_declaration Tests/PlatformGuardOnTestDeclaration.swift:26
platform_guard_on_test_declaration Tests/PlatformGuardOnTestDeclaration.swift:32

unstructured_task_is_held App/UnstructuredTaskIsHeld.swift:6
unstructured_task_is_held App/UnstructuredTaskIsHeld.swift:12
unstructured_task_is_held App/UnstructuredTaskIsHeld.swift:18
unstructured_task_is_held Sources/WorkoutCLI/UnstructuredTaskIsHeld.swift:3
unstructured_task_is_held Tests/UnstructuredTaskIsHeld.swift:7

optional_bool_needs_a_nil_answer App/OptionalBoolNeedsANilAnswer.swift:3
optional_bool_needs_a_nil_answer App/OptionalBoolNeedsANilAnswer.swift:7
optional_bool_needs_a_nil_answer App/OptionalBoolNeedsANilAnswer.swift:11
optional_bool_needs_a_nil_answer App/OptionalBoolNeedsANilAnswer.swift:15
optional_bool_needs_a_nil_answer Sources/WorkoutTracker/OptionalBoolNeedsANilAnswer.swift:3

fixture_dates_are_literal Sources/WorkoutTracker/Fixtures/FixtureDatesAreLiteral.swift:5
fixture_dates_are_literal Tests/FixtureDatesAreLiteral.swift:5
fixture_dates_are_literal Tests/FixtureDatesAreLiteral.swift:9
fixture_dates_are_literal Tests/FixtureDatesAreLiteral.swift:13
fixture_dates_are_literal Tests/FixtureDatesAreLiteral.swift:17
fixture_dates_are_literal Tests/FixtureDatesAreLiteral.swift:21
fixture_dates_are_literal Tests/FixtureDatesAreLiteral.swift:25

polling_loops_are_bounded Tests/PollingLoopsAreBounded.swift:8
polling_loops_are_bounded Tests/PollingLoopsAreBounded.swift:14
polling_loops_are_bounded Tests/PollingLoopsAreBounded.swift:20
EXPECTED
}

configured=$(awk '/^custom_rules:/ { inside = 1; next }
                  inside && /^[^[:space:]#]/ { exit }
                  inside && /^  [A-Za-z_][A-Za-z0-9_]*:[[:space:]]*$/ { sub(/^  /, ""); sub(/:.*/, ""); print }' \
    "$config" | LC_ALL=C sort)
if [ -z "$configured" ]; then
    echo "error: $config has no custom_rules: entries to run." >&2
    exit 1
fi

echo "custom_rules: in $config names the rules this table covers"
if [ "$configured" = "$rules" ]; then
    ok "$(printf '%s\n' "$rules" | wc -l | tr -d ' ') rules"
else
    while IFS= read -r id; do
        [ -n "$id" ] && bad "custom_rules: has $id, which this table has no fixtures for"
    done < <(LC_ALL=C comm -13 <(printf '%s\n' "$rules") <(printf '%s\n' "$configured"))
    while IFS= read -r id; do
        [ -n "$id" ] && bad "custom_rules: has no $id, which this table pins"
    done < <(LC_ALL=C comm -23 <(printf '%s\n' "$rules") <(printf '%s\n' "$configured"))
fi

files=()
while IFS= read -r file; do
    files+=("$file")
done < <(find "$fixtures" -name '*.swift' | LC_ALL=C sort)
only=()
while IFS= read -r id; do
    only+=(--only-rule "$id")
done <<CONFIGURED
$configured
CONFIGURED

"$swiftlint" lint --no-cache --quiet --config "$config" --reporter json "${only[@]}" "${files[@]}" \
    >"$work/report.json" 2>"$work/stderr"
status=$?
if [ "$status" -ne 0 ] && [ "$status" -ne 2 ]; then
    echo "FAIL SwiftLint exited $status" >&2
    cat "$work/stderr" >&2
    exit 1
fi

if ! actual=$(jq -r --arg root "$fixtures/" '.[] | "\(.rule_id) \(.file | ltrimstr($root)):\(.line)"' \
    "$work/report.json" | LC_ALL=C sort); then
    echo "FAIL SwiftLint's JSON report did not parse" >&2
    exit 1
fi
expected=$(expected_rows | grep -v '^$' | LC_ALL=C sort)

echo "violations over ${#files[@]} fixture files"
while IFS= read -r row; do
    [ -n "$row" ] && ok "$row $(case_at "$row")"
done < <(LC_ALL=C comm -12 <(printf '%s\n' "$expected") <(printf '%s\n' "$actual") | by_line)
while IFS= read -r row; do
    [ -n "$row" ] && bad "missing $row $(case_at "$row")"
done < <(LC_ALL=C comm -23 <(printf '%s\n' "$expected") <(printf '%s\n' "$actual") | by_line)
while IFS= read -r row; do
    [ -n "$row" ] && bad "unexpected $row $(case_at "$row")"
done < <(LC_ALL=C comm -13 <(printf '%s\n' "$expected") <(printf '%s\n' "$actual") | by_line)

echo "every case named ...IsFlagged has an expected row, and every row lands in one"
named=$(cd "$fixtures" && grep -rno --include='*.swift' 'func [A-Za-z_][A-Za-z0-9_]*' . |
    sed -n 's|^\./\([^:]*\):[0-9]*:func \(.*IsFlagged\)$|\1 \2|p' | LC_ALL=C sort -u)
landed=$(printf '%s\n' "$expected" | while IFS= read -r row; do
    location=${row#* }
    echo "${location%:*} $(case_at "$row")"
done | LC_ALL=C sort -u)
if [ "$named" = "$landed" ]; then
    ok "$(printf '%s\n' "$named" | wc -l | tr -d ' ') flagged cases"
else
    while IFS= read -r name; do
        [ -n "$name" ] && bad "$name is named as flagged and has no expected row"
    done < <(LC_ALL=C comm -23 <(printf '%s\n' "$named") <(printf '%s\n' "$landed"))
    while IFS= read -r name; do
        [ -n "$name" ] && bad "an expected row lands in $name, which is not named ...IsFlagged"
    done < <(LC_ALL=C comm -13 <(printf '%s\n' "$named") <(printf '%s\n' "$landed"))
fi

echo "every rule has a flagged case in the table"
while IFS= read -r id; do
    count=$(printf '%s\n' "$expected" | grep -c "^$id ")
    if [ "$count" -gt 0 ]; then ok "$id: $count"; else bad "$id has no expected violation"; fi
done <<RULES
$rules
RULES

echo
echo "$pass passed, $fail failed"
[ "$fail" -eq 0 ]
