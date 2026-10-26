#!/bin/bash
set -uo pipefail

script=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/keyboard-lane-paths.sh
root=$(mktemp -d) || exit 3
trap 'rm -rf "$root"' EXIT
repo=$root/repo
err=$root/err
mkdir "$repo"
pass=0
fail=0

ok()  { pass=$((pass + 1)); printf '  ok   %s\n' "$1"; }
bad() { fail=$((fail + 1)); printf '  FAIL %s\n' "$1"; }

git -C "$repo" init -q -b main
git -C "$repo" config user.email test@example.com
git -C "$repo" config user.name test
git -C "$repo" config commit.gpgsign false
git -C "$repo" commit -q --allow-empty -m base

# Commits one change to $1 on a fresh branch from the base and prints the script's stdout, stderr,
# and exit status.
run_for() {
    git -C "$repo" checkout -q main
    git -C "$repo" checkout -q -B "case-$RANDOM"
    mkdir -p "$repo/$(dirname "$1")"
    echo change > "$repo/$1"
    git -C "$repo" add -A && git -C "$repo" commit -qm change
    (cd "$repo" && "$script" main 2>"$err"; echo "exit=$?")
}

expect() {
    local path=$1 want=$2 out
    out=$(run_for "$path")
    if [ "$out" = "$(printf 'run=%s\nexit=0' "$want")" ]; then
        ok "$path gives run=$want"
    else
        bad "$path gives run=$want, got: $out $(cat "$err")"
    fi
}

expect App/Views/SessionStageView.swift true
expect App/Views/SessionQueueSheet.swift true
expect App/Views/SmartValuePills.swift true
expect App/Views/ActiveSetCard.swift true
expect Tests/UI/KeyboardLaneUITests.swift true
expect Sources/WorkoutTracker/Session/SessionCoordinator.swift false
expect App/Views/SettingsView.swift false
expect Tests/Unit/SessionStageViewTests.swift false

run_for App/Views/SessionView.swift > /dev/null
if grep -qx '  App/Views/SessionView.swift' "$err"; then
    ok "stderr names the matched path"
else
    bad "stderr names the matched path, got: $(cat "$err")"
fi

out=$(cd "$repo" && "$script" no-such-base 2>/dev/null; echo "exit=$?")
case $out in
    exit=0 | run=*) bad "a base git cannot read fails, got: $out" ;;
    *) ok "a base git cannot read fails ($out)" ;;
esac

out=$("$script" 2>/dev/null; echo "exit=$?")
if [ "$out" = exit=2 ]; then ok "no base exits 2"; else bad "no base exits 2, got: $out"; fi

printf '%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" = 0 ]
