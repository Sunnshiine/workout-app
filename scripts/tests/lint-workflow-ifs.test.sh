#!/usr/bin/env bash
set -uo pipefail

script_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
checker="$script_dir/../lint-workflow-ifs.sh"

root=$(mktemp -d) || exit 3
trap 'rm -rf "$root"' EXIT
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

cat >"$root/bad.yml" <<'YAML'
name: Bad guards
on: push
jobs:
  unit:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - name: Visual gate
        id: visual
        run: exit 1
      - name: Hosted suite
        if: ${{ steps.visual.conclusion == 'success' || steps.visual.conclusion == 'failure' }}
        run: echo hosted
      - if: steps.visual.outcome == 'failure' # always() in a comment is not a status check
        name: Named after its guard
        run: echo report
      - id: folded
        if: >-
          github.event_name == 'push' &&
          steps.visual.conclusion != 'success'
        run: echo folded
      - if: |
          steps.visual.outcome != 'success'
        run: echo literal
  release-notes:
    runs-on: ubuntu-latest
    steps:
    - id: draft
      run: exit 1
    - name: Plain scalar over two lines
      if: github.event_name == 'push' &&
        steps.draft.outcome == 'failure'
      run: echo plain
YAML

cat >"$root/good.yml" <<'YAML'
name: Good guards
on: push
jobs:
  build:
    runs-on: ubuntu-latest
    steps:
      - id: visual
        run: exit 1
      - if: ${{ !cancelled() && (steps.visual.conclusion == 'success' || steps.visual.conclusion == 'failure') }}
        run: echo hosted
      - if: steps.visual.outputs.mode == 'run' && steps.visual.outcome == 'success' && (failure() || cancelled())
        run: echo cleanup
      - if: always() && steps.visual.outcome == 'failure'
        run: echo always
      - if: success() && steps.visual.conclusion == 'success'
        run: echo green
      - if: >-
          steps.visual.conclusion == 'failure' &&
          !cancelled()
        run: echo folded
      - if: steps.visual.outputs.changed == 'true'
        run: echo outputs
      - name: A script that prints the bad shape
        run: |
          cat <<'EOF'
          if: steps.visual.conclusion == 'failure'
          EOF
  report:
    if: github.ref == 'refs/heads/main'
    runs-on: ubuntu-latest
    steps:
      - run: echo report
YAML

echo "bad.yml: every step-result guard without a status check function is named"
out=$(cd "$root" && "$checker" bad.yml 2>&1)
status=$?
expect_exit "bad.yml" "$status" 1
expect_line "bad.yml" "$out" "bad.yml:12: job 'unit', step 'Hosted suite': if: reads a step conclusion or outcome and calls no status check function"
expect_line "bad.yml" "$out" "    \${{ steps.visual.conclusion == 'success' || steps.visual.conclusion == 'failure' }}"
expect_line "bad.yml" "$out" "bad.yml:14: job 'unit', step 'Named after its guard': if: reads a step conclusion or outcome and calls no status check function"
expect_line "bad.yml" "$out" "    steps.visual.outcome == 'failure'"
expect_line "bad.yml" "$out" "bad.yml:18: job 'unit', step 'folded': if: reads a step conclusion or outcome and calls no status check function"
expect_line "bad.yml" "$out" "    github.event_name == 'push' && steps.visual.conclusion != 'success'"
expect_line "bad.yml" "$out" "bad.yml:22: job 'unit', step '#6': if: reads a step conclusion or outcome and calls no status check function"
expect_line "bad.yml" "$out" "    steps.visual.outcome != 'success'"
expect_line "bad.yml" "$out" "bad.yml:31: job 'release-notes', step 'Plain scalar over two lines': if: reads a step conclusion or outcome and calls no status check function"
expect_line "bad.yml" "$out" "    github.event_name == 'push' && steps.draft.outcome == 'failure'"
count=$(printf '%s\n' "$out" | grep -c '^bad\.yml:[0-9]*: ')
if [ "$count" -eq 5 ]; then ok "bad.yml names 5 guards"; else bad "bad.yml names 5 guards, got $count"; fi

echo "good.yml: guards that call a status check function, and if: text inside a run script, pass"
out=$(cd "$root" && "$checker" good.yml 2>&1)
status=$?
expect_exit "good.yml" "$status" 0
expect_line "good.yml" "$out" "==> Clean: 7 if: conditions in 1 file(s)"

echo "a path that does not exist is a usage error, not a clean run"
out=$(cd "$root" && "$checker" missing.yml 2>&1)
status=$?
expect_exit "missing.yml" "$status" 2

echo
echo "$pass passed, $fail failed"
[ "$fail" -eq 0 ]
