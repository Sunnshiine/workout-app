#!/usr/bin/env python3
"""Usage: scripts/refuse-raw-builds.py < PreToolUse-JSON
Claude Code's PreToolUse hook for the Bash tool (.claude/settings.json). This Mac is shared by many
agents, and a raw swift build, swift test, swift run, or xcodebuild build takes none of the
host-wide build slots that scripts/build-slot.sh hands out, so it slows every other lane. The guard
reads the hook's JSON on stdin, splits tool_input.command into simple commands, and exits 3 with
the slotted replacement on stderr when one of them is a raw build. The settings hook turns 3 into
the blocking exit 2. Anything it cannot read, it allows with exit 0. Any argument prints this and
exits 2; the hook passes none.
"""
import json
import os
import re
import shlex
import sys

SLOT = "scripts/build-slot.sh"
HEREDOC = re.compile(r"(?<!<)<<(-?)\s*(['\"]?)([A-Za-z_][\w.-]*)\2")
ASSIGNMENT = re.compile(r"^[A-Za-z_]\w*=")
REPO_SCRIPT = re.compile(r"(^|/)scripts/[^/]+$")

# program -> (flags that take a value, flags that only look the program up and run nothing)
WRAPPERS = {
    "env": ({"-u", "-C", "-P", "-S"}, set()),
    "command": (set(), {"-v", "-V"}),
    "exec": ({"-a"}, set()),
    "builtin": (set(), set()),
    "time": ({"-o"}, set()),
    "nice": ({"-n"}, set()),
    "nohup": (set(), set()),
    "caffeinate": ({"-t", "-w"}, set()),
    "xcrun": ({"--sdk", "-sdk", "--toolchain", "-toolchain"}, {"-f", "--find", "-find"}),
}
KEYWORDS = {"!", "{", "}", "if", "then", "else", "elif", "do", "while", "until"}
SHELLS = {"bash", "sh", "zsh"}

XCODEBUILD_ACTIONS = {
    "build", "build-for-testing", "test", "test-without-building", "archive", "analyze",
    "docbuild", "install",
}
XCODEBUILD_TEST_ACTIONS = {"test", "test-without-building", "build-for-testing"}
XCODEBUILD_INFO = (
    "-version", "-showBuildSettings", "-showsdks", "-showdestinations", "-showTestPlans",
    "-showComponent", "-list", "-help", "-usage", "-resolvePackageDependencies", "-exportArchive",
    "-exportLocalizations", "-importLocalizations", "-create-xcframework",
    "-checkFirstLaunchStatus", "-runFirstLaunch", "-downloadPlatform", "-downloadAllPlatforms",
    "-license",
)
XCODEBUILD_VALUED = {
    "-project", "-workspace", "-scheme", "-destination", "-configuration", "-sdk",
    "-derivedDataPath", "-resultBundlePath", "-only-testing", "-skip-testing", "-testPlan",
    "-xctestrun", "-archivePath", "-target", "-arch", "-toolchain", "-xcconfig",
    "-destination-timeout", "-parallel-testing-worker-count",
    "-maximum-concurrent-test-simulator-destinations", "-clonedSourcePackagesDirPath",
    "-packageCachePath", "-exportPath", "-exportOptionsPlist",
}
TEST_SIM_HINT = "Simulator suites go through scripts/test-sim.sh, which leases a simulator and takes a slot."
COVERAGE_HINT = "The coverage gate is scripts/crap.sh gate."


def strip_heredocs(text):
    kept, delimiters = [], []
    for line in text.split("\n"):
        if delimiters:
            if line.strip() == delimiters[0]:
                delimiters.pop(0)
            continue
        kept.append(line)
        delimiters = [m.group(3) for m in HEREDOC.finditer(line)]
    return "\n".join(kept)


def simple_commands(text):
    """Split a shell string into argv lists, dropping redirections and comments."""
    lexer = shlex.shlex(strip_heredocs(text).replace("\\\n", " "), posix=True,
                        punctuation_chars="();<>|&\n")
    lexer.whitespace = " \t\r"
    lexer.whitespace_split = True
    lexer.commenters = ""
    commands, argv, tokens = [], [], list(lexer)
    i, in_comment = 0, False
    while i < len(tokens):
        token = tokens[i]
        is_punct = bool(token) and all(c in "();<>|&\n" for c in token)
        if in_comment and "\n" not in token:
            pass
        elif is_punct and (token in ("&", "&&") or any(c in token for c in ";|()\n")):
            commands.append(argv)
            argv, in_comment = [], False
        elif is_punct:
            if argv and argv[-1].isdigit():
                argv.pop()
            i += 1
        elif token.startswith("#"):
            in_comment = True
        else:
            argv.append(token)
        i += 1
    commands.append(argv)
    return [c for c in commands if c]


def unwrap(name, argv):
    """The argv a wrapper runs, or None when it runs nothing."""
    valued, lookups = WRAPPERS[name]
    i = 1
    while i < len(argv) and (argv[i].startswith("-") or (name == "env" and ASSIGNMENT.match(argv[i]))):
        if argv[i] in lookups:
            return None
        i += 2 if argv[i] in valued else 1
    return argv[i:]


def swift_refusal(argv):
    sub = next((a for a in argv[1:] if not a.startswith("-")), None)
    if sub not in ("build", "test", "run"):
        return None
    return [COVERAGE_HINT] if sub == "test" and "--enable-code-coverage" in argv else []


def xcodebuild_refusal(argv):
    if any(a.startswith(XCODEBUILD_INFO) for a in argv[1:]):
        return None
    words, i = [], 1
    while i < len(argv):
        if argv[i] in XCODEBUILD_VALUED:
            i += 1
        elif not argv[i].startswith("-"):
            words.append(argv[i])
        i += 1
    actions = [w for w in words if w in XCODEBUILD_ACTIONS]
    if not actions and "clean" in words:
        return None
    return [TEST_SIM_HINT] if XCODEBUILD_TEST_ACTIONS.intersection(actions) else []


RULES = {
    "swift": swift_refusal,
    "swift-build": lambda argv: [],
    "swift-test": lambda argv: [],
    "swift-run": lambda argv: [],
    "xcodebuild": xcodebuild_refusal,
}


def refusal(argv):
    """(replacement argv, hint lines) for a raw build, or None to allow."""
    while argv and ASSIGNMENT.match(argv[0]):
        argv = argv[1:]
    if not argv:
        return None
    name = os.path.basename(argv[0])
    if name == "hostgate" and argv[1:2] == ["run"]:
        return None
    if REPO_SCRIPT.search(argv[0]):
        if name == "receipt.sh" and "--" in argv:
            cut = argv.index("--") + 1
            inner = refusal(argv[cut:])
            return inner and (argv[:cut] + inner[0], inner[1])
        return None
    if name in KEYWORDS:
        return refusal(argv[1:])
    if name in WRAPPERS:
        inner = refusal(unwrap(name, argv) or [])
    elif name == "perl":
        code = next((i for i, a in enumerate(argv) if re.fullmatch(r"-\w*[eE]", a)), None)
        inner = None if code is None else refusal(argv[code + 2:])
    elif name in SHELLS:
        flag = next((i for i, a in enumerate(argv[1:], 1) if not a.startswith("-") or re.fullmatch(r"-[a-z]*c[a-z]*", a)), None)
        if flag is not None and argv[flag].startswith("-"):
            inner = first_refusal(argv[flag + 1]) if flag + 1 < len(argv) else None
        else:
            inner = None if flag is None else refusal(argv[flag:])
            if inner and REPO_SCRIPT.search(argv[flag]):
                return argv[:flag] + inner[0], inner[1]
    elif name in RULES:
        hints = RULES[name](argv)
        inner = None if hints is None else ([], hints)
    else:
        return None
    return inner and ([SLOT] + argv, inner[1])


def first_refusal(text):
    return next(filter(None, map(refusal, simple_commands(text))), None)


def refusals(text):
    out = []
    for argv in simple_commands(text):
        found = refusal(argv)
        if found:
            assignments = []
            while ASSIGNMENT.match(argv[len(assignments)]):
                assignments.append(argv[len(assignments)])
            out.append((shlex.join(assignments + found[0]), found[1]))
    return out


def main():
    if len(sys.argv) > 1:
        sys.stderr.write(__doc__)
        return 2
    try:
        found = refusals(json.load(sys.stdin)["tool_input"]["command"])
    except Exception:
        return 0
    if not found:
        return 0
    lines = [
        "Refused: this Mac is shared by many agents, and a raw build takes no host-wide build slot,",
        "so it slows every other lane. Run it through a slot (see scripts/build-slot.sh --help):",
    ]
    for replacement, hints in found:
        lines.append("  " + replacement)
        lines.extend(hints)
    print("\n".join(dict.fromkeys(lines)), file=sys.stderr)
    return 3


if __name__ == "__main__":
    sys.exit(main())
