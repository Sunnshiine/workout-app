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
    printf '#!/bin/bash\n{ pwd; echo "DEVELOPER_DIR=$DEVELOPER_DIR FOO=${FOO-} NAME=${NAME-}"; printf "%%s\\n" "${0##*/}" "$@"; echo; } >>%q\necho fake-output\nexit "${FAKE_EXIT:-0}"\n' "$fx/fake.log" >"$fx/bin/$tool"
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

# The last block of two-space-indented lines on the hook's stderr, without the indent.
printed_replacement() {
    awk '/^  /{ if (!run) block = ""; run = 1; block = block substr($0, 3) "\n"; next } { run = 0 } END { printf "%s", block }' "$tmp/err"
}

# Runs script $4 with shell $2 in the fixture against fakes that exit $3, keeping the calls they
# log in $tmp/$1.log and stdout in $tmp/$1.out. zsh runs with -f so ~/.zshenv cannot put the real
# toolchain ahead of the fakes.
run_in_fixture() {
    local status
    : >"$fx/fake.log"
    (cd "$fx" && PATH="$fx/bin:$PATH" DEVELOPER_DIR="$fx/no-xcode" FAKE_EXIT=$3 $2 -c "$4" >"$tmp/$1.out" 2>/dev/null)
    status=$?
    mv "$fx/fake.log" "$tmp/$1.log"
    return "$status"
}

# Runs the command and its printed replacement between the same caller prelude and postlude, in zsh
# and bash, with the fakes passing and failing, and compares the calls, stdout, and exit status.
replacement_runs() {
    local command=$1 label=$2 prelude=$3 postlude=$4 printed shell code want got reached=
    # These reach the real toolchain past the fakes, so they are judged but never run: a /usr path
    # names it, env -i clears PATH, and a login shell lets path_helper put /usr/bin first.
    case $command in /usr/* | "env -i swift"* | "sh -l"*) return ;; esac
    printed=$(printed_replacement)
    for shell in "/bin/zsh -f" /bin/bash; do
        for code in 0 7; do
            run_in_fixture original "$shell" "$code" "$prelude"$'\n'"$command"$'\n'"$postlude"
            want=$?
            run_in_fixture replacement "$shell" "$code" "$prelude"$'\n'"$printed"$'\n'"$postlude"
            got=$?
            [ -s "$tmp/original.log" ] && reached=1
            if [ "$got" != "$want" ] || ! cmp -s "$tmp/original.log" "$tmp/replacement.log" ||
                ! cmp -s "$tmp/original.out" "$tmp/replacement.out"; then
                bad "$label replacement behaves as written under ${shell%% *} at fake exit $code, exit $got vs $want:"
                diff "$tmp/original.log" "$tmp/replacement.log" | sed 's/^/    log /'
                diff "$tmp/original.out" "$tmp/replacement.out" | sed 's/^/    out /'
                return
            fi
        done
    done
    if [ -n "$reached" ]; then
        ok "$label replacement behaves as written under zsh and bash"
    else
        bad "$label reaches a fake build tool when run as written"
    fi
}

# Judges command $2 against verdict $1. A refusal must print replacement $3 (default: the slot
# before the command) and behave as written between caller prelude $4 and postlude $5.
check() {
    local want=$1 command=$2 replacement=${3-} prelude=${4-} postlude=${5-} got label
    run_hook "$fx" "$command"
    got=$?
    label="$want: ${prelude:+[$prelude] }${command//$'\n'/\\n}${postlude:+ [$postlude]}"
    if [ "$want" = allow ]; then
        if [ "$got" = 0 ]; then ok "$label"; else bad "$label, got exit $got: $(head -3 "$tmp/err")"; fi
        return
    fi
    replacement=${replacement:-@SLOT@ $command}
    replacement=${replacement//@SLOT@/$slot}
    if [ "$got" != 2 ]; then
        bad "$label, got exit $got"
        return
    elif [ "$(printed_replacement)" != "$replacement" ]; then
        bad "$label, stderr lacks the replacement '${replacement//$'\n'/\\n}':"
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
    replacement_runs "$command" "$label" "$prelude" "$postlude"
}

unescape() { local s=${1//\{NL\}/$'\n'}; printf '%s' "${s//\{TAB\}/$'\t'}"; }

echo "the guard, through the settings hook"
while IFS=$'\t' read -r want command replacement; do
    check "$want" "$(unescape "$command")" "$(unescape "$replacement")"
done <<'ROWS'
refuse	swift build
refuse	swift test
refuse	swift test --filter SyncCoordinatorTests
refuse	swift run workout
refuse	swift run workout -- log w1d1.e0.s0 185x5@8
refuse	swift run workout --help
refuse	swift run --repl
refuse	swift run --skip-build --repl
refuse	swift test -Xlinker --skip-build
refuse	swift test -Xswiftc --skip-build
refuse	swift test --filter --skip-build
refuse	swift test -Xswiftc --help
refuse	swift-build -c release
refuse	swift build && swift test	@SLOT@ swift build && @SLOT@ swift test
refuse	swift build --product workout && export PATH="$PWD/.build/debug:$PATH"
refuse	cd Sources && swift test	cd Sources && @SLOT@ swift test
refuse	cd x && swift test; pwd	cd x && @SLOT@ swift test; pwd
refuse	export FOO=1; swift test; echo $FOO	export FOO=1; @SLOT@ swift test; echo $FOO
refuse	FOO=1 swift test	FOO=1 @SLOT@ swift test
refuse	NAME='value with spaces' swift test	NAME='value with spaces' @SLOT@ swift test
refuse	DEVELOPER_DIR='/Applications/Xcode 27.app/Contents/Developer' swift test	DEVELOPER_DIR='/Applications/Xcode 27.app/Contents/Developer' @SLOT@ swift test
refuse	VAR="two words"; swift test --filter $VAR	VAR="two words"; @SLOT@ swift test --filter $VAR
refuse	VAR="local value"; swift test --filter "$VAR"	VAR="local value"; @SLOT@ swift test --filter "$VAR"
refuse	items=(a b); swift test --filter $items[1]	items=(a b); @SLOT@ swift test --filter $items[1]
refuse	items=(one two); swift test --filter "$items[1]"	items=(one two); @SLOT@ swift test --filter "$items[1]"
refuse	swift test --filter "O'Connor" && echo done
refuse	myfn() { echo function; }; myfn && swift test	myfn() { echo function; }; myfn && @SLOT@ swift test
refuse	alias st='echo hi'; st; swift test	alias st='echo hi'; st; @SLOT@ swift test
refuse	set -o pipefail; swift test | cat	set -o pipefail; @SLOT@ swift test | cat
refuse	set -e; swift test; echo after	set -e; @SLOT@ swift test; echo after
refuse	swift test 2>&1 | tail -5
refuse	swift test 2>&1 | cat
refuse	swift test > result.txt; cat result.txt
refuse	swift test --enable-code-coverage > out.txt
refuse	cd x{NL}swift test	cd x{NL}@SLOT@ swift test
refuse	cd Sources{NL}swift test --filter X	cd Sources{NL}@SLOT@ swift test --filter X
refuse	swift test <<'EOF'{NL}payload with 'single' and "double"{NL}EOF
refuse	swift build \{NL}  --product workout
refuse	echo hi # note{NL}swift build	echo hi # note{NL}@SLOT@ swift build
refuse	echo "a <<EOF b"{NL}swift test	echo "a <<EOF b"{NL}@SLOT@ swift test
refuse	perl -e 'alarm 600; exec @ARGV' swift test
refuse	env -i swift build
refuse	env -i PATH="$PATH" swift build
refuse	env FOO=1 swift test
refuse	env -S "swift test"
refuse	nice -n 10 caffeinate -i swift test
refuse	exec swift test	exec @SLOT@ swift test
refuse	exec -a NAME swift test	exec -a NAME @SLOT@ swift test
refuse	command swift test	command @SLOT@ swift test
refuse	time swift test	time @SLOT@ swift test
refuse	bash -c 'swift test'
refuse	sh -lc "cd x && swift build"
refuse	sh -ec "cd x && swift build"
refuse	if swift test; then echo ok; fi	if @SLOT@ swift test; then echo ok; fi
refuse	{ swift test; }	{ @SLOT@ swift test; }
refuse	for x in a; do swift test; done	for x in a; do @SLOT@ swift test; done
refuse	! swift build	! @SLOT@ swift build
refuse	echo ""; swift build	echo ""; @SLOT@ swift build
refuse	git commit --allow-empty -m "" && swift test	git commit --allow-empty -m "" && @SLOT@ swift test
refuse	echo $(swift build)	echo $(@SLOT@ swift build)
refuse	git commit -m "$(cat <<'EOF'{NL}fix: don't{NL}EOF{NL})" && swift test	git commit -m "$(cat <<'EOF'{NL}fix: don't{NL}EOF{NL})" && @SLOT@ swift test
refuse	echo "$(cat <<<'it is')" && swift test	echo "$(cat <<<'it is')" && @SLOT@ swift test
refuse	/usr/bin/xcrun xcodebuild test -scheme X
refuse	xcrun --sdk iphonesimulator xcodebuild build -scheme X
refuse	xcodebuild test -scheme X
refuse	xcodebuild test-without-building -xctestrun f.xctestrun
refuse	xcodebuild build-for-testing -project WorkoutTracker.xcodeproj -scheme WorkoutTracker
refuse	xcodebuild -project P -scheme S
refuse	xcodebuild archive -scheme S
refuse	xcodebuild clean build -scheme S
refuse	scripts/receipt.sh unit -- xcodebuild test -scheme X	scripts/receipt.sh unit -- @SLOT@ xcodebuild test -scheme X
refuse	a=(x $(swift build))	a=(x $(@SLOT@ swift build))
refuse	args=(--filter X) && swift test	args=(--filter X) && @SLOT@ swift test
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
allow	swift test --filter Foo --skip-build
allow	swift run --skip-build workout
allow	echo "&&" swift test
allow	echo ';' swift test
allow	printf "%s\n" ";" "swift" "test"
allow	printf "%s\n" "(" "swift" "test" ")"
allow	text=";swift test;"; echo ${text//;swift test;/x}
allow	printf "%s\n" ${text:-;swift test;}
allow	echo ${text//;swift test;/x}
allow	echo ${text:-";" swift test}
allow	echo "${text:-"a;b"}"; echo ${a:-${b:-;swift test;}}
allow	printf "%s\n" **/*.swift(N)
allow	[[ "$text" == "swift test" ]]
allow	git log --format=$'%s\n'
allow	printf "%s\n" "a \"quoted\" swift test"
allow	echo ${text:-; swift test
allow	echo "$(printf ';'; swift test
allow	scripts/build-slot.sh swift test
allow	./scripts/build-slot.sh xcodebuild build-for-testing -project P
allow	/opt/checkout/scripts/build-slot.sh swift build
allow	bash scripts/build-slot.sh swift test
allow	hostgate run -- swift test
allow	scripts/test-sim.sh unit
allow	scripts/crap.sh gate
allow	scripts/receipt.sh unit -- scripts/build-slot.sh swift test
allow	scripts/receipt.sh unit -- swift test
allow	bash scripts/receipt.sh unit -- swift build
allow	args=(swift test --filter X)
allow	args+=(swift build) && echo "${args[@]}"
allow	local cmd=(xcodebuild build -scheme S) other=(swift test)
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

echo "quoted and substituted operators stay data"
templates=('echo "$(printf %s P)"' 'printf "%s\n" "$(echo P)"' 'git commit -m "$(echo P)"' 'echo `printf %s P`' 'printf %s P' 'echo "$(echo $(printf %s P))"')
payloads=('"&&" swift test' "';' swift test" '";" "swift" "test"' '"(" "swift" "test" ")"' '"a \"quote\"; swift test"'
    "\"\$(printf 'swift test')\"" "'swift test'" '"one" "swift test"')
for template in "${templates[@]}"; do
    for payload in "${payloads[@]}"; do
        check allow "${template%%P*}$payload${template#*P}"
    done
done

echo "the caller's shell state survives the replacement"
while IFS=$'\t' read -r prelude command replacement postlude; do
    [ "$prelude" = - ] && prelude=
    [ "$postlude" = - ] && postlude=
    check refuse "$command" "$replacement" "$prelude" "$postlude"
done <<'ROWS'
preexisting() { echo function-present; }	preexisting && swift test	preexisting && @SLOT@ swift test	-
set -o pipefail	swift test | cat	@SLOT@ swift test | cat	-
set -e	swift test; echo should-not-run	@SLOT@ swift test; echo should-not-run	-
shopt -s expand_aliases 2>/dev/null; alias st='echo hi'	st && swift test	st && @SLOT@ swift test	-
-	cd Sources && swift test	cd Sources && @SLOT@ swift test	pwd
-	swift build --product workout && export REVIEW_EXPORTED=yes	@SLOT@ swift build --product workout && export REVIEW_EXPORTED=yes	echo "${REVIEW_EXPORTED-unset}"
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

echo
printf '%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" = 0 ]
