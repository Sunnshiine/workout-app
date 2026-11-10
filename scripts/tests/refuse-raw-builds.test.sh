#!/bin/bash
set -uo pipefail

repo=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
tmp=$(mktemp -d "${TMPDIR:-/tmp}/refuse-raw-builds.XXXXXX") || exit 3
trap 'rm -rf "$tmp"' EXIT
pass=0
fail=0

ok()  { pass=$((pass + 1)); printf '  ok   %s\n' "$1"; }
bad() { fail=$((fail + 1)); printf '  FAIL %s\n' "$1"; }

hook=$(python3 -c '
import json, sys
for entry in json.load(open(sys.argv[1]))["hooks"].get("PreToolUse", []):
    if entry.get("matcher") == "Bash":
        for h in entry["hooks"]:
            if "refuse-raw-builds.py" in h.get("command", ""):
                print(h["command"])
' "$repo/.claude/settings.json")
if [ -z "$hook" ]; then
    bad "settings.json has a PreToolUse Bash hook that runs scripts/refuse-raw-builds.py"
    printf '%d passed, %d failed\n' "$pass" "$fail"
    exit 1
fi

fx=$tmp/fixture
slot=$fx/scripts/build-slot.sh
mkdir -p "$fx/scripts" "$fx/bin" "$fx/Sources" "$fx/x"
cp "${GUARD:-$repo/scripts/refuse-raw-builds.py}" "$fx/scripts/refuse-raw-builds.py"
printf '#!/bin/bash\nexec "$@"\n' >"$slot"
printf '#!/bin/bash\nwhile [ "$1" != -- ]; do shift; done\nshift\nexec "$@"\n' >"$fx/scripts/receipt.sh"
for tool in swift swift-build xcodebuild xcrun git; do
    printf '#!/bin/bash\n{ pwd; printf "%%s\\n" "${0##*/}" "$@"; echo; } >>%q\n' "$fx/fake.log" >"$fx/bin/$tool"
done
chmod +x "$fx/scripts/"* "$fx/bin/"*

# Runs the settings hook as Claude Code does, from directory $1, with the PreToolUse JSON for command $2 on stdin.
run_hook() {
    local -x CLAUDE_PROJECT_DIR=$1
    COMMAND=$2 python3 -c '
import json, os
print(json.dumps({"session_id": "t", "hook_event_name": "PreToolUse", "tool_name": "Bash",
                  "tool_input": {"command": os.environ["COMMAND"], "description": "x"},
                  "cwd": os.environ["CLAUDE_PROJECT_DIR"]}))' >"$tmp/in"
    (cd "$1" && bash -c "$hook" <"$tmp/in" 2>"$tmp/err")
}

# Runs $2 in the fixture against the fakes, keeping what they receive in $tmp/$1.log.
run_in_fixture() {
    local status
    : >"$fx/fake.log"
    (cd "$fx" && PATH="$fx/bin:$PATH" DEVELOPER_DIR="$fx/no-xcode" bash -c "$2" >/dev/null 2>&1)
    status=$?
    mv "$fx/fake.log" "$tmp/$1.log"
    return "$status"
}

replacement_runs() {
    local command=$1 label=$2 line got want
    # These reach the real toolchain past the fakes, so they are judged but never run: a /usr path
    # names it, env -i clears PATH, and a login shell lets path_helper put /usr/bin first.
    case $command in /usr/* | "env -i swift"* | "sh -l"*) return ;; esac
    line=$(grep '^  ' "$tmp/err" | grep -F scripts/build-slot.sh)
    if [ "$(grep -c . <<<"$line")" != 1 ]; then
        bad "$label prints one slotted replacement, got: $line"
        return
    fi
    run_in_fixture original "$command"
    want=$?
    run_in_fixture replacement "${line#  }"
    got=$?
    if [ ! -s "$tmp/original.log" ]; then
        bad "$label reaches a fake build tool when run as written"
    elif [ "$got" != "$want" ] || ! cmp -s "$tmp/original.log" "$tmp/replacement.log"; then
        bad "$label replacement runs the same build in the same directory, exit $got vs $want:"
        diff "$tmp/original.log" "$tmp/replacement.log" | sed 's/^/    /'
    else
        ok "$label replacement runs as printed"
    fi
}

echo "the guard, through the settings hook"
while IFS=$'\t' read -r want command replacement; do
    command=${command//\{NL\}/$'\n'}
    command=${command//\{TAB\}/$'\t'}
    run_hook "$fx" "$command"
    got=$?
    label="$want: ${command//$'\n'/\\n}"
    if [ "$want" = allow ]; then
        if [ "$got" = 0 ]; then ok "$label"; else bad "$label, got exit $got: $(head -3 "$tmp/err")"; fi
        continue
    fi
    replacement=${replacement:-@SLOT@ $command}
    replacement=${replacement//@SLOT@/$slot}
    if [ "$got" != 2 ]; then
        bad "$label, got exit $got"
        continue
    elif ! grep -qxF "  $replacement" "$tmp/err"; then
        bad "$label, stderr lacks the line '  $replacement':"
        sed 's/^/    /' "$tmp/err"
    else
        ok "$label"
    fi
    case $command in
        *"xcodebuild test "* | *test-without-building*)
            if grep -m1 '^  ' "$tmp/err" | grep -qF "$fx/scripts/test-sim.sh"; then
                ok "$label leads with scripts/test-sim.sh"
            else
                bad "$label leads with scripts/test-sim.sh"
            fi ;;
        *--enable-code-coverage*)
            if grep -qF "scripts/crap.sh gate" "$tmp/err"; then ok "$label names the coverage gate"; else bad "$label names the coverage gate"; fi ;;
    esac
    replacement_runs "$command" "$label"
done <<'ROWS'
refuse	swift build
refuse	swift test
refuse	swift test --filter SyncCoordinatorTests
refuse	swift run workout
refuse	swift run workout -- log w1d1.e0.s0 185x5@8
refuse	swift run workout --help
refuse	swift-build -c release
refuse	swift build --product workout && export PATH="$PWD/.build/debug:$PATH"	@SLOT@ bash -c 'swift build --product workout && export PATH="$PWD/.build/debug:$PATH"'
refuse	cd Sources && swift test	@SLOT@ bash -c 'cd Sources && swift test'
refuse	FOO=1 swift test	FOO=1 @SLOT@ swift test
refuse	DEVELOPER_DIR='/Applications/Xcode 27.app/Contents/Developer' swift test	DEVELOPER_DIR='/Applications/Xcode 27.app/Contents/Developer' @SLOT@ swift test
refuse	swift test 2>&1 | tail -5	@SLOT@ bash -c 'swift test 2>&1 | tail -5'
refuse	swift test --enable-code-coverage > out.txt	@SLOT@ bash -c 'swift test --enable-code-coverage > out.txt'
refuse	cd x{NL}swift test	@SLOT@ bash -c $'cd x\nswift test'
refuse	swift build \{NL}  --product workout	@SLOT@ swift build --product workout
refuse	echo hi # note{NL}swift build	@SLOT@ bash -c $'echo hi # note\nswift build'
refuse	echo "a <<EOF b"{NL}swift test	@SLOT@ bash -c $'echo "a <<EOF b"\nswift test'
refuse	perl -e 'alarm 600; exec @ARGV' swift test
refuse	env -i swift build
refuse	env -i PATH="$PATH" swift build	@SLOT@ bash -c 'env -i PATH="$PATH" swift build'
refuse	env -S "swift test"	@SLOT@ env -S 'swift test'
refuse	nice -n 10 caffeinate -i swift test
refuse	exec swift test	@SLOT@ bash -c 'exec swift test'
refuse	bash -c 'swift test'
refuse	sh -lc "cd x && swift build"	@SLOT@ sh -lc 'cd x && swift build'
refuse	sh -ec "cd x && swift build"	@SLOT@ sh -ec 'cd x && swift build'
refuse	if swift test; then echo ok; fi	@SLOT@ bash -c 'if swift test; then echo ok; fi'
refuse	{ swift test; }	@SLOT@ bash -c '{ swift test; }'
refuse	for x in a; do swift test; done	@SLOT@ bash -c 'for x in a; do swift test; done'
refuse	! swift build	@SLOT@ bash -c '! swift build'
refuse	echo ""; swift build	@SLOT@ bash -c 'echo ""; swift build'
refuse	git commit --allow-empty -m "" && swift test	@SLOT@ bash -c 'git commit --allow-empty -m "" && swift test'
refuse	echo $(swift build)	@SLOT@ bash -c 'echo $(swift build)'
refuse	/usr/bin/xcrun xcodebuild test -scheme X
refuse	xcrun --sdk iphonesimulator xcodebuild build -scheme X
refuse	xcodebuild test -scheme X
refuse	xcodebuild test-without-building -xctestrun f.xctestrun
refuse	xcodebuild build-for-testing -project WorkoutTracker.xcodeproj -scheme WorkoutTracker
refuse	xcodebuild -project P -scheme S
refuse	xcodebuild archive -scheme S
refuse	xcodebuild clean build -scheme S
refuse	scripts/receipt.sh unit -- swift test	scripts/receipt.sh unit -- @SLOT@ swift test
refuse	bash scripts/receipt.sh unit -- swift test	bash scripts/receipt.sh unit -- @SLOT@ swift test
allow	swift --version
allow	swift
allow	swift package resolve
allow	swift format lint -r Sources
allow	swift-format lint -r Sources
allow	swift test --help
allow	swift build --help
allow	swift run --help
allow	swift build -h
allow	swift build --show-bin-path
allow	swift-build --version
allow	swift test --skip-build --filter Foo
allow	swift run --skip-build workout
allow	echo "&&" swift test
allow	echo ';' swift test
allow	printf "%s\n" ";" "swift" "test"
allow	printf "%s\n" "(" "swift" "test" ")"
allow	scripts/build-slot.sh swift test
allow	./scripts/build-slot.sh xcodebuild build-for-testing -project P
allow	/opt/checkout/scripts/build-slot.sh swift build
allow	bash scripts/build-slot.sh swift test
allow	hostgate run -- swift test
allow	scripts/test-sim.sh unit
allow	scripts/crap.sh gate
allow	scripts/receipt.sh unit -- scripts/build-slot.sh swift test
allow	xcodebuild -version
allow	xcodebuild -showBuildSettings -project P
allow	xcodebuild -list
allow	xcodebuild -scheme build -showBuildSettings
allow	xcodebuild clean
allow	xcrun simctl list
allow	xcrun --find xcodebuild
allow	xcrun --show-sdk-path
allow	command -v xcodebuild
allow	echo swift test
allow	grep -rn "swift build" docs
allow	git commit -m "swift test is refused"
allow	cat > f <<EOF{NL}swift test{NL}EOF
allow	cat <<-'EOF'{NL}{TAB}swift test{NL}{TAB}EOF
allow	git commit -m "$(cat <<'EOF'{NL}fix: x{NL}{NL}swift test{NL}EOF{NL})"
allow	echo hi # swift build; swift test
allow	echo "swift test
ROWS

echo "fail-open"
stub() {
    rm -rf "$tmp/stub" && mkdir -p "$tmp/stub/scripts"
    [ $# = 0 ] && return
    printf '%s\n' "$2" > "$tmp/stub/scripts/refuse-raw-builds.py"
    chmod "$1" "$tmp/stub/scripts/refuse-raw-builds.py"
}
expect_exit() {
    local want=$1 label=$2 got
    run_hook "$tmp/stub" "swift test"
    got=$?
    if [ "$got" = "$want" ]; then ok "$label"; else bad "$label, got exit $got"; fi
}
stub;                                                  expect_exit 0 "a missing guard allows"
stub 644 $'#!/bin/sh\nexit 3';                         expect_exit 0 "a guard without the executable bit allows"
stub 755 $'#!/usr/bin/env python3\nraise RuntimeError("boom")'; expect_exit 0 "a guard that raises allows"
stub 755 $'#!/bin/sh\nexit 2';                         expect_exit 0 "a guard that exits 2 does not block"
stub 755 $'#!/bin/sh\nexit 3';                         expect_exit 2 "a guard that exits 3 blocks"
out=$(echo 'not json' | CLAUDE_PROJECT_DIR=$repo bash -c "$hook" 2>&1; echo "exit=$?")
if [ "$out" = exit=0 ]; then ok "malformed stdin allows silently"; else bad "malformed stdin allows silently, got: $out"; fi
out=$("$repo/scripts/refuse-raw-builds.py" --help 2>/dev/null; echo "exit=$?")
if [ "$out" = exit=2 ]; then ok "an argument exits 2"; else bad "an argument exits 2, got: $out"; fi

echo "the XcodeBuildMCP tools that boot, build or test stay denied"
deny=$(python3 -c 'import json, sys; print("\n".join(json.load(open(sys.argv[1]))["permissions"]["deny"]))' "$repo/.claude/settings.json")
while read -r tool; do
    if grep -qxF "mcp__XcodeBuildMCP__$tool" <<<"$deny"; then ok "denies $tool"; else bad "denies $tool"; fi
done <<'TOOLS'
boot_sim
open_sim
build_sim
build_run_sim
test_sim
install_app_sim
launch_app_sim
erase_sims
clean
build_device
build_run_device
test_device
build_macos
build_run_macos
test_macos
swift_package_build
swift_package_run
swift_package_test
xcode_ide_call_tool
TOOLS
if python3 -c 'import json, sys; sys.exit("XcodeBuildMCP" not in json.load(open(sys.argv[1]))["mcpServers"])' "$repo/.mcp.json"; then
    ok ".mcp.json still names the server XcodeBuildMCP, which the deny entries key on"
else
    bad ".mcp.json still names the server XcodeBuildMCP, which the deny entries key on"
fi

echo
printf '%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" = 0 ]
