#!/usr/bin/env bash
set -uo pipefail

script_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
repo=$(cd "$script_dir/../.." && pwd)
table="$repo/scripts/rule-table.sh"

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

expect_text() {
    if printf '%s\n' "$2" | grep -Fq -- "$3"; then ok "$1 has $3"; else bad "$1 is missing the text: $3"; fi
}

expect_no_text() {
    if printf '%s\n' "$2" | grep -Fq -- "$3"; then bad "$1 has the text: $3"; else ok "$1 has no $3"; fi
}

run() {
    "$table" "$@" >"$root/stdout" 2>"$root/stderr"
    status=$?
    out=$(cat "$root/stdout")
    err=$(cat "$root/stderr")
}

fresh_fixture() {
    rm -rf "$fx"
    mkdir -p "$fx/scripts" "$fx/.github/workflows" "$fx/Tests/Unit"
    cat >"$fx/CODING_STANDARDS.md" <<'MD'
# Coding standards

## State

- **A derived fact with more than one owner.** A latch every method must set. (#586.) Enforced by:
  `DifferentialStateTests`, judgment.
- **A dropped `Task`,** held nowhere. Enforced by: `unstructured_task_is_held`,
  `scripts/lint-defaults.py`, and judgment.
- **A type that only forwards.** Enforced by: judgment.
MD
    cat >"$fx/.swiftlint.yml" <<'YAML'
custom_rules:
  unstructured_task_is_held:
    name: "Unstructured Tasks are held"
    regex: 'Task'
  no_uppercase_microlabels:
    name: "No uppercase microlabels"
    regex: 'x'
identifier_name:
  min_length: 1
YAML
    cat >"$fx/scripts/lint.sh" <<'SH'
echo "==> Defaulted parameters stay within the baseline"
python3 "$ROOT/scripts/lint-defaults.py" "$ROOT"

echo "==> Doc lines naming a file this branch split (advisory)"
python3 "$ROOT/scripts/doc-drift.py" origin/main || true
SH
    : >"$fx/scripts/lint-defaults.py"
    cat >"$fx/.github/workflows/ci.yml" <<'YAML'
jobs:
  lint:
    steps:
      - uses: actions/checkout@v4
      - name: Read the pinned SwiftLint version
        run: echo "version=$(scripts/lint.sh --print-version)"
      # scripts/commented.sh judges nothing.
      - name: Lint
        run: scripts/lint.sh
      - name: Refuse a landing that undoes a commit on the base
        run: |
          scripts/landing-reverts-main.py "$base" "$head"
      - name: Ensure the pinned baseline simulator exists
        run: scripts/sim-slim.sh "$udid" scripts/sim-ci-disabled-jobs.txt
      - name: Checker tests
        run: scripts/tests/lint.test.sh
      - name: Comment the mutants that survive
        continue-on-error: true
        run: scripts/mutate-advisory.sh --comment "$PR"
      - name: Refuse committed record mode
        with:
          paths:
            - App
        run: scripts/refuse-record-mode.sh
YAML
    printf '@Suite(.serialized) struct DifferentialStateTests {}\n' >"$fx/Tests/Unit/DifferentialStateTests.swift"
    printf '# Agents\n\n<!-- rule-table:start -->\n<!-- rule-table:end -->\n\nAfter.\n' >"$fx/AGENTS.md"
}

expected='| Rule | Enforced by |
|---|---|
| A derived fact with more than one owner | `DifferentialStateTests` (swift test), judgment |
| A dropped `Task` | `unstructured_task_is_held` (lint.sh), `scripts/lint-defaults.py` (lint.sh), judgment |
| A type that only forwards | judgment |
| No uppercase microlabels | `no_uppercase_microlabels` (lint.sh) |
| Doc lines naming a file this branch split | `scripts/doc-drift.py` (lint.sh, advisory) |
| Refuse a landing that undoes a commit on the base | `scripts/landing-reverts-main.py` (ci.yml) |
| Comment the mutants that survive | `scripts/mutate-advisory.sh` (ci.yml, advisory) |
| Refuse committed record mode | `scripts/refuse-record-mode.sh` (ci.yml) |'

echo "a tree whose every bullet names an enforcer"
fresh_fixture
run "$fx"
expect_exit "the print" "$status" 0
if [ "$out" = "$expected" ]; then ok "the table pairs each bullet and each unnamed check"; else
    bad "the table differs:"
    diff <(printf '%s\n' "$expected") <(printf '%s\n' "$out") | sed 's/^/         /'
fi
expect_no_text "a setup step" "$out" "sim-slim"
expect_no_text "a checker's own test" "$out" "scripts/tests/"
expect_no_text "a commented script" "$out" "commented.sh"

echo "a bullet with no enforcer"
fresh_fixture
printf -- '- **A new rule nobody checks,** added last.\n' >>"$fx/CODING_STANDARDS.md"
run "$fx"
expect_exit "the orphan" "$status" 1
expect_text "the orphan" "$err" "CODING_STANDARDS.md:10: the bullet \"A new rule nobody checks\" names no enforcer."
expect_text "the orphan" "$err" "\"Enforced by: judgment.\""
expect_no_text "the orphan" "$out" "| Rule |"

echo "a bullet that names an enforcer the tree lacks"
fresh_fixture
printf -- '- **A gone check.** Enforced by: `tests_never_sleep`.\n' >>"$fx/CODING_STANDARDS.md"
run "$fx"
expect_exit "the missing name" "$status" 1
expect_text "the missing name" "$err" "names \`tests_never_sleep\`, which is no custom SwiftLint rule, file, or test type in this tree."

echo "a bullet that names an enforcer without backticks"
fresh_fixture
printf -- '- **A loose name.** Enforced by: unstructured_task_is_held.\n' >>"$fx/CODING_STANDARDS.md"
run "$fx"
expect_exit "the bare name" "$status" 1
expect_text "the bare name" "$err" "\"unstructured_task_is_held\" in \"A loose name\" is neither a backticked name nor judgment."

echo "a bullet with no bold lead"
fresh_fixture
printf -- '- `unstructured_task_is_held` skips App/Views/.\n' >>"$fx/CODING_STANDARDS.md"
run "$fx"
expect_exit "the plain bullet" "$status" 1
expect_text "the plain bullet" "$err" "CODING_STANDARDS.md:10: this bullet has no bold lead."

echo "AGENTS.md's table against the tree"
fresh_fixture
run --check "$fx"
expect_exit "an empty block" "$status" 1
expect_text "an empty block" "$err" "Run scripts/rule-table.sh --write."
expect_text "an empty block" "$out" "+| A type that only forwards | judgment |"
run --write "$fx"
expect_exit "the write" "$status" 0
run --check "$fx"
expect_exit "the written block" "$status" 0
expect_text "the written block" "$out" "==> Clean: 8 rules, 7 with a check, 1 by judgment alone"
expect_text "the written block keeps the text around it" "$(cat "$fx/AGENTS.md")" "After."
printf -- '- **A later rule.** Enforced by: judgment.\n' >>"$fx/CODING_STANDARDS.md"
run --check "$fx"
expect_exit "a bullet added after the write" "$status" 1
expect_text "a bullet added after the write" "$out" "+| A later rule | judgment |"
printf '# Agents\n' >"$fx/AGENTS.md"
run --check "$fx"
expect_exit "an AGENTS.md with no block" "$status" 1
expect_text "an AGENTS.md with no block" "$err" "AGENTS.md has no <!-- rule-table:start --> ... <!-- rule-table:end --> block"

echo "usage"
run --nope
expect_exit "an unknown flag" "$status" 64
run "$root/empty"
expect_exit "a root with no CODING_STANDARDS.md" "$status" 64

echo "this repo"
run --check
expect_exit "AGENTS.md matches this tree's table" "$status" 0

echo
echo "$pass passed, $fail failed"
[ "$fail" -eq 0 ]
