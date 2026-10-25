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
expect "an App-only diff says it is out of reach, runs no mutant, and exits 0" "$status|$out|$([ -e "$repo/args" ] && echo ran)" \
    "0|This diff changes no Sources/ file, so no mutant runs.|"

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
expect "every mutant killed says so" "$status|$out" "0|Every mutant of the changed Sources lines was killed (1 mutant: 1 killed)."

run "the untouched snapshot must pass before mutating; swift test reports:
SURVIVED     Sources/A.swift:1  const  1 -> 2" 2
expect "a run with no verdict lists no survivor and exits 0" "$status|$out" \
    "0|mutate.sh exited 2 with no verdict, so no mutant ran. The job log names the cause, such as a red baseline (2) or busy scratch trees (75)."

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

bot='{"id": 5, "user": {"login": "github-actions[bot]"}, "body": "<!-- mutate-advisory -->\\nold"}'
person='{"id": 9, "user": {"login": "someone"}, "body": "<!-- mutate-advisory --> quoted"}'
comment "[$bot, $person]" "$survivor" 1
expect "a person's comment that starts with the marker is left alone, and the bot's is updated" "$(head -1 "$GH_LOG")" \
    "PATCH repos/o/r/issues/comments/5"
comment "[$person]" "$survivor" 1
expect "with only a person's marker comment, a survivor posts a new comment" "$(head -1 "$GH_LOG")" \
    "POST repos/o/r/issues/7/comments"

updated() {
    comment "[$bot]" "$2" "$3"
    expect "$1" "$status|$(head -1 "$GH_LOG")|$(sed -n '3,$p' "$GH_LOG")" "0|PATCH repos/o/r/issues/comments/5|$4"
}
updated "every mutant killed updates the earlier comment to say so" "log: x
mutants: 2 on 1 changed line in 1 file since abc
killed       Sources/A.swift:1  const   1 -> 2  aTest
killed       Sources/A.swift:1  bool    true -> false  aTest
2 mutants: 2 killed" 0 "Every mutant of the changed Sources lines was killed (2 mutants: 2 killed).

At 01234567."
updated "no mutant generated is not reported as none surviving" "log: x
mutants: 0 on 3 changed lines in 1 file since abc" 0 "No mutant was generated on the changed Sources lines.

At 01234567."
partial="No mutant survived, but not every mutant was run and killed, so the changed lines may still be unpinned:"
updated "a --max cut with no survivor lists the mutants it left out" "mutants: 3 on 1 changed line in 1 file since abc
killed       Sources/A.swift:1  const   1 -> 2  aTest
not run      Sources/A.swift:1  bool    true -> false
1 mutant: 1 killed; 1 not run (--max 1)" 1 "$partial

\`\`\`text
not run      Sources/A.swift:1  bool    true -> false
1 mutant: 1 killed; 1 not run (--max 1)
\`\`\`

At 01234567."
updated "mutants that did not compile are not reported as killed" "mutants: 1 on 1 changed line in 1 file since abc
nocompile    Sources/A.swift:1  const   1 -> 2  Sources/A.swift:1: error: x
1 mutant: 1 nocompile" 0 "$partial

\`\`\`text
nocompile    Sources/A.swift:1  const   1 -> 2  Sources/A.swift:1: error: x
1 mutant: 1 nocompile
\`\`\`

At 01234567."
updated "error and flaky rows are not reported as killed" "mutants: 2 on 1 changed line in 1 file since abc
error        Sources/A.swift:1  const   1 -> 2  runner failed
flaky        Sources/A.swift:1  bool    true -> false  aTest
2 mutants: 1 flaky, 1 error" 1 "$partial

\`\`\`text
error        Sources/A.swift:1  const   1 -> 2  runner failed
flaky        Sources/A.swift:1  bool    true -> false  aTest
2 mutants: 1 flaky, 1 error
\`\`\`

At 01234567."
for code in 2 75; do
    updated "exit $code updates the earlier comment to say no mutant ran" "the untouched snapshot must pass before mutating" $code \
        "mutate.sh exited $code with no verdict, so no mutant ran. The job log names the cause, such as a red baseline (2) or busy scratch trees (75).

At 01234567."
done
comment '[]' "the untouched snapshot must pass before mutating" 2
expect "a run with no verdict and no earlier comment posts nothing" "$status|$(cat "$GH_LOG")" "0|"

git -C "$repo" -c user.name=t -c user.email=t@t commit -q --allow-empty -m empty
updated "a diff that changes no Sources/ file updates the earlier comment to say so" "" 0 \
    "This diff changes no Sources/ file, so no mutant runs.

At 01234567."

guard=$(awk '/^  mutants:/ { job = 1; next } job && /^    if:/ { print; exit }' "$script_dir/../../.github/workflows/ci.yml")
titles=""
for title in "fix(sync): a" "fix: a" "fix!: a" "fix(sync)!: a" "feat(sync): a" "ci(mutate): a" "fixup: a"; do
    while IFS= read -r prefix; do
        [[ $title == "$prefix"* ]] && { titles="$titles$title,"; break; }
    done < <(grep -o "title, '[^']*'" <<<"$guard" | sed "s/title, '//; s/'$//")
done
expect "the CI job runs on fix titles, breaking ones included, and on no other type" "$titles" "fix(sync): a,fix: a,fix!: a,fix(sync)!: a,"

(cd "$repo" && scripts/mutate-advisory.sh >/dev/null 2>&1)
expect "no BASE is a usage error" "$?" "2"

echo
echo "$pass passed, $fail failed"
[ "$fail" -eq 0 ]
