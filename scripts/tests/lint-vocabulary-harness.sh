# shellcheck shell=bash
# Sourced by the lint-vocabulary*.test.sh files: a scratch repo with a glossary, a list, and
# existing names at origin/main, the checker, and the expect helpers.
script_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
checker="$script_dir/../lint-vocabulary.py"

root=$(mktemp -d) || exit 3
trap 'rm -rf "$root"' EXIT
repo="$root/repo"
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

# A repo whose glossary avoids "displayed session", "tempo", "conflict", "e1rm", "actual rpe", and
# four phrases whose last words inflect differently,
# committed as origin/main with existing names the branch did not add: displayedSessionCount, the
# kept names conflict and conflicts, and the unrelated name conflicting.
fresh_repo() {
    rm -rf "$repo"
    mkdir -p "$repo/Sources/Core" "$repo/App" "$repo/Tests" "$repo/scripts" "$repo/docs/context"
    cat >"$repo/CONTEXT.md" <<'EOF'
**Viewed Session**: The Session on screen. Avoid: displayed session.
**Sync Outcome**: What a flush did. Avoid: conflict.
**Estimated Single**: A one-rep estimate. Avoid: e1rm, actual rpe.
**Ledger**: Past Set Logs. Avoid: history, index, rate, dictation log.
EOF
    cat >"$repo/docs/context/logging.md" <<'EOF'
**Cadence**: The coach's tempo prefix. Avoid: tempo.
**Coach Note**: Coach prose in a Notes cell.
EOF
    cat >"$repo/scripts/vocabulary-avoid.txt" <<'EOF'
[avoid]
displayed session
tempo
conflict
e1rm
actual rpe
history
index
rate
dictation log

[kept]
conflict
conflicts

[unrelated]
conflicting
EOF
    cat >"$repo/Sources/Core/Old.swift" <<'EOF'
let displayedSessionCount = 1
let conflicts = 0
func refuse(conflict: Int) -> Int { conflict }
enum Reason { case heard, conflicting }
EOF
    git -C "$repo" init -q
    git -C "$repo" add -A
    git -C "$repo" -c user.name=t -c user.email=t@example.com commit -qm base
    git -C "$repo" update-ref refs/remotes/origin/main HEAD
}

check() {
    (cd "$repo" && python3 "$checker" "$@") >"$root/stdout" 2>"$root/stderr"
    status=$?
    out=$(cat "$root/stdout")
    err=$(cat "$root/stderr")
}
