#!/usr/bin/env bash
set -uo pipefail

script_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
checker="$script_dir/../lint-doc-symbols.py"

tmp=$(mktemp -d) || exit 3
trap 'rm -rf "$tmp"' EXIT
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

expect_count() {
    local got
    got=$(printf '%s\n' "$2" | grep -c '^error: ')
    if [ "$got" -eq "$3" ]; then ok "$1 reports $3 error(s)"; else bad "$1 reports $3 error(s), got $got"; fi
}

tree() {
    local root="$tmp/$1"
    mkdir -p "$root/docs/adr" "$root/.agents/skills/verify" "$root/.claude/skills" \
        "$root/Sources/Core" "$root/Sources/WorkoutTracker/Fixtures" "$root/Tests/UI" "$root/scripts"
    cat >"$root/.agents/skills/verify/launch-flags.md" <<'MD'
| Flag | Kind | Meaning |
| --- | --- | --- |
| `-UITEST_FIXTURE` | Switch | Runs on fixtures. |
MD
    printf '# Verify\n' >"$root/.agents/skills/verify/SKILL.md"
    ln -s ../../.agents/skills/verify "$root/.claude/skills/verify"
    printf 'struct SyncCoordinator { func fetchTabSnapshot(spreadsheetId: String) {} }\n' \
        >"$root/Sources/Core/SyncCoordinator.swift"
    printf 'let fixture = "-UITEST_FIXTURE"\n' >"$root/Sources/WorkoutTracker/Fixtures/LaunchFlag.swift"
    printf 'let arguments = ["-UITEST_FIXTURE"]\n' >"$root/Tests/UI/Support.swift"
    printf '#!/bin/bash\n' >"$root/scripts/flake-hunt.sh"
    printf 'Secrets.xcconfig\n.build/\n' >"$root/.gitignore"
    printf 'Run `scripts/flake-hunt.sh` against `SyncCoordinator`.\n' >"$root/AGENTS.md"
    git -C "$root" init -q
    echo "$root"
}

stage() {
    git -C "$1" add -A
}

check() {
    out=$("$checker" "$1" 2>&1)
    status=$?
}

echo "every span resolves: clean"
root=$(tree clean)
stage "$root"
check "$root"
expect_exit "clean" "$status" 0
expect_line "clean" "$out" "==> Clean: 3 docs, 1 launch flags"

echo "a moved path is named with the path that has its name"
root=$(tree moved)
printf 'Open `Core/SyncCoordinator.swift` and `WorkoutTracker/SyncCoordinator.swift`.\n' >"$root/docs/TESTING.md"
stage "$root"
check "$root"
expect_exit "moved" "$status" 1
expect_count "moved" "$out" 1
expect_line "moved" "$out" "error: docs/TESTING.md:1: \`WorkoutTracker/SyncCoordinator.swift\` is not a path in this tree."
expect_line "moved" "$out" "       Closest: Sources/Core/SyncCoordinator.swift."

echo "a path anchored at a top-level directory must exist there, not only deeper"
root=$(tree anchored)
mkdir -p "$root/tools/crap/Sources/CRAPKit"
printf 'let gate = 1\n' >"$root/tools/crap/Sources/CRAPKit/Gate.swift"
printf 'Open `Sources/CRAPKit/Gate.swift` from the root, and `CRAPKit/Gate.swift`.\n' >"$root/docs/TESTING.md"
stage "$root"
check "$root"
expect_exit "anchored" "$status" 1
expect_count "anchored" "$out" 1
expect_line "anchored" "$out" "error: docs/TESTING.md:1: \`Sources/CRAPKit/Gate.swift\` is not a path in this tree."

echo "a line suffix, a dotfile, and a call label are each checked"
root=$(tree suffixes)
printf 'x\n' >"$root/.swift-format"
cat >"$root/docs/TESTING.md" <<'MD'
See `scripts/flake-hunt.sh:1`, `scripts/gone.sh:12`, `.swift-format`, and `.swift-formatt`.
Call `SyncCoordinator.fetchTabSnapshot(spreadsheetIdd:)`.
MD
stage "$root"
check "$root"
expect_exit "suffixes" "$status" 1
expect_count "suffixes" "$out" 3
expect_line "suffixes" "$out" "error: docs/TESTING.md:1: \`scripts/gone.sh\` is not a path in this tree."
expect_line "suffixes" "$out" "error: docs/TESTING.md:1: \`.swift-formatt\` names no file in this tree."
expect_line "suffixes" "$out" "error: docs/TESTING.md:2: \`spreadsheetIdd\` is named in no Swift, project, or script file."

echo "a missing dotted chain is printed with its dot"
root=$(tree dotted)
printf 'Call `SyncCoordinatorGone.flushEverything` or `SyncCoordinator.flushEverything`.\n' >"$root/docs/TESTING.md"
stage "$root"
check "$root"
expect_exit "dotted" "$status" 1
expect_count "dotted" "$out" 2
expect_line "dotted" "$out" "error: docs/TESTING.md:1: \`SyncCoordinatorGone.flushEverything\` is named in no Swift, project, or script file."
expect_line "dotted" "$out" "error: docs/TESTING.md:1: \`flushEverything\` is named in no Swift, project, or script file."

echo "a fenced block's repo paths are checked, and its other words are not"
root=$(tree fenced)
cat >"$root/AGENTS.md" <<'MD'
```bash
scripts/flake-hunt.sh --repetitions 1000 SyncCoordinatorTests   # repeat under load
scripts/flakehunt.sh --filter MissingTests
export PATH="$PWD/.build/debug:$PATH" && cp Secrets.xcconfig .build/crap/report.json
xcodebuild -project <worktree>/WorkoutTracker.xcodeproj -only-testing WorkoutTrackerUITests/Smoke
echo "$(cat scripts/flake-hunt.sh)" | grep -c x scripts/flake-hunt.sh|wc -l
./scripts/gone-dot.sh && x="$(scripts/gone-subshell.sh)" && OUT=scripts/gone-env.sh
```
MD
stage "$root"
check "$root"
expect_exit "fenced" "$status" 1
expect_count "fenced" "$out" 4
expect_line "fenced" "$out" "error: AGENTS.md:3: \`scripts/flakehunt.sh\` is not a path in this tree."
expect_line "fenced" "$out" "error: AGENTS.md:7: \`scripts/gone-dot.sh\` is not a path in this tree."
expect_line "fenced" "$out" "error: AGENTS.md:7: \`scripts/gone-subshell.sh\` is not a path in this tree."
expect_line "fenced" "$out" "error: AGENTS.md:7: \`scripts/gone-env.sh\` is not a path in this tree."

echo "an exemption that copies a printed dotted chain silences it"
root=$(tree dotted-exempt)
cat >"$root/docs/TESTING.md" <<'MD'
<!-- doc-symbols: not-in-tree UIAccessibilityTraits.isHeader -->
VoiceOver reads `UIAccessibilityTraits.isHeader` here.
MD
stage "$root"
check "$root"
expect_exit "dotted exempt" "$status" 0

echo "a stray backtick in one list item does not swallow the next item's spans"
root=$(tree stray)
printf -- '- Press ` to open\n- Run `scripts/gone.sh` now\n' >"$root/docs/TESTING.md"
stage "$root"
check "$root"
expect_exit "stray" "$status" 1
expect_line "stray" "$out" "error: docs/TESTING.md:2: \`scripts/gone.sh\` is not a path in this tree."

echo "a renamed type is named with its nearest spelling"
root=$(tree renamed)
printf 'Call `SyncCoordinater.fetchTabSnapshot(spreadsheetId:)`.\n' >"$root/docs/TESTING.md"
stage "$root"
check "$root"
expect_exit "renamed" "$status" 1
expect_count "renamed" "$out" 1
expect_line "renamed" "$out" "error: docs/TESTING.md:1: \`SyncCoordinater\` is named in no Swift, project, or script file."
expect_line "renamed" "$out" "       Closest: SyncCoordinator."

echo "a span that wraps across lines resolves as one span"
root=$(tree wrapped)
printf 'Run `scripts/flake-hunt.sh\nSyncCoordinater` here.\n' >"$root/docs/TESTING.md"
stage "$root"
check "$root"
expect_exit "wrapped" "$status" 1
expect_count "wrapped" "$out" 1
expect_line "wrapped" "$out" "error: docs/TESTING.md:1: \`SyncCoordinater\` is named in no Swift, project, or script file."

echo "a flag the table lacks fails in a doc and in a test"
root=$(tree flags)
cat >"$root/.agents/skills/verify/SKILL.md" <<'MD'
Launch with `-UITEST_SLOW_SYNC`.

```bash
verify.sh launch settings -UITEST_BOGUS
```

Pass `["-UITEST_NOPE"]`.
MD
printf 'let arguments = ["-UITEST_FIXTURE", "-UITEST_PARTIAL_BLOCK"]\n' >"$root/Tests/UI/Support.swift"
printf 'let fixture = "-UITEST_FIXTURE"\nlet orphan = "-UITEST_ORPHAN"\n' >"$root/Sources/WorkoutTracker/Fixtures/LaunchFlag.swift"
stage "$root"
check "$root"
expect_exit "flags" "$status" 1
expect_count "flags" "$out" 5
expect_line "flags" "$out" "error: .agents/skills/verify/SKILL.md:4: \`-UITEST_BOGUS\` is not a row of .agents/skills/verify/launch-flags.md, so the app ignores it."
expect_line "flags" "$out" "error: .agents/skills/verify/SKILL.md:7: \`-UITEST_NOPE\` is not a row of .agents/skills/verify/launch-flags.md, so the app ignores it."
expect_line "flags" "$out" "error: Sources/WorkoutTracker/Fixtures/LaunchFlag.swift:2: \`-UITEST_ORPHAN\` is declared in LaunchFlag but missing from LaunchFlag.all. Add it there, then run: RECORD_LAUNCH_FLAGS=1 swift test --filter LaunchFlagTableTests"
expect_line "flags" "$out" "error: .agents/skills/verify/SKILL.md:1: \`-UITEST_SLOW_SYNC\` is not a row of .agents/skills/verify/launch-flags.md, so the app ignores it."
expect_line "flags" "$out" "error: Tests/UI/Support.swift:1: \`-UITEST_PARTIAL_BLOCK\` is not a row of .agents/skills/verify/launch-flags.md, so the app ignores it."

echo "app sources spell a flag only in LaunchFlag"
root=$(tree literal)
printf 'let on = CommandLine.arguments.contains("-UITEST_FIXTURE")\n' >"$root/Sources/Core/Reader.swift"
stage "$root"
check "$root"
expect_exit "literal" "$status" 1
expect_count "literal" "$out" 1
expect_line "literal" "$out" "error: Sources/Core/Reader.swift:1: \`-UITEST_FIXTURE\` reads a launch flag outside LaunchFlag. Declare it there and read it through UITestLaunch."

echo "an exemption silences the names it lists, and a stale one is named"
root=$(tree exempt)
cat >"$root/docs/TESTING.md" <<'MD'
<!-- doc-symbols: not-in-tree AXGenericElement blueLight retiredName -->
axe prints `AXGenericElement` for the card, and `retiredName.goneMember` once lived here.
MD
stage "$root"
check "$root"
expect_exit "exempt" "$status" 1
expect_count "exempt" "$out" 2
expect_line "exempt" "$out" "error: docs/TESTING.md:2: \`goneMember\` is named in no Swift, project, or script file."
expect_line "exempt" "$out" "error: docs/TESTING.md:1: the exemption names \`blueLight\`, which nothing in this file fails on. Drop it."

echo "an ADR is checked, and passes once it lists the names it retires; research notes are not"
root=$(tree adr)
mkdir -p "$root/docs/research"
printf 'Deleted `project.yml` and `OldCoordinator` for `SyncCoordinator`.\n' >"$root/docs/adr/0001-old.md"
cat >"$root/docs/adr/0002-amended.md" <<'MD'
Deleted `project.yml` and `OldCoordinator` for `SyncCoordinator`.

<!-- doc-symbols: not-in-tree project.yml OldCoordinator -->
MD
printf 'Read `goneResearchName`.\n' >"$root/docs/research/2026-01-01-note.md"
stage "$root"
check "$root"
expect_exit "adr" "$status" 1
expect_count "adr" "$out" 2
expect_line "adr" "$out" "error: docs/adr/0001-old.md:1: \`project.yml\` names no file in this tree."
expect_line "adr" "$out" "error: docs/adr/0001-old.md:1: \`OldCoordinator\` is named in no Swift, project, or script file."

echo "fenced words, ignored files, placeholders, and linked skills pass"
root=$(tree skipped)
cat >"$root/docs/TESTING.md" <<'MD'
```bash
scripts/flake-hunt.sh --filter MissingTests
```

Copy `Secrets.xcconfig` into `<worktree>/Sources/Core`, read `.build/crap/report.json`, then read
`.claude/skills/verify/SKILL.md` and `.claude/skills/<name>/SKILL.md`. Branch `origin/main`.
MD
stage "$root"
check "$root"
expect_exit "skipped" "$status" 0
expect_line "skipped" "$out" "==> Clean: 4 docs, 1 launch flags"

echo "an inline command's substituted path is checked"
root=$(tree substituted)
cat >"$root/AGENTS.md" <<'MD'
Start each call with `env=$(scripts/flake-hunt.sh env <name>) && eval "$env"`, or `"$(scripts/flake-hunt.sh)"`.
Then `out=$(scripts/gone.sh <name>)` and `$(scripts/gone-bare.sh)`.
MD
stage "$root"
check "$root"
expect_exit "substituted" "$status" 1
expect_count "substituted" "$out" 2
expect_line "substituted" "$out" "error: AGENTS.md:2: \`scripts/gone.sh\` is not a path in this tree."
expect_line "substituted" "$out" "error: AGENTS.md:2: \`scripts/gone-bare.sh\` is not a path in this tree."

echo "a placeholder path passes when git ignores the directory it sits in, and fails otherwise"
root=$(tree ignored-placeholder)
printf '.claude/worktrees/\n*.pyc\n' >>"$root/.gitignore"
cat >"$root/docs/TESTING.md" <<'MD'
A lane lives in `.claude/worktrees/<name>`, never in `.claude/worktree/<name>` or `scripts/gone/<name>.pyc`.
MD
stage "$root"
check "$root"
expect_exit "ignored placeholder" "$status" 1
expect_count "ignored placeholder" "$out" 2
expect_line "ignored placeholder" "$out" "error: docs/TESTING.md:1: \`.claude/worktree/<name>\` is not a path in this tree."
expect_line "ignored placeholder" "$out" "error: docs/TESTING.md:1: \`scripts/gone/<name>.pyc\` is not a path in this tree."

echo "root guides, CONTEXT, Sources, tools, and repo-authored skills are checked; vendored skills and .sandcastle are not"
root=$(tree scope)
mkdir -p "$root/tools/crap" "$root/.agents/skills/own" "$root/.agents/skills/triage" "$root/.sandcastle/plan"
printf 'See `Core/Gone.swift`.\n' >"$root/CODING_STANDARDS.md"
printf '**Viewed Session**: the Session `goneTermOwner` shows.\n' >"$root/CONTEXT.md"
printf 'See `goneHelper`.\n' >"$root/Sources/Core/README.md"
printf 'See `scripts/gone.sh`.\n' >"$root/tools/crap/README.md"
printf 'See `staleName`.\n' >"$root/.agents/skills/own/SKILL.md"
printf 'See `placeholderName` and `tickets.md`.\n' >"$root/.agents/skills/triage/SKILL.md"
printf 'See `exampleName`.\n' >"$root/.sandcastle/plan/extraction.md"
stage "$root"
check "$root"
expect_exit "scope" "$status" 1
expect_count "scope" "$out" 5
expect_line "scope" "$out" "error: CODING_STANDARDS.md:1: \`Core/Gone.swift\` is not a path in this tree."
expect_line "scope" "$out" "error: CONTEXT.md:1: \`goneTermOwner\` is named in no Swift, project, or script file."
expect_line "scope" "$out" "error: Sources/Core/README.md:1: \`goneHelper\` is named in no Swift, project, or script file."
expect_line "scope" "$out" "error: tools/crap/README.md:1: \`scripts/gone.sh\` is not a path in this tree."
expect_line "scope" "$out" "error: .agents/skills/own/SKILL.md:1: \`staleName\` is named in no Swift, project, or script file."

echo "a tree with no flag table is a usage error"
root=$(tree no-table)
rm "$root/.agents/skills/verify/launch-flags.md"
stage "$root"
check "$root"
expect_exit "no table" "$status" 2
expect_line "no table" "$out" "error: .agents/skills/verify/launch-flags.md is missing. Run: RECORD_LAUNCH_FLAGS=1 swift test --filter LaunchFlagTableTests"

echo "a root that is not a checkout is a usage error"
mkdir "$tmp/plain"
check "$tmp/plain"
expect_exit "not a checkout" "$status" 2
expect_line "not a checkout" "$out" "error: $tmp/plain is not a git checkout."

echo
echo "$pass passed, $fail failed"
[ "$fail" -eq 0 ]
