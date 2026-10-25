#!/bin/bash
# shellcheck disable=SC2016  # expected text holds literal backticks
set -uo pipefail

script_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
tmp=$(mktemp -d) || exit 3
trap 'rm -rf "$tmp"' EXIT
pass=0
fail=0

ok()  { pass=$((pass + 1)); printf '  ok   %s\n' "$1"; }
bad() { fail=$((fail + 1)); printf '  FAIL %s\n' "$1"; }
expect() {
    if [ "$2" = "$3" ]; then ok "$1"; else
        bad "$1"
        diff <(printf '%s\n' "$3") <(printf '%s\n' "$2") | sed 's/^/       /'
    fi
}

repo=$tmp/repo
mkdir -p "$repo/scripts" "$repo/Sources" "$repo/App"
cp "$script_dir/../mutate-advisory.sh" "$repo/scripts/"
cat >"$repo/scripts/mutate.sh" <<'SH'
#!/bin/bash
printf '%s\n' "$*" >"$(dirname "$0")/../args"
cat "$(dirname "$0")/../fake-output"
exit "$(cat "$(dirname "$0")/../fake-status")"
SH
chmod +x "$repo/scripts/mutate.sh"
mkdir -p "$tmp/bin"
cat >"$tmp/bin/gh" <<'SH'
#!/bin/bash
[ "$1" = api ] || exit 9
shift
if [ "$1" = -X ]; then
    printf '%s %s\n%s\n' "$2" "$3" "$(cat "${5#body=@}")" >>"$GH_LOG"
    exit 0
fi
jq -r "$4" "$GH_COMMENTS"
SH
chmod +x "$tmp/bin/gh"
export PATH="$tmp/bin:$PATH" GITHUB_REPOSITORY=o/r GH_LOG=$tmp/gh.log GH_COMMENTS=$tmp/comments.json
git -C "$repo" init -q
echo 'let a = 1' >"$repo/Sources/A.swift"
echo 'let v = 1' >"$repo/App/V.swift"
git -C "$repo" add -A && git -C "$repo" -c user.name=t -c user.email=t@t commit -qm base

run() {
    printf '%s\n' "$1" >"$repo/fake-output"
    echo "$2" >"$repo/fake-status"
    rm -f "$repo/args"
    out=$(cd "$repo" && scripts/mutate-advisory.sh HEAD^1 2>"$tmp/stderr")
    status=$?
}

echo 'let v = 2' >"$repo/App/V.swift"
git -C "$repo" -c user.name=t -c user.email=t@t commit -qam app
run "" 0
expect "an App-only diff prints no body, says why, runs no mutant, and exits 0" "$status|$out|$(cat "$tmp/stderr")|$([ -e "$repo/args" ] && echo ran)" \
    "0||mutate-advisory: this diff changes no Sources/ file, so it is out of reach of swift test|"

echo 'let a = 2' >"$repo/Sources/A.swift"
git -C "$repo" -c user.name=t -c user.email=t@t commit -qam fix
run "log: x
mutants: 3 on 1 changed line in 1 file since abc
killed       Sources/A.swift:1  const   1 -> 2  aTest
SURVIVED     Sources/A.swift:1  result  return a -> return []
not run      Sources/A.swift:1  clamp   max(a, 1) -> a
2 mutants: 1 killed, 1 SURVIVED; 1 not run (--max 1)" 1
expect "survivors print as a body that lists them, the unrun ones, and the summary" "$status
$out" '0
**Mutants that survive on the lines this fix changed** (advisory, from `scripts/mutate.sh --diff`)

Each row is a one-line change to the code that every `swift test` test still passes. Pin the
behaviour with a test, or say in the PR why the mutant is equivalent.

```text
SURVIVED     Sources/A.swift:1  result  return a -> return []
not run      Sources/A.swift:1  clamp   max(a, 1) -> a
2 mutants: 1 killed, 1 SURVIVED; 1 not run (--max 1)
```'
expect "it runs the full suite on Sources only, capped at 20" "$(cat "$repo/args")" "--max 20 --diff HEAD^1 Sources"
expect "the mutate.sh output goes to stderr" "$(sed -n 2p "$tmp/stderr")" "mutants: 3 on 1 changed line in 1 file since abc"

run "1 mutant: 1 killed" 0
expect "every mutant killed prints no body" "$status|$out" "0|"

run "the untouched snapshot must pass before mutating; swift test reports:
SURVIVED     Sources/A.swift:1  const  1 -> 2" 2
expect "a run with no verdict prints no body and exits 0" "$status|$out|$(tail -1 "$tmp/stderr")" \
    "0||mutate-advisory: mutate.sh exited 2 with no verdict, so nothing is posted"

comment() {
    printf '%s\n' "$1" >"$GH_COMMENTS"
    : >"$GH_LOG"
    printf '%s\n' "$2" >"$repo/fake-output"
    echo "$3" >"$repo/fake-status"
    (cd "$repo" && scripts/mutate-advisory.sh --comment 7 --at 0123456789abcdef HEAD^1 2>/dev/null)
    status=$?
}
survivor="SURVIVED     Sources/A.swift:1  const  1 -> 2
1 mutant: 1 SURVIVED"

comment '[]' "$survivor" 1
expect "a survivor and no earlier comment posts one comment that names the commit" "$status|$(head -2 "$GH_LOG")|$(tail -2 "$GH_LOG")" \
    "0|POST repos/o/r/issues/7/comments
<!-- mutate-advisory -->|
At 01234567."

comment '[{"id": 5, "user": {"login": "github-actions[bot]"}, "body": "<!-- mutate-advisory -->\nold"}]' "$survivor" 1
expect "a survivor with an earlier comment updates that comment" "$(head -1 "$GH_LOG")" "PATCH repos/o/r/issues/comments/5"

comment '[]' "1 mutant: 1 killed" 0
expect "every mutant killed and no earlier comment posts nothing" "$status|$(cat "$GH_LOG")" "0|"

(cd "$repo" && scripts/mutate-advisory.sh >/dev/null 2>&1)
expect "no BASE is a usage error" "$?" "2"

echo
echo "$pass passed, $fail failed"
[ "$fail" -eq 0 ]
