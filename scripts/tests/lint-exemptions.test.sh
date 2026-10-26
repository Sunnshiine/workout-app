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

expect_no_text() {
    if printf '%s\n' "$2" | grep -Fq -- "$3"; then bad "$1 has the text: $3"; else ok "$1 lacks $3"; fi
}

expect_no_gh() {
    if [ -e "$GH_CALLS" ]; then bad "$1 calls gh: $(cat "$GH_CALLS")"; else ok "$1 makes no gh call"; fi
}

mkdir -p "$root/bin" "$root/issues"
cat >"$root/bin/gh" <<'EOF'
#!/bin/bash
echo "$*" >>"$GH_CALLS"
case "${GH_STUB:-}" in
unauthenticated)
    echo "To get started with GitHub CLI, please run:  gh auth login" >&2
    exit 4 ;;
bad-token)
    printf 'HTTP 401: Bad credentials (https://api.github.com/graphql)\nTry authenticating with:  gh auth login -h github.com\n' >&2
    exit 1 ;;
actions-no-token)
    printf 'gh: To use GitHub CLI in a GitHub Actions workflow, set the GH_TOKEN environment variable. Example:\n  env:\n    GH_TOKEN: ${{ github.token }}\n' >&2
    exit 4 ;;
offline)
    printf 'error connecting to api.github.com\ncheck your internet connection or https://githubstatus.com\n' >&2
    exit 1 ;;
slow)
    exec sleep 10 ;;
esac
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
    "App/A.swift:2: the unstructured_task_is_held exemption cites no issue. That rule stops a bug, so its exemption accepts one. Cite the open or wontfix issue that tracks it as a bare #N, N of two to five digits with no leading zero, on the directive or the comment lines directly above it. An owner/repo#N or a URL does not count."
check <<'SWIFT'
    // Mirrors the production default.
    // swiftlint:disable:next fixture_dates_are_literal
    createdAt: Date = Date(),
SWIFT
expect_exit "an uncited fixture_dates_are_literal exemption" "$status" 1
check <<'SWIFT'
final class Store {
    // The reload root.
    // swiftlint:disable:next model_held_across_reload
    private(set) var block: Block?
}
SWIFT
expect_exit "an uncited model_held_across_reload exemption" "$status" 1
expect_text "it names the rule" "$out" "App/A.swift:3: the model_held_across_reload exemption cites no issue."
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
expect_text "it names the bug-shaped rule alone" "$out" "App/A.swift:1: the fixture_dates_are_literal exemption cites no issue."
expect_line "an enable line is no exemption" "$(tail -1 "$root/stdout")" "1 exemptions cite 0 issues, and 1 fail"
check <<'SWIFT'
// swiftlint:enable unstructured_task_is_held
Task { await work() }
SWIFT
expect_exit "a lone enable line" "$status" 0
check <<'SWIFT'
// WCAG 1.4.3 exempts an inactive control from contrast.
// swiftlint:disable:next system_ink_outside_the_palette
let ink = Color.secondary
SWIFT
expect_exit "an uncited exemption of a rule that records a design fact" "$status" 0
expect_line "it reports the count" "$out" "1 exemptions cite 0 issues, and 0 fail"
expect_no_gh "a run with nothing cited"
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
check <<'SWIFT'
// swiftlint:disable:next unstructured_task_is_held
Task { await work() }  // #100
// Tracked in #100.
SWIFT
expect_exit "a citation below the exemption" "$status" 1
check <<'SWIFT'
Task { print("#100") }  // swiftlint:disable:this unstructured_task_is_held
SWIFT
expect_exit "a #100 in code before the directive's //" "$status" 1
check <<'SWIFT'
// swiftlint:disable:previous unstructured_task_is_held
SWIFT
expect_exit "an uncited disable:previous" "$status" 1

echo "the rule list"
check <<'SWIFT'
// swiftlint:disable:next line_length, unstructured_task_is_held
Task { await work() }
SWIFT
expect_exit "a bug-shaped rule after a comma-ended rule" "$status" 1
expect_text "it names the bug-shaped rule alone" "$out" "App/A.swift:1: the unstructured_task_is_held exemption cites no issue."
check <<'SWIFT'
// swiftlint:disable:next force_try because all of it is needed
Task { await work() }
SWIFT
expect_exit "prose before any ' - ', which SwiftLint reads as rules, all among them" "$status" 1
expect_text "it names all" "$out" "App/A.swift:1: the all exemption cites no issue."
check <<'SWIFT'
// swiftlint:disable:next force_try - all of unstructured_task_is_held is fine here
let value = try! load()
SWIFT
expect_exit "rule names after ' - ', which SwiftLint reads as the reason" "$status" 0

echo "where SwiftLint finds a directive"
check <<'SWIFT'
// Held. swiftlint:disable:next unstructured_task_is_held
Task { await work() }
SWIFT
expect_exit "an uncited directive after prose in its comment" "$status" 1
expect_text "it names the line" "$out" "App/A.swift:1: the unstructured_task_is_held exemption cites no issue."
check <<'SWIFT'
Task { await work() }  // note swiftlint:disable:this unstructured_task_is_held
SWIFT
expect_exit "an uncited disable:this after prose in a trailing comment" "$status" 1
check <<'SWIFT'
// noswiftlint:disable:next unstructured_task_is_held
Task { await work() }
SWIFT
expect_exit "an uncited directive glued to a word" "$status" 1
check <<'SWIFT'
let s = "a // b"; Task { await work() }  // x swiftlint:disable:this unstructured_task_is_held
SWIFT
expect_exit "an uncited directive after a string holding //" "$status" 1
check <<'SWIFT'
/* a */ // x swiftlint:disable:next unstructured_task_is_held
Task { await work() }
SWIFT
expect_exit "an uncited directive after a block comment" "$status" 1
check <<'SWIFT'
// Tracked in #100.
// Held. swiftlint:disable:next force_try
// swiftlint:disable:next unstructured_task_is_held
Task { await work() }
SWIFT
expect_exit "an uncited exemption under a cited mid-comment directive" "$status" 1
check <<'SWIFT'
// Held (#100). swiftlint:disable:next unstructured_task_is_held
Task { await work() }
SWIFT
expect_exit "a citation before the directive in its own comment" "$status" 0
check <<'SWIFT'
let a = "// swiftlint:disable:next unstructured_task_is_held"
let b = "x \("y") // swiftlint:disable:this unstructured_task_is_held"
let c = #"raw " // swiftlint:disable:this unstructured_task_is_held"#
let e = "a \" // swiftlint:disable:this unstructured_task_is_held"
let f = "\(g("//")) // swiftlint:disable:this unstructured_task_is_held"
/* a /* b */ // swiftlint:disable:next unstructured_task_is_held */
let d = """
    "quoted" // swiftlint:disable:next unstructured_task_is_held
    """
/* // swiftlint:disable:next unstructured_task_is_held */
/// swiftlint:disable:next unstructured_task_is_held
//// swiftlint:disable:next unstructured_task_is_held
// swiftlint: then swiftlint:disable:next unstructured_task_is_held
Task { await work() }
SWIFT
expect_exit "directive text SwiftLint does not honour" "$status" 0
expect_line "it counts none of it" "$out" "0 exemptions cite 0 issues, and 0 fail"
check <<'SWIFT'
let s = "left open
// swiftlint:disable:next unstructured_task_is_held
Task { await work() }
SWIFT
expect_exit "an uncited directive after a string left open at its line's end" "$status" 1
check <<'SWIFT'
work()  // Tracked in #100.
// swiftlint:disable:next unstructured_task_is_held
Task { await work() }
SWIFT
expect_exit "a citation in a trailing comment above the exemption" "$status" 1

echo "stacked directives"
check <<'SWIFT'
// Tracked in #100.
// swiftlint:disable:next force_try
// swiftlint:disable:next unstructured_task_is_held
Task { await work() }
SWIFT
expect_exit "an uncited exemption under a cited directive" "$status" 1
expect_text "it names the lower line" "$out" "App/A.swift:3: the unstructured_task_is_held exemption cites no issue."
check <<'SWIFT'
// Tracked in #100.
Task { await work() }  // swiftlint:disable:this unstructured_task_is_held
SWIFT
expect_exit "a disable:this on a code line under a cited comment" "$status" 1

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
check <<'SWIFT'
    static func live(  // swiftlint:disable:this unstructured_task_is_held
SWIFT
expect_exit "an uncited disable:this" "$status" 1
check <<'SWIFT'
// Tracked in #100,
// which explains why awaiting it
// would keep flushes apart.
// swiftlint:disable:next unstructured_task_is_held
Task { await work() }
SWIFT
expect_exit "a citation three contiguous comment lines up" "$status" 0

echo "citations"
for cite in '#100,' '(#100)' '#100.'; do
    check <<<"$(printf '// Tracked in %s\n// swiftlint:disable:next unstructured_task_is_held\nTask { }' "$cite")"
    expect_exit "a citation written $cite" "$status" 0
done
for cite in 'abc#100' '#100abc' 'Sunnshiine/workout-app#100' 'https://github.com/Sunnshiine/workout-app/issues/100' '#5' '#000000' '#0100'; do
    check <<<"$(printf '// Tracked in %s\n// swiftlint:disable:next unstructured_task_is_held\nTask { }' "$cite")"
    expect_exit "a bug-shaped exemption whose only number is $cite" "$status" 1
    expect_no_gh "$cite"
done
check <<'SWIFT'
// Step #3 of WCAG's procedure, and the ring is #000000.
// swiftlint:disable:next system_ink_outside_the_palette
let ink = Color.secondary
SWIFT
expect_exit "a design-fact exemption with a step number and a hex colour" "$status" 0
expect_no_gh "a step number and a hex colour"
check <<'SWIFT'
// Tracked in #100 and #101.
// swiftlint:disable:next unstructured_task_is_held
Task { await work() }
SWIFT
expect_exit "a second citation in one comment that is closed" "$status" 1
expect_text "it names the second" "$out" "the exemption cites #101, which is closed"

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
expect_line "it names the number and the fix" "$(head -1 "$root/stdout")" \
    "App/A.swift:2: the exemption cites #999, which is no issue or pull request in Sunnshiine/workout-app. Correct the number, or reword the text so it is no bare #N."

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
cited='// Tracked in #100.
// swiftlint:disable:next unstructured_task_is_held
Task { await work() }'
check env GH_STUB=unauthenticated python3 <<<"$cited"
expect_exit "an unauthenticated gh" "$status" 2
expect_text "it passes gh's message on" "$err" "error: gh issue view 100 exited 4: To get started with GitHub CLI"
expect_text "it says it did not pass unchecked" "$err" "it fails rather than pass unchecked"
expect_text "it says how to sign in" "$err" "Run \`gh auth login\`, or set GH_TOKEN."
if [ -z "$out" ]; then ok "it prints no count"; else bad "it printed: $out"; fi
check env GH_STUB=bad-token python3 <<<"$cited"
expect_exit "a rejected token" "$status" 2
expect_text "it says how to sign in" "$err" "Run \`gh auth login\`, or set GH_TOKEN."
check env GH_STUB=actions-no-token python3 <<<"$cited"
expect_exit "a CI job with no token" "$status" 2
expect_text "it says how to sign in" "$err" "Run \`gh auth login\`, or set GH_TOKEN."
check env GH_STUB=offline python3 <<<"$cited"
expect_exit "an unreachable network" "$status" 2
expect_text "it says the network is unreachable" "$err" "GitHub is unreachable from this machine."
expect_no_text "it does not blame sign-in" "$err" "gh auth login\`"
check env GH_STUB=slow LINT_EXEMPTIONS_GH_TIMEOUT=1 python3 <<<"$cited"
expect_exit "a gh that never answers" "$status" 2
expect_text "it says gh timed out" "$err" "error: gh issue view 100 did not answer within 1 s"
check env LINT_EXEMPTIONS_GH_TIMEOUT=soon python3 <<<"$cited"
expect_exit "a timeout that is no number" "$status" 64
expect_line "it names the variable" "$err" "error: LINT_EXEMPTIONS_GH_TIMEOUT is 'soon', not a positive number of seconds."
expect_no_text "it prints no traceback" "$err" "Traceback"
expect_no_gh "a timeout that is no number"
for seconds in 0 -1 inf; do
    check env LINT_EXEMPTIONS_GH_TIMEOUT=$seconds python3 <<<"$cited"
    expect_exit "a timeout of $seconds" "$status" 64
done
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

echo "a default: reason"
check <<'SWIFT'
func load(retrying: Bool = true) {} // default: a one-shot read is the exception, #101
SWIFT
expect_exit "a default: reason citing a closed issue" "$status" 1
expect_text "it names the issue" "$out" "App/A.swift:1: the exemption cites #101, which is closed without the wontfix label."
check <<'SWIFT'
func load(retrying: Bool = true) {} // default: accepted under #102
SWIFT
expect_exit "a default: reason citing a wontfix issue" "$status" 0
check <<'SWIFT'
func load(retrying: Bool = true) {} // default: a one-shot read is the exception
SWIFT
expect_exit "a default: reason citing nothing" "$status" 0
expect_line "it counts as an exemption" "$out" "1 exemptions cite 0 issues, and 0 fail"
check <<'SWIFT'
let caption = """
    a \
    b
    """
func load(retrying: Bool = true) {} // default: a one-shot read is the exception, #101
SWIFT
expect_exit "a default: reason under a string continued across a line" "$status" 1
expect_text "it names the reason's own line" "$out" "App/A.swift:5: the exemption cites #101, which is closed without the wontfix label."
check <<'SWIFT'
/// default: see #101
func load(retrying: Bool = true) {}
SWIFT
expect_exit "a doc comment that starts with default:" "$status" 0
expect_no_gh "a doc comment that starts with default:"

echo "unreadable input"
check <<<"$(printf '// \xff\xfe\n// swiftlint:disable:next unstructured_task_is_held\nTask { }')"
expect_exit "a Swift file that is not UTF-8" "$status" 2
expect_line "it names the file" "$(head -1 "$root/stderr")" "error: App/A.swift is not UTF-8"
expect_no_text "it prints no traceback" "$err" "Traceback"
plain="$root/plain"
mkdir -p "$plain"
python3 "$checker" "$plain" >"$root/stdout" 2>"$root/stderr"
expect_exit "a root outside any git checkout" "$?" 2
expect_text "it says git failed" "$(head -1 "$root/stderr")" "error: git ls-files failed in $(cd "$plain" && pwd -P): fatal: not a git repository"
expect_no_text "it prints no traceback" "$(cat "$root/stderr")" "Traceback"

echo
echo "$pass passed, $fail failed"
[ "$fail" -eq 0 ]
