#!/usr/bin/env bash
# Lint the fixture tree with the pinned SwiftLint and compare every custom-rule violation to the
# table below, so a rule edit that stops flagging a pinned shape, or starts flagging a pinned pass,
# fails here with the rule, file, and line.
#
#   scripts/tests/swiftlint-custom-rules.test.sh [CONFIG]
#
# CONFIG defaults to the repo's .swiftlint.yml. Pass a mutated copy to prove a case is load-bearing.
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

case_at() {
    local location=${1#* }
    awk -v at="${location##*:}" '
        function name() {
            match($0, /func [A-Za-z_][A-Za-z0-9_]*/)
            return substr($0, RSTART + 5, RLENGTH - 5)
        }
        NR < at && /func [A-Za-z_]/ { last = name() }
        NR == at && /^[ \t]*@/ && !/func [A-Za-z_]/ { below = 1; next }
        NR == at { if (/func [A-Za-z_]/) last = name(); print last; exit }
        below && /func [A-Za-z_]/ { print name(); exit }
    ' "$fixtures/${location%:*}" 2>/dev/null
}
by_line() { LC_ALL=C sort -t: -k1,1 -k2,2n; }

expected_rows() {
    cat <<'EXPECTED'
font_construction_via_theme App/Views/FontConstructionViaTheme.swift:5
font_construction_via_theme App/Views/FontConstructionViaTheme.swift:9
font_construction_via_theme App/Views/FontConstructionViaTheme.swift:14
font_construction_via_theme App/Views/FontConstructionViaTheme.swift:15
font_construction_via_theme App/Views/FontConstructionViaTheme.swift:16
font_construction_via_theme App/Views/FontConstructionViaTheme.swift:17
font_construction_via_theme App/Views/FontConstructionViaTheme.swift:18
font_construction_via_theme App/Views/FontConstructionViaTheme.swift:19
font_construction_via_theme App/Views/FontConstructionViaTheme.swift:20
font_construction_via_theme App/Views/FontConstructionViaTheme.swift:21
font_construction_via_theme App/Views/FontConstructionViaTheme.swift:22
font_construction_via_theme App/Views/FontConstructionViaTheme.swift:23
font_construction_via_theme App/Views/FontConstructionViaTheme.swift:24
font_construction_via_theme App/Views/FontConstructionViaTheme.swift:29
font_construction_via_theme Sources/WorkoutTracker/FontConstructionViaTheme.swift:5

no_uppercase_microlabels App/Views/NoUppercaseMicrolabels.swift:5
no_uppercase_microlabels App/Views/NoUppercaseMicrolabels.swift:9

platform_guard_on_test_declaration Tests/PlatformGuardOnTestDeclaration.swift:5
platform_guard_on_test_declaration Tests/PlatformGuardOnTestDeclaration.swift:12
platform_guard_on_test_declaration Tests/PlatformGuardOnTestDeclaration.swift:19
platform_guard_on_test_declaration Tests/PlatformGuardOnTestDeclaration.swift:26
platform_guard_on_test_declaration Tests/PlatformGuardOnTestDeclaration.swift:32
platform_guard_on_test_declaration Tests/PlatformGuardOnTestDeclaration.swift:41
platform_guard_on_test_declaration Tests/PlatformGuardOnTestDeclaration.swift:48
platform_guard_on_test_declaration Tests/PlatformGuardOnTestDeclaration.swift:55
platform_guard_on_test_declaration Tests/PlatformGuardOnTestDeclaration.swift:62

unstructured_task_is_held App/UnstructuredTaskIsHeld.swift:6
unstructured_task_is_held App/UnstructuredTaskIsHeld.swift:12
unstructured_task_is_held App/UnstructuredTaskIsHeld.swift:18
unstructured_task_is_held App/UnstructuredTaskIsHeld.swift:24
unstructured_task_is_held App/UnstructuredTaskIsHeld.swift:31
unstructured_task_is_held Sources/WorkoutCLI/UnstructuredTaskIsHeld.swift:3
unstructured_task_is_held Tests/UnstructuredTaskIsHeld.swift:7
unstructured_task_is_held WorkoutShared/UnstructuredTaskIsHeld.swift:3
unstructured_task_is_held WorkoutWidgets/UnstructuredTaskIsHeld.swift:3

optional_bool_needs_a_nil_answer App/OptionalBoolNeedsANilAnswer.swift:3
optional_bool_needs_a_nil_answer App/OptionalBoolNeedsANilAnswer.swift:7
optional_bool_needs_a_nil_answer App/OptionalBoolNeedsANilAnswer.swift:11
optional_bool_needs_a_nil_answer App/OptionalBoolNeedsANilAnswer.swift:15
optional_bool_needs_a_nil_answer App/OptionalBoolNeedsANilAnswer.swift:19
optional_bool_needs_a_nil_answer App/OptionalBoolNeedsANilAnswer.swift:23
optional_bool_needs_a_nil_answer App/OptionalBoolNeedsANilAnswer.swift:27
optional_bool_needs_a_nil_answer App/OptionalBoolNeedsANilAnswer.swift:43
optional_bool_needs_a_nil_answer App/OptionalBoolNeedsANilAnswer.swift:47
optional_bool_needs_a_nil_answer Sources/WorkoutTracker/OptionalBoolNeedsANilAnswer.swift:3
optional_bool_needs_a_nil_answer WorkoutShared/OptionalBoolNeedsANilAnswer.swift:3
optional_bool_needs_a_nil_answer WorkoutWidgets/OptionalBoolNeedsANilAnswer.swift:3

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
polling_loops_are_bounded Tests/PollingLoopsAreBounded.swift:24
EXPECTED
}
expected=$(expected_rows | grep -v '^$' | LC_ALL=C sort)
covered=$(printf '%s\n' "$expected" | cut -d' ' -f1 | LC_ALL=C sort -u)

configured=$(awk -v config="$config" -v q="'" '
    BEGIN {
        id = "[A-Za-z_][A-Za-z0-9_]*"
        key = "^  (\"" id "\"|" q id q "|" id "):[[:space:]]*(#.*)?$"
    }
    /^custom_rules:/ { inside = 1; next }
    !inside { next }
    /^[^[:space:]#]/ { exit }
    /^  [^[:space:]#]/ {
        if ($0 !~ key) {
            printf "error: line %d of %s is indented as a custom_rules: key but is not one:\n%s\n", NR, config, $0 > "/dev/stderr"
            exit 1
        }
        sub(/^  /, ""); sub(/:.*/, ""); gsub(/["'\'']/, "")
        print
    }' "$config" | LC_ALL=C sort) || exit 1
if [ -z "$configured" ]; then
    echo "error: $config has no custom_rules: entries to run." >&2
    exit 1
fi

echo "custom_rules: in $config names the rules this table covers"
if [ "$configured" = "$covered" ]; then
    ok "$(printf '%s\n' "$covered" | wc -l | tr -d ' ') rules"
else
    while IFS= read -r id; do
        [ -n "$id" ] && bad "custom_rules: has $id, which this table has no fixtures for"
    done < <(LC_ALL=C comm -13 <(printf '%s\n' "$covered") <(printf '%s\n' "$configured"))
    while IFS= read -r id; do
        [ -n "$id" ] && bad "custom_rules: has no $id, which this table pins"
    done < <(LC_ALL=C comm -23 <(printf '%s\n' "$covered") <(printf '%s\n' "$configured"))
fi

mirror="$work/mirror"
cp -R "$fixtures" "$mirror" &&
    cp "$config" "$mirror/.swiftlint.yml" &&
    cp "$repo/Tests/.swiftlint.yml" "$mirror/Tests/.swiftlint.yml" || exit 3
# SwiftLint reports a standardized path, which drops the /private that pwd -P puts on a /var dir.
root=$(cd "$mirror" && pwd -P) || exit 3
root=${root#/private}

# No --strict, which would report a warning as an error and hide the severity checked below.
(cd "$mirror" && "$swiftlint" lint --no-cache --quiet --reporter json) \
    >"$work/report.json" 2>"$work/stderr"
status=$?

echo "SwiftLint over the mirrored tree writes nothing to stderr"
if [ -s "$work/stderr" ]; then
    bad "SwiftLint exited $status and wrote to stderr:"
    sed 's/^/         /' "$work/stderr"
else
    ok "stderr is empty"
fi
if [ "$status" -ne 0 ] && [ "$status" -ne 2 ]; then
    echo "FAIL SwiftLint exited $status" >&2
    exit 1
fi

if ! kept=$(jq -r --arg ids "$configured" --arg root "$root/" '
    ($ids | split("\n")) as $ids
    | .[] | select(.rule_id | IN($ids[]))
    | "\(.rule_id) \(.file | ltrimstr($root)):\(.line) \(.severity)"' "$work/report.json"); then
    echo "FAIL SwiftLint's JSON report did not parse" >&2
    exit 1
fi
actual=$(printf '%s\n' "$kept" | cut -d' ' -f1,2 | grep -v '^$' | LC_ALL=C sort)

echo "every custom-rule violation reports severity Error"
off=$(printf '%s\n' "$kept" | awk 'NF && $3 != "Error"' | by_line)
if [ -z "$off" ]; then
    ok "$(printf '%s\n' "$actual" | grep -c .) violations at Error"
else
    while IFS=' ' read -r id location severity; do
        bad "$id $location reports severity $severity"
    done <<OFF
$off
OFF
fi

echo "violations over $(find "$fixtures" -name '*.swift' | wc -l | tr -d ' ') fixture files"
while IFS= read -r row; do
    [ -n "$row" ] && ok "$row $(case_at "$row")"
done < <(LC_ALL=C comm -12 <(printf '%s\n' "$expected") <(printf '%s\n' "$actual") | by_line)
while IFS= read -r row; do
    [ -n "$row" ] && bad "missing $row $(case_at "$row")"
done < <(LC_ALL=C comm -23 <(printf '%s\n' "$expected") <(printf '%s\n' "$actual") | by_line)
while IFS= read -r row; do
    [ -n "$row" ] && bad "unexpected $row $(case_at "$row")"
done < <(LC_ALL=C comm -13 <(printf '%s\n' "$expected") <(printf '%s\n' "$actual") | by_line)

cases=$(cd "$fixtures" && grep -rno --include='*.swift' 'func [A-Za-z_][A-Za-z0-9_]*' . |
    sed 's|^\./\([^:]*\):[0-9]*:func |\1 |' | LC_ALL=C sort -u)

echo "every case ends in IsFlagged, IsFalselyFlagged, Passes, or IsMissed"
unnamed=$(printf '%s\n' "$cases" | grep -vE ' [A-Za-z0-9_]*(IsFlagged|IsFalselyFlagged|Passes|IsMissed)$')
if [ -z "$unnamed" ]; then
    ok "$(printf '%s\n' "$cases" | grep -c .) cases"
else
    while IFS= read -r name; do
        bad "$name ends in none of the four outcomes"
    done <<UNNAMED
$unnamed
UNNAMED
fi

echo "every case named ...Flagged has an expected row, and every row lands in one"
named=$(printf '%s\n' "$cases" | grep 'Flagged$')
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
        [ -n "$name" ] && bad "an expected row lands in $name, which is not named ...Flagged"
    done < <(LC_ALL=C comm -13 <(printf '%s\n' "$named") <(printf '%s\n' "$landed"))
fi

echo
echo "$pass passed, $fail failed"
[ "$fail" -eq 0 ]
