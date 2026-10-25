#!/usr/bin/env bash
set -uo pipefail

script_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
checker="$script_dir/../lint-exemptions.py"

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

expect_text() {
    if printf '%s\n' "$2" | grep -Fq -- "$3"; then ok "$1 has $3"; else bad "$1 is missing the text: $3"; fi
}

mkdir -p "$root/bin" "$root/issues"
cat >"$root/bin/gh" <<'EOF'
#!/bin/bash
echo "$*" >>"$GH_CALLS"
if [ -n "${GH_STUB_UNAUTHENTICATED:-}" ]; then
    echo "To get started with GitHub CLI, please run:  gh auth login" >&2
    exit 4
fi
if [ -f "$GH_STUB_ISSUES/$3" ]; then
    cat "$GH_STUB_ISSUES/$3"
    exit 0
fi
echo "GraphQL: Could not resolve to an issue or pull request with the number of $3. (repository.issue)" >&2
exit 1
EOF
chmod +x "$root/bin/gh"
issue() {
    printf '{"state":"%s","labels":[%s],"url":"https://github.com/Sunnshiine/workout-app/%s/%s"}\n' \
        "$2" "$3" "${4:-issues}" "$1" >"$root/issues/$1"
}
issue 100 OPEN '{"name":"bug"}'
issue 101 CLOSED '{"name":"bug"}'
issue 102 CLOSED '{"name":"bug"},{"name":"wontfix"}'
issue 103 MERGED '' pull
export GH_CALLS="$root/gh-calls" GH_STUB_ISSUES="$root/issues" PATH="$root/bin:$PATH"

# Writes stdin to App/A.swift in a fresh repo and runs the check there.
check() {
    local repo="$root/repo"
    rm -rf "$repo" "$GH_CALLS"
    mkdir -p "$repo/App"
    cat >"$repo/App/A.swift"
    git -C "$repo" init -q
    "${@:-python3}" "$checker" "$repo" >"$root/stdout" 2>"$root/stderr"
    status=$?
    out=$(cat "$root/stdout")
    err=$(cat "$root/stderr")
}

echo "no citation"
check <<'SWIFT'
func start() {
    // swiftlint:disable:next unstructured_task_is_held
    Task { await work() }
}
SWIFT
expect_exit "an uncited unstructured_task_is_held exemption" "$status" 1
expect_line "it names the line" "$out" \
    "App/A.swift:2: the unstructured_task_is_held exemption cites no issue. That rule stops a bug, so its exemption accepts one. Cite the open issue that tracks it, or a wontfix one."
check <<'SWIFT'
    // Mirrors the production default.
    // swiftlint:disable:next fixture_dates_are_literal
    createdAt: Date = Date(),
SWIFT
expect_exit "an uncited fixture_dates_are_literal exemption" "$status" 1
check <<'SWIFT'
// swiftlint:disable:next all
let now = Date()
SWIFT
expect_exit "an uncited exemption of all" "$status" 1
check <<'SWIFT'
// swiftlint:disable force_try fixture_dates_are_literal
let now = Date()
// swiftlint:enable force_try fixture_dates_are_literal
SWIFT
expect_exit "an uncited block exemption naming a bug-shaped rule second" "$status" 1
expect_text "it names the line" "$out" "App/A.swift:1: the force_try fixture_dates_are_literal exemption cites no issue."
check <<'SWIFT'
// WCAG 1.4.3 exempts an inactive control from contrast.
// swiftlint:disable:next system_ink_outside_the_palette
let ink = Color.secondary
SWIFT
expect_exit "an uncited exemption of a rule that records a design fact" "$status" 0
expect_line "it reports the count" "$out" "1 exemptions cite 0 issues, and 0 fail"
if [ -e "$GH_CALLS" ]; then bad "a run with nothing cited calls gh"; else ok "a run with nothing cited makes no gh call"; fi
check <<'SWIFT'
/// Replaces #100's workaround.
// swiftlint:disable:next unstructured_task_is_held
Task { await work() }
SWIFT
expect_exit "a doc comment's citation above the exemption" "$status" 1
check <<'SWIFT'
// Tracked in #100,
// which explains the hold.

// swiftlint:disable:next unstructured_task_is_held
Task { await work() }
SWIFT
expect_exit "a citation above a blank line" "$status" 1

echo "an open issue"
check <<'SWIFT'
func start() {
    // Awaiting it would keep flushes apart (#100).
    // swiftlint:disable:next unstructured_task_is_held
    Task { await work() }
}
SWIFT
expect_exit "an exemption citing an open issue" "$status" 0
expect_line "it looks the issue up in the repo" "$(cat "$GH_CALLS")" \
    "issue view 100 --repo Sunnshiine/workout-app --json state,labels,url"
check <<'SWIFT'
    static func live(  // swiftlint:disable:this unstructured_task_is_held (#100)
SWIFT
expect_exit "a disable:this citing an open issue on its own line" "$status" 0

echo "a closed issue"
check <<'SWIFT'
// Awaiting it would reorder teardown (#101).
// swiftlint:disable:next unstructured_task_is_held
Task { await work() }
SWIFT
expect_exit "an exemption citing a closed issue without wontfix" "$status" 1
expect_line "it names the issue" "$out" \
    "App/A.swift:2: the exemption cites #101, which is closed without the wontfix label. Remove the exemption, reopen #101, or label it wontfix."
check <<'SWIFT'
// One parameter per column (#101).
// swiftlint:disable:next function_parameter_count
func make(a: Int, b: Int, c: Int, d: Int, e: Int, f: Int) {}
SWIFT
expect_exit "a design-fact exemption citing a closed issue" "$status" 1
check <<'SWIFT'
// Held on purpose (#999).
// swiftlint:disable:next unstructured_task_is_held
Task { await work() }
SWIFT
expect_exit "an exemption citing a number with no issue" "$status" 1
expect_text "it names the number" "$out" "App/A.swift:2: the exemption cites #999, which is no issue in Sunnshiine/workout-app."

echo "a wontfix issue"
check <<'SWIFT'
// Keeps the production default (#102, wontfix).
// swiftlint:disable:next fixture_dates_are_literal
createdAt: Date = Date(),
SWIFT
expect_exit "an exemption citing a closed wontfix issue" "$status" 0

echo "a pull request"
check <<'SWIFT'
// The hold landed in #103.
// swiftlint:disable:next unstructured_task_is_held
Task { await work() }
SWIFT
expect_exit "a bug-shaped exemption citing only a merged pull request" "$status" 1
expect_text "it says no issue is cited" "$out" "App/A.swift:2: the unstructured_task_is_held exemption cites no issue."
check <<'SWIFT'
// WCAG 1.4.3, settled in #103.
// swiftlint:disable:next system_ink_outside_the_palette
let ink = Color.secondary
SWIFT
expect_exit "a design-fact exemption citing a merged pull request" "$status" 0

echo "gh failing"
check env GH_STUB_UNAUTHENTICATED=1 python3 <<'SWIFT'
// Tracked in #100.
// swiftlint:disable:next unstructured_task_is_held
Task { await work() }
SWIFT
expect_exit "an unauthenticated gh" "$status" 2
expect_text "it passes gh's message on" "$err" "error: gh issue view 100 exited 4: To get started with GitHub CLI"
expect_text "it says it did not pass unchecked" "$err" "it fails rather than pass unchecked"
if [ -z "$out" ]; then ok "it prints no count"; else bad "it printed: $out"; fi
nogh="$root/nogh"
mkdir -p "$nogh"
ln -s "$(command -v git)" "$nogh/git"
ln -s "$(command -v python3)" "$nogh/python3"
check env PATH="$nogh" python3 <<'SWIFT'
// Tracked in #100.
// swiftlint:disable:next unstructured_task_is_held
Task { await work() }
SWIFT
expect_exit "a PATH with no gh" "$status" 2
expect_line "it says gh is missing" "$(head -1 "$root/stderr")" "error: gh is not on PATH"

echo
echo "$pass passed, $fail failed"
[ "$fail" -eq 0 ]
