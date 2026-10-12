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
    printf 'Secrets.xcconfig\n' >"$root/.gitignore"
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
printf 'Launch with `-UITEST_SLOW_SYNC`.\n' >"$root/.agents/skills/verify/SKILL.md"
printf 'let arguments = ["-UITEST_FIXTURE", "-UITEST_PARTIAL_BLOCK"]\n' >"$root/Tests/UI/Support.swift"
stage "$root"
check "$root"
expect_exit "flags" "$status" 1
expect_count "flags" "$out" 2
expect_line "flags" "$out" "error: .agents/skills/verify/SKILL.md:1: \`-UITEST_SLOW_SYNC\` is not a row of .agents/skills/verify/launch-flags.md, so the app ignores it."
expect_line "flags" "$out" "error: Tests/UI/Support.swift:1: \`-UITEST_PARTIAL_BLOCK\` is not a row of .agents/skills/verify/launch-flags.md, so the app ignores it."

echo "app sources spell a flag only in LaunchFlag"
root=$(tree literal)
printf 'let on = CommandLine.arguments.contains("-UITEST_FIXTURE")\n' >"$root/Sources/Core/Reader.swift"
stage "$root"
check "$root"
expect_exit "literal" "$status" 1
expect_count "literal" "$out" 1
expect_line "literal" "$out" "error: Sources/Core/Reader.swift:1: \`-UITEST_FIXTURE\` reads a launch flag outside LaunchFlag. Add a case there and read it through UITestLaunch."

echo "an exemption silences the names it lists, and a stale one is named"
root=$(tree exempt)
cat >"$root/docs/TESTING.md" <<'MD'
<!-- doc-symbols: not-in-tree AXGenericElement blueLight -->
axe prints `AXGenericElement` for the card.
MD
stage "$root"
check "$root"
expect_exit "exempt" "$status" 1
expect_count "exempt" "$out" 1
expect_line "exempt" "$out" "error: docs/TESTING.md:1: the exemption names \`blueLight\`, which no span in this file fails on. Drop it."

echo "ADRs, fenced blocks, ignored files, placeholders, and linked skills pass"
root=$(tree skipped)
printf 'Deleted `project.yml` and `OldCoordinator`.\n' >"$root/docs/adr/0001-old.md"
cat >"$root/docs/TESTING.md" <<'MD'
```bash
scripts/gone.sh --filter MissingTests
```

Copy `Secrets.xcconfig` into `<worktree>/Sources/Core`, then read
`.claude/skills/verify/SKILL.md` and `.claude/skills/<name>/SKILL.md`. Branch `origin/main`.
MD
stage "$root"
check "$root"
expect_exit "skipped" "$status" 0
expect_line "skipped" "$out" "==> Clean: 4 docs, 1 launch flags"

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
