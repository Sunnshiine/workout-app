#!/bin/bash
set -uo pipefail

script_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
source_script="$script_dir/../rerecord-snapshots"
[ -x "$source_script" ] || { echo "not executable: $source_script" >&2; exit 2; }

root=$(mktemp -d) || exit 3
trap 'rm -rf "$root"' EXIT
pass=0
fail=0

ok()  { pass=$((pass + 1)); printf '  ok   %s\n' "$1"; }
bad() { fail=$((fail + 1)); printf '  FAIL %s\n' "$1"; }

mkdir -p "$root/bin" "$root/stub"
export STUB_DIR=$root/stub
export PATH="$root/bin:$PATH"
export RERECORD_POLL_SECONDS=0

cat >"$root/bin/gh" <<'STUB'
#!/bin/bash
set -euo pipefail
printf '%s\n' "$*" >>"$STUB_DIR/calls.log"
case "$1 $2" in
    "workflow run")
        [ "$3 $4 $5" = "ci.yml --ref topic" ] || { echo "gh stub: unexpected dispatch $*" >&2; exit 1; }
        echo 42 >"$STUB_DIR/dispatched" ;;
    "run list")
        case "$*" in *"--branch topic --event workflow_dispatch --commit $STUB_SHA "*) ;;
            *) echo "gh stub: unexpected filters $*" >&2; exit 1 ;;
        esac
        cat "$STUB_DIR/dispatched" 2>/dev/null || echo 0 ;;
    "run view")
        [ "$3" = 42 ] || { echo "gh stub: no run $3" >&2; exit 1; }
        echo "completed $STUB_CONCLUSION" ;;
    *) echo "gh stub: unexpected command: $*" >&2; exit 1 ;;
esac
STUB
chmod +x "$root/bin/gh"

git init -q --bare "$root/origin.git"
git clone -q "$root/origin.git" "$root/repo" 2>/dev/null
cd "$root/repo" || exit 3
git config user.email test@example.com
git config user.name test
git checkout -q -b topic
mkdir -p scripts Tests/Visual/__Snapshots__/SuiteTests
cp "$source_script" scripts/rerecord-snapshots
cat >scripts/ci-visual-diffs.sh <<'STUB'
#!/bin/bash
set -euo pipefail
[ "$*" = 42 ] || { echo "ci-visual-diffs stub: unexpected $*" >&2; exit 2; }
[ "${STUB_DIFFS_EXIT:-0}" = 0 ] || exit "$STUB_DIFFS_EXIT"
dir=.build/ci-visual-diffs/42
mkdir -p "$dir/snapshots/SuiteTests"
: >"$dir/other-failures.txt"
[ -z "${STUB_OTHER:-}" ] || echo "SuiteTests/crashes()	boom" >"$dir/other-failures.txt"
for name in ${STUB_FAILING:-}; do
    echo "runner $name" >"$dir/snapshots/SuiteTests/$name"
    printf 'SuiteTests/%s\t%s\t%s\n' "$name" "$PWD/$dir/snapshots/SuiteTests/$name" "$PWD/$dir/diff.png"
done
STUB
chmod +x scripts/ci-visual-diffs.sh
for name in day.1.png night.1.png same.1.png; do echo "trunk $name" >"Tests/Visual/__Snapshots__/SuiteTests/$name"; done
git add -A
git commit -q -m base
git push -q origin topic 2>/dev/null
export STUB_SHA
STUB_SHA=$(git rev-parse HEAD)

run() {
    rm -f "$STUB_DIR/dispatched" "$STUB_DIR/calls.log"
    git checkout -q -- Tests
    rm -rf .build
    out=$(scripts/rerecord-snapshots "$@" 2>"$root/err") && code=0 || code=$?
}
baseline() { cat "Tests/Visual/__Snapshots__/SuiteTests/$1"; }

STUB_CONCLUSION=success run
if [ "$code" = 0 ] && [ -z "$out" ] && grep -q "every baseline matches the runner" "$root/err" \
    && grep -q "^workflow run ci.yml --ref topic" "$STUB_DIR/calls.log"; then
    ok "a green visual-tests dispatch writes nothing and exits 0"
else
    bad "green run: exit $code, out '$out', err '$(cat "$root/err")'"
fi

STUB_CONCLUSION=failure STUB_FAILING="day.1.png night.1.png" run
if [ "$code" = 0 ] && [ "$(baseline day.1.png)" = "runner day.1.png" ] \
    && [ "$(baseline night.1.png)" = "runner night.1.png" ] && [ "$(baseline same.1.png)" = "trunk same.1.png" ] \
    && [ "$(echo "$out" | wc -l | tr -d ' ')" = 2 ]; then
    ok "with no names, every failing baseline takes the runner's render"
else
    bad "no names: exit $code, out '$out', err '$(cat "$root/err")'"
fi

STUB_CONCLUSION=failure STUB_FAILING="day.1.png night.1.png" \
    run Tests/Visual/__Snapshots__/SuiteTests/day.1.png SuiteTests/same.1.png
if [ "$code" = 0 ] && [ "$out" = "Tests/Visual/__Snapshots__/SuiteTests/day.1.png" ] \
    && [ "$(baseline night.1.png)" = "trunk night.1.png" ] && [ "$(baseline same.1.png)" = "trunk same.1.png" ] \
    && grep -q "same.1.png already matches the runner" "$root/err"; then
    ok "named baselines: a failing one is written, a matching one is left, an unnamed one is untouched"
else
    bad "named: exit $code, out '$out', err '$(cat "$root/err")'"
fi

STUB_CONCLUSION=failure STUB_FAILING="day.1.png" run day.1.png SuiteTests/missing.1.png
if [ "$code" = 2 ] && [ -z "$out" ] && [ "$(baseline day.1.png)" = "trunk day.1.png" ]; then
    ok "a name that is neither a baseline nor failing writes nothing and exits 2"
else
    bad "unknown name: exit $code, out '$out', err '$(cat "$root/err")'"
fi

STUB_CONCLUSION=failure STUB_DIFFS_EXIT=3 run
if [ "$code" = 1 ] && grep -q "before comparing baselines" "$root/err"; then
    ok "a visual-tests failure with no baseline diffs exits 1"
else
    bad "no diffs: exit $code, err '$(cat "$root/err")'"
fi

STUB_CONCLUSION=failure STUB_FAILING="day.1.png" STUB_OTHER=1 run
if [ "$code" = 1 ] && [ "$(baseline day.1.png)" = "runner day.1.png" ] && grep -q "not baseline mismatches" "$root/err"; then
    ok "a failure that is not a mismatch exits 1 after writing the baselines"
else
    bad "other failure: exit $code, err '$(cat "$root/err")'"
fi

STUB_CONCLUSION=cancelled run
if [ "$code" = 1 ] && grep -q "ended cancelled" "$root/err"; then
    ok "a cancelled visual-tests job exits 1"
else
    bad "cancelled: exit $code, err '$(cat "$root/err")'"
fi

echo dirty >>Tests/Visual/__Snapshots__/SuiteTests/day.1.png
out=$(scripts/rerecord-snapshots 2>"$root/err") && code=0 || code=$?
if [ "$code" = 2 ] && grep -q "commit and push first" "$root/err"; then
    ok "a dirty tree dispatches nothing and exits 2"
else
    bad "dirty: exit $code, err '$(cat "$root/err")'"
fi

git checkout -q -- Tests

git commit -q --allow-empty -m unpushed
STUB_CONCLUSION=success run
if [ "$code" = 2 ] && [ ! -e "$STUB_DIR/calls.log" ] && grep -q "push HEAD first" "$root/err"; then
    ok "an unpushed HEAD dispatches nothing and exits 2"
else
    bad "unpushed: exit $code, err '$(cat "$root/err")'"
fi

echo "rerecord-snapshots: $pass passed, $fail failed"
[ "$fail" -eq 0 ]
