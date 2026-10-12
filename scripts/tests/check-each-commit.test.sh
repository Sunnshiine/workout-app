#!/bin/bash
# shellcheck disable=SC2016  # stubs hold literal $
set -uo pipefail

script_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
root=$(mktemp -d) || exit 3
root=$(cd "$root" && pwd -P)
trap 'rm -rf "$root"' EXIT
export LC_ALL=C GIT_CONFIG_COUNT=1 GIT_CONFIG_KEY_0=core.fsmonitor GIT_CONFIG_VALUE_0=false
export PATH="$root/bin:$PATH" STUB_WATCH=$root/watch STUB_CALLER=$root/repo STUB_XCODE_SEEN=$root/xcode-seen
repo=$root/repo
pass=0
fail=0

ok()  { pass=$((pass + 1)); printf '  ok   %s\n' "$1"; }
bad() { fail=$((fail + 1)); printf '  FAIL %s\n' "$1"; }
expect() {
    if [ "$2" = "$3" ]; then ok "$1"; else bad "$1"; printf '    got:\n%s\n    want:\n%s\n' "$2" "$3"; fi
}

mkdir -p "$root/bin" "$repo/scripts" "$repo/Sources" "$repo/App"
cp "$script_dir/../check-each-commit.sh" "$script_dir/../scratch-tree.sh" "$script_dir/../test-log.awk" "$repo/scripts/"

# swift build fails on BREAK under Sources/, swift test fails on FAILTEST, and xcodebuild fails on
# XBREAK under App/. Each records the caller's state while it runs.
cat >"$root/bin/swift" <<'STUB'
#!/bin/bash
{ git -C "$STUB_CALLER" status --porcelain; git -C "$STUB_CALLER" rev-parse HEAD; } >>"$STUB_WATCH"
if [ "$1" = build ]; then
    broken=$(grep -rn BREAK Sources | head -1 | cut -d: -f1,2)
    [ -z "$broken" ] || { echo "error: SwiftCompile normal arm64 $PWD/${broken%:*} failed with a nonzero exit code." >&2
        echo "$PWD/$broken:5: error: cannot find 'BREAK' in scope" >&2; exit 1; }
    echo "Build complete!"
    exit 0
fi
echo "◇ Test run started."
if grep -rq FAILTEST Sources; then
    echo "✘ Test gateOpens() recorded an issue at GateTests.swift:3:5: Expectation failed: 1 == 2"
    echo "✘ Test run with 3 tests in 1 suite failed after 0.001 seconds with 1 issue."
    exit 1
fi
echo "✔ Test run with 3 tests in 1 suite passed after 0.001 seconds."
echo "	 Executed 2 tests, with 0 failures (0 unexpected) in 0.001 (0.001) seconds"
STUB
cat >"$root/bin/xcodebuild" <<'STUB'
#!/bin/bash
{ git -C "$STUB_CALLER" status --porcelain; git -C "$STUB_CALLER" rev-parse HEAD; } >>"$STUB_WATCH"
echo "$*" >>"$STUB_XCODE_SEEN"
broken=$(grep -rn XBREAK App | head -1 | cut -d: -f1,2)
[ -z "$broken" ] || { echo "$PWD/$broken:1: error: cannot find 'XBREAK' in scope"; echo "** TEST BUILD FAILED **"; exit 65; }
echo "** TEST BUILD SUCCEEDED **"
STUB
chmod +x "$root/bin/swift" "$root/bin/xcodebuild"

git init -q -b main "$repo"
git -C "$repo" config user.email t@example.com
git -C "$repo" config user.name t
printf '.build/\n' >"$repo/.gitignore"
echo 'let gate = 3' >"$repo/Sources/Gate.swift"
echo 'let app = 1' >"$repo/App/App.swift"
git -C "$repo" add -A && git -C "$repo" commit -qm base
commit() {
    echo "$2" >"$repo/$1"
    git -C "$repo" commit -qam "$3"
    git -C "$repo" rev-parse --short=8 HEAD
}
c1=$(commit Sources/Gate.swift 'let gate = 4' "raise the gate")
c2=$(commit Sources/Gate.swift 'let gate = BREAK' "break the build")
c3=$(commit Sources/Gate.swift 'let gate = 4' "repair the build")
c4=$(commit App/App.swift 'let app = XBREAK' "break App/ only")
c5=$(commit App/App.swift 'let app = 1' "repair App/")
c6=$(commit Sources/Gate.swift 'let gate = 4 // FAILTEST' "add a failing test")
echo 'let gate = BREAK' >"$repo/Sources/Gate.swift"
before=$(git -C "$repo" status --porcelain; git -C "$repo" rev-parse HEAD)

(cd "$repo" && scripts/check-each-commit.sh main~6..main) >"$root/out" 2>"$root/err"
status=$?
logs=$(sed -n '1s/^log: //p' "$root/out")
expect "every commit prints one line, a failing step names its first error and log, and the run exits 1" "$status
$(sed -E '1d; s/ [0-9]+s( |$)/ Ns\1/g' "$root/out")
$(cat "$root/err")" "1
scratch: $repo/.build/scratch/1
ok    $c1  spm-build Ns  spm-test 5 Ns  xcode-bft Ns  raise the gate
FAIL  $c2  spm-build ✘  spm-test -  xcode-bft -  break the build
      Sources/Gate.swift:1:5: error: cannot find 'BREAK' in scope
      log: $logs/$c2-spm-build.log
ok    $c3  spm-build Ns  spm-test 5 Ns  xcode-bft Ns  repair the build
FAIL  $c4  spm-build Ns  spm-test 5 Ns  xcode-bft ✘  break App/ only
      App/App.swift:1:1: error: cannot find 'XBREAK' in scope
      log: $logs/$c4-xcode-bft.log
ok    $c5  spm-build Ns  spm-test 5 Ns  xcode-bft Ns  repair App/
FAIL  $c6  spm-build Ns  spm-test ✘  xcode-bft -  add a failing test
      ✘ Test gateOpens() recorded an issue at GateTests.swift:3:5: Expectation failed: 1 == 2
      log: $logs/$c6-spm-test.log
3 of 6 commits failed
"
expect "the logs sit under the caller's .build/check-each-commit" "${logs%/*}" "$repo/.build/check-each-commit"
expect "xcodebuild builds for testing on a generic simulator destination" "$(sort -u "$STUB_XCODE_SEEN")" \
    "build-for-testing -project WorkoutTracker.xcodeproj -scheme WorkoutTracker -destination generic/platform=iOS Simulator -skipPackagePluginValidation -skipMacroValidation CODE_SIGNING_ALLOWED=NO"
expect "the caller's HEAD and status never change while commits build" "$(sort -u "$STUB_WATCH")" "$(sort -u <<<"$before")"
expect "the caller's uncommitted edit is still there after the run" "$(git -C "$repo" status --porcelain; git -C "$repo" rev-parse HEAD)" "$before"

(cd "$repo" && scripts/check-each-commit.sh main~1) >"$root/out" 2>"$root/err"
expect "BASE alone means BASE..HEAD" "$? $(sed -E '1,2d; s/ [0-9]+s( |$)/ Ns\1/g' "$root/out")" \
    "1 FAIL  $c6  spm-build Ns  spm-test ✘  xcode-bft -  add a failing test
      ✘ Test gateOpens() recorded an issue at GateTests.swift:3:5: Expectation failed: 1 == 2
      log: $(sed -n '1s/^log: //p' "$root/out")/$c6-spm-test.log
1 of 1 commits failed"

(cd "$repo" && scripts/check-each-commit.sh main..main) >"$root/out" 2>"$root/err"
expect "an empty range exits 2" "$? $(cat "$root/out" "$root/err")" "2 no commits in main..main"

(cd "$repo" && scripts/check-each-commit.sh main~1...main) >"$root/out" 2>"$root/err"
expect "a three-dot range is a usage error" "$? $(cat "$root/out")
$(head -1 "$root/err")" "2 
A...B names both sides of a fork; check-each-commit.sh takes BASE..HEAD"

(cd "$repo" && scripts/check-each-commit.sh nope..main) >"$root/out" 2>"$root/err"
expect "a range git cannot resolve exits 2" "$? $(cat "$root/out" "$root/err")" "2 not a commit range: nope..main"

printf '\npassed %s, failed %s\n' "$pass" "$fail"
[ "$fail" -eq 0 ] || exit 1
