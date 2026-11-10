#!/bin/bash
set -uo pipefail

repo=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
tmp=$(mktemp -d) || exit 3
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

# Runs the settings hook as Claude Code does, with the PreToolUse JSON for command $2 on stdin.
run_hook() {
    local -x CLAUDE_PROJECT_DIR=$1
    COMMAND=$2 python3 -c '
import json, os
print(json.dumps({"session_id": "t", "hook_event_name": "PreToolUse", "tool_name": "Bash",
                  "tool_input": {"command": os.environ["COMMAND"], "description": "x"},
                  "cwd": os.environ["CLAUDE_PROJECT_DIR"]}))' >"$tmp/in"
    bash -c "$hook" <"$tmp/in" 2>"$tmp/err"
}

echo "the guard, through the settings hook"
while IFS=$'\t' read -r want command replacement; do
    command=${command//\\n/$'\n'}
    run_hook "$repo" "$command"
    got=$?
    label="$want: ${command//$'\n'/\\n}"
    if [ "$want" = allow ]; then
        if [ "$got" = 0 ]; then ok "$label"; else bad "$label, got exit $got: $(head -3 "$tmp/err")"; fi
        continue
    fi
    replacement=${replacement:-scripts/build-slot.sh $command}
    if [ "$got" != 2 ]; then
        bad "$label, got exit $got"
    elif ! grep -qxF "  $replacement" "$tmp/err"; then
        bad "$label, stderr lacks the line '  $replacement':"
        sed 's/^/    /' "$tmp/err"
    else
        ok "$label"
    fi
done <<'ROWS'
refuse	swift build
refuse	swift test
refuse	swift test --filter SyncCoordinatorTests
refuse	swift run workout
refuse	swift run workout -- log w1d1.e0.s0 185x5@8
refuse	swift-build -c release
refuse	swift build --product workout && export PATH="$PWD/.build/debug:$PATH"	scripts/build-slot.sh swift build --product workout
refuse	cd Sources && swift test	scripts/build-slot.sh swift test
refuse	FOO=1 swift test	FOO=1 scripts/build-slot.sh swift test
refuse	swift test 2>&1 | tail -5	scripts/build-slot.sh swift test
refuse	swift test --enable-code-coverage > out.txt	scripts/build-slot.sh swift test --enable-code-coverage
refuse	cd x\nswift test	scripts/build-slot.sh swift test
refuse	swift build \\n  --product workout	scripts/build-slot.sh swift build --product workout
refuse	echo hi # note\nswift build	scripts/build-slot.sh swift build
refuse	perl -e 'alarm 600; exec @ARGV' swift test
refuse	env -i swift build
refuse	nice -n 10 caffeinate -i swift test
refuse	bash -c 'swift test'
refuse	sh -lc "cd x && swift build"	scripts/build-slot.sh sh -lc 'cd x && swift build'
refuse	if swift test; then echo ok; fi	scripts/build-slot.sh swift test
refuse	{ swift test; }	scripts/build-slot.sh swift test
refuse	for x in a; do swift test; done	scripts/build-slot.sh swift test
refuse	! swift build	scripts/build-slot.sh swift build
refuse	echo ""; swift build	scripts/build-slot.sh swift build
refuse	git commit --allow-empty -m "" && swift test	scripts/build-slot.sh swift test
refuse	echo $(swift build)	scripts/build-slot.sh swift build
refuse	/usr/bin/xcrun xcodebuild test -scheme X
refuse	xcrun --sdk iphonesimulator xcodebuild build -scheme X
refuse	xcodebuild build-for-testing -project WorkoutTracker.xcodeproj -scheme WorkoutTracker
refuse	xcodebuild -project P -scheme S
refuse	xcodebuild archive -scheme S
refuse	xcodebuild clean build -scheme S
refuse	scripts/receipt.sh unit -- swift test	scripts/receipt.sh unit -- scripts/build-slot.sh swift test
refuse	bash scripts/receipt.sh unit -- swift test	bash scripts/receipt.sh unit -- scripts/build-slot.sh swift test
allow	swift --version
allow	swift
allow	swift package resolve
allow	swift format lint -r Sources
allow	swift-format lint -r Sources
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
allow	cat > f <<EOF\nswift test\nEOF
allow	git commit -m "$(cat <<'EOF'\nfix: x\n\nswift test\nEOF\n)"
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
