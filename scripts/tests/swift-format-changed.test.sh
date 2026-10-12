#!/bin/bash
set -euo pipefail

script_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
subject="$script_dir/../swift-format-changed.sh"
config="$script_dir/../../.swift-format"
[ -x "$subject" ] || { echo "not executable: $subject" >&2; exit 2; }

root=$(mktemp -d)
trap 'rm -rf "$root"' EXIT
pass=0
fail=0

ok()  { pass=$((pass + 1)); printf '  ok   %s\n' "$1"; }
bad() { fail=$((fail + 1)); printf '  FAIL %s\n' "$1"; }

formatted=$'struct Plate {\n    var kilograms = 20\n}\n'
two_space=$'struct Plate {\n  var kilograms = 20\n}\n'

new_repo() {
    rm -rf "$root/repo"
    mkdir -p "$root/repo/Sources" "$root/repo/scripts/tests/swiftlint-custom-rules"
    cd "$root/repo"
    git init -q -b main
    git config user.email test@example.com
    git config user.name test
    cp "$config" .swift-format
    printf '%s' "$formatted" >Sources/Kept.swift
    printf '%s' "$two_space" >Sources/OldDebt.swift
    git add -A
    git commit -qm base
    git checkout -qb topic
}

run() {
    set +e
    "$subject" "$@" >"$root/out" 2>"$root/err"
    status=$?
    set -e
}

expect() {
    local name=$1 want_status=$2 want_text=$3
    if [ "$status" -eq "$want_status" ] && grep -qF -- "$want_text" "$root/out" "$root/err"; then
        ok "$name"
    else
        bad "$name"
        printf '       want exit %s and "%s"; got exit %s\n' "$want_status" "$want_text" "$status"
        sed 's/^/       out: /' "$root/out"
        sed 's/^/       err: /' "$root/err"
    fi
}

echo "only the files the branch changes"

new_repo
run main
expect "no changed Swift file exits 0, though main holds an unformatted one" 0 "No changed Swift file to check"

new_repo
printf '%s' "$two_space" >Sources/New.swift
git add -A && git commit -qm change
run main
expect "a committed unformatted file fails at its line" 1 "Sources/New.swift:2:"
expect "the failure names the command that fixes it" 1 "format them with: xcrun swift-format format -i Sources/New.swift"

new_repo
printf '%s\n// heavier\n' "$formatted" >Sources/Kept.swift
git add -A && git commit -qm change
run main
expect "a formatted change passes while untouched debt stays unreported" 0 "1 changed Swift file(s) clean"

new_repo
printf '%s' "$two_space" >Sources/Kept.swift
run main
expect "an uncommitted edit is checked" 1 "Sources/Kept.swift:2:"

new_repo
printf '%s' "$two_space" >Sources/Untracked.swift
run main
expect "an untracked new file is checked" 1 "Sources/Untracked.swift:2:"

new_repo
git rm -q Sources/OldDebt.swift && git commit -qm delete
run main
expect "a deleted file is not handed to swift-format" 0 "No changed Swift file to check"

new_repo
printf '%s' "$two_space" >scripts/tests/swiftlint-custom-rules/Fixture.swift
git add -A && git commit -qm fixture
run main
expect "a SwiftLint rule fixture is left unformatted on purpose" 0 "No changed Swift file to check"

echo "CI's form: the pull request merge commit against its first parent"

new_repo
printf '%s' "$two_space" >Sources/New.swift
git add -A && git commit -qm change
git checkout -q main
git merge -q --no-ff -m merge topic
run HEAD^1
expect "the merged side's unformatted file fails" 1 "Sources/New.swift:2:"

echo "--fix"

new_repo
printf '%s' "$two_space" >Sources/New.swift
git add -A && git commit -qm change
run --fix main
expect "--fix formats the changed file and passes" 0 "1 changed Swift file(s) clean"
if [ "$(cat Sources/New.swift)" = "$(printf '%s' "$formatted")" ]; then ok "--fix wrote four-space indentation"; else bad "--fix wrote: $(cat Sources/New.swift)"; fi
if [ "$(cat Sources/OldDebt.swift)" = "$(printf '%s' "$two_space")" ]; then ok "--fix left a file the branch did not change"; else bad "--fix rewrote Sources/OldDebt.swift"; fi

echo "arguments"

new_repo
run no-such-ref
expect "a base git cannot resolve exits 2" 2 "git cannot find where HEAD left 'no-such-ref'"
run --frobnicate
expect "an unknown flag exits 2 with the usage" 2 "scripts/swift-format-changed.sh [--fix] [<base>]"
run main topic
expect "two bases exit 2" 2 "scripts/swift-format-changed.sh [--fix] [<base>]"

printf '\npassed %s, failed %s\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
