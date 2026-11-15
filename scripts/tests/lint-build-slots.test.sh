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

echo "running a .swift file by path compiles it, so it is a heavy build too"
root=$(tree by-path)
cat > "$root/scripts/shoot.sh" <<'SH'
#!/bin/bash
tiler=$repo/scripts/contact-sheet.swift
scripts/contact-sheet.swift out.png a.png
"$tiler" out.png a.png
line=$("${tiler}" out.png a.png)
perl -e 'alarm 60; exec @ARGV' "$tiler" out.png a.png
env LANG=C "$tiler" out.png a.png
if swift "$repo/tools/generate.swift"; then :; fi
xcrun swift generate.swift
SH
cat > "$root/scripts/contact-sheet.sh" <<'SH'
#!/bin/bash
source=$here/contact-sheet.swift
other=$here/other.swift
exec "$source" "$@"
exec "$other" "$@"
SH
cat > "$root/scripts/fine.sh" <<'SH'
#!/bin/bash
tiler=$repo/scripts/contact-sheet.swift
scripts/build-slot.sh --as fine.sh "$tiler" out.png a.png
with_build_slot "$tiler" out.png a.png
echo "$tiler" scripts/contact-sheet.swift
cp "$tiler" "$tmp/"
[ -f "$tiler" ] || exit 1
case $f in
    *.swift) ;;
    Tests/Unit/GoogleAuthTests.swift) return 1 ;;
    Sources/*.swift | App/*.swift) continue ;;
esac
SH
check "$root"
expect_exit "by path" 1
expect_errors "by path" 8
case $out in
    *"error: scripts/shoot.sh:5: runs \$repo/scripts/contact-sheet.swift by path, which compiles it with swift-frontend outside a host-wide slot"*)
        ok "a finding names the line and the file it compiles" ;;
    *) bad "a finding names the line and the file it compiles: $out" ;;
esac
case $out in
    *"scripts/contact-sheet.sh:5: runs \$here/other.swift"*) ok "an exception covers only the .swift file it names" ;;
    *) bad "an exception covers only the .swift file it names: $out" ;;
esac
case $out in
    *"scripts/fine.sh"*|*"scripts/contact-sheet.sh:4:"*) bad "a slotted call, a mention, a case pattern and a listed exception pass: $out" ;;
    *) ok "a slotted call, a mention, a case pattern and a listed exception pass" ;;
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
