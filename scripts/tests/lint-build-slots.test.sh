#!/usr/bin/env bash
set -uo pipefail

script_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
checker="$script_dir/../lint-build-slots.py"

tmp=$(mktemp -d) || exit 3
trap 'rm -rf "$tmp"' EXIT
pass=0
fail=0

ok()  { pass=$((pass + 1)); printf '  ok   %s\n' "$1"; }
bad() { fail=$((fail + 1)); printf '  FAIL %s\n' "$1"; }

check() { out=$(python3 "$checker" "$1" 2>&1); status=$?; }

expect_exit() {
    if [ "$status" -eq "$2" ]; then ok "$1 exits $2"; else bad "$1 exits $2, got $status: $out"; fi
}

expect_errors() {
    local got
    got=$(printf '%s\n' "$out" | grep -c '^error: ')
    if [ "$got" -eq "$2" ]; then ok "$1 reports $2 error(s)"; else bad "$1 reports $2 error(s), got $got: $out"; fi
}

tree() {
    local root="$tmp/$1"
    mkdir -p "$root/scripts/tests" "$root/scripts/ci" "$root/.agents/skills/verify/tests"
    printf '%s\n' "$root"
}

echo "builds through the slot, and commands that compile nothing, pass"
root=$(tree clean)
cat > "$root/scripts/run.sh" <<'SH'
#!/bin/bash
usage() {
    cat <<'EOF'
Runs swift test, then xcodebuild build.
EOF
}
# swift build runs below, in a slot.
scripts/build-slot.sh swift build --build-tests
"$repo/scripts/build-slot.sh" --as run.sh --log "$log" swift test --enable-code-coverage
with_build_slot --log "$log" xcodebuild build-for-testing -project P -scheme S \
    -destination "platform=iOS Simulator,id=$sim"
swift test --skip-build --filter X
swift build --show-bin-path
swift package resolve
xcodebuild test-without-building -xctestrun f.xctestrun
xcodebuild -showBuildSettings -project P
args=(swift test --filter X)
echo "swift build" 'xcodebuild build'
case $1 in spm-build) scripts/build-slot.sh swift build ;; esac
SH
cat > "$root/scripts/notes.md" <<'MD'
Run swift test.
MD
cat > "$root/scripts/tests/fixture.test.sh" <<'SH'
swift build
SH
cat > "$root/scripts/ci/runner.sh" <<'SH'
xcodebuild build -scheme S
SH
cat > "$root/.agents/skills/verify/tests/fake.sh" <<'SH'
swift test
SH
check "$root"
expect_exit "clean" 0

echo "each heavy build outside the slot is an error, as main's scripts had them"
root=$(tree raw)
cat > "$root/scripts/crap.sh" <<'SH'
#!/bin/bash
test_command() {
    swift test --enable-code-coverage
    xcodebuild test -workspace W -scheme S -destination platform=macOS
}
SH
cat > "$root/scripts/check-each-commit.sh" <<'SH'
#!/bin/bash
run_step() {
    case $1 in
        spm-build) swift build --build-tests ;;
        xcode-bft)
            xcodebuild build-for-testing -project WorkoutTracker.xcodeproj -scheme WorkoutTracker \
                -destination 'generic/platform=iOS Simulator'
            ;;
    esac
}
SH
cat > "$root/scripts/mutate.sh" <<'SH'
#!/bin/bash
(cd "$scratch" && with_timeout "$limit" swift build --build-tests) </dev/null >"$log" 2>&1 || rc=$?
SH
printf '#!/bin/zsh\nxcodebuild -project P -scheme S\n' > "$root/scripts/no-extension"
printf '#!/usr/bin/env bash\nswift run workout\n' > "$root/.agents/skills/verify/drive"
check "$root"
expect_exit "raw" 1
expect_errors "raw" 7
case $out in
    *"error: scripts/check-each-commit.sh:6: runs xcodebuild build-for-testing outside a host-wide slot; prefix it with scripts/build-slot.sh --as check-each-commit.sh"*)
        ok "a finding names the line and the fix" ;;
    *) bad "a finding names the line and the fix: $out" ;;
esac

echo "a script it cannot read is an error, not a pass"
root=$(tree unreadable)
printf '#!/bin/bash\necho "unclosed\n' > "$root/scripts/broken.sh"
check "$root"
expect_exit "unreadable" 1

echo "a root with neither directory is a usage error"
mkdir -p "$tmp/empty"
check "$tmp/empty"
expect_exit "empty" 2

echo "this checkout passes"
check "$script_dir/../.."
expect_exit "this checkout" 0

printf '\n%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" = 0 ]
