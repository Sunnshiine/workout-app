#!/usr/bin/env python3
"""Usage: scripts/refuse-raw-builds.py < PreToolUse-JSON
Claude Code's PreToolUse hook for the Bash tool (.claude/settings.json). This Mac is shared by many
agents, and a raw swift build, swift test, swift run, or xcodebuild build takes none of the
host-wide build slots that scripts/build-slot.sh hands out, so it slows every other lane. The guard
reads the hook's JSON on stdin, splits tool_input.command into simple commands, and exits 3 with
one slotted replacement for the whole command on stderr when one of them is a raw build. The
settings hook turns 3 into the blocking exit 2. Anything it cannot read, it allows with exit 0.
Any argument prints this and exits 2; the hook passes none.
Known misses: builds inside a quoted $(...) or backticks, and builds that xargs or make run.
"""
import itertools
import json
import os
import re
import shlex
import sys

PROJECT = os.environ.get("CLAUDE_PROJECT_DIR")
SLOT = os.path.join(PROJECT, "scripts/build-slot.sh") if PROJECT else "scripts/build-slot.sh"
TEST_SIM = os.path.join(PROJECT, "scripts/test-sim.sh") if PROJECT else "scripts/test-sim.sh"
ASSIGNMENT = re.compile(r"^[A-Za-z_]\w*=")
REPO_SCRIPT = re.compile(r"(^|/)scripts/[^/]+$")

REDIRECTIONS = ["<<<", "<<-", "&>>", "<<", "&>", ">>", "<>", ">&", "<&", ">|", "<", ">"]
SEPARATORS = ["&&", "||", "|&", ";;", ";", "&", "|", "(", ")", "\n"]
OPERATORS = sorted(REDIRECTIONS + SEPARATORS, key=len, reverse=True)
# shlex.join would quote these, so a rebuilt argv would not expand them as the original does.
EXPANSIONS = set("$`*?[~{")
DQUOTE_ESCAPES = '"\\$`'
ANSI_ESCAPES = {"n": "\n", "t": "\t", "r": "\r", "e": "\x1b", "a": "\a", "b": "\b"}

# program -> (flags that take a value, flags that only look the program up and run nothing)
WRAPPERS = {
    "env": ({"-u", "-C", "-P"}, set()),
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
BUILTINS = {"exec", "builtin", "command", "time"}
SHELLS = {"bash", "sh", "zsh"}

SWIFT_NO_COMPILE = {"--help", "-h", "-help", "--version", "--show-bin-path"}
XCODEBUILD_ACTIONS = {
    "build", "build-for-testing", "test", "test-without-building", "archive", "analyze",
    "docbuild", "install",
}
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
SIM_TEST, SIM_BUILD, COVERAGE = "sim-test", "sim-build", "coverage"
HINTS = {
    SIM_BUILD: "Simulator suites go through scripts/test-sim.sh, which leases a simulator and takes a slot.",
    COVERAGE: "The coverage gate is scripts/crap.sh gate.",
}


def tokens(text):
    """[(kind, text)] with kind "word" or "op". Quotes are removed; heredoc bodies and comments are
    skipped. Raises ValueError on an unclosed quote."""
    out, word, i, heredocs, delimiter_for = [], None, 0, [], None

    def end_word():
        nonlocal word, delimiter_for
        if word is not None:
            out.append(("word", word))
            if delimiter_for:
                heredocs.append((word, delimiter_for == "<<-"))
            word, delimiter_for = None, None

    while i < len(text):
        c, nxt = text[i], text[i + 1:i + 2]
        if c == "\\":
            word = word if nxt == "\n" else (word or "") + nxt
            i += 2
        elif c == "'":
            j = text.find("'", i + 1)
            if j < 0:
                raise ValueError("unclosed quote")
            word, i = (word or "") + text[i + 1:j], j + 1
        elif c == "$" and nxt == "'":
            word, i = (word or ""), i + 2
            while text[i:i + 1] != "'":
                if not text[i:]:
                    raise ValueError("unclosed quote")
                if text[i] == "\\":
                    word, i = word + ANSI_ESCAPES.get(text[i + 1:i + 2], text[i + 1:i + 2]), i + 2
                else:
                    word, i = word + text[i], i + 1
            i += 1
        elif c == '"':
            word, i = (word or ""), i + 1
            while text[i:i + 1] != '"':
                if not text[i:]:
                    raise ValueError("unclosed quote")
                pair = text[i:i + 2]
                if pair == "\\\n":
                    i += 2
                elif pair[:1] == "\\" and pair[1:] and pair[1] in DQUOTE_ESCAPES:
                    word, i = word + pair[1], i + 2
                else:
                    word, i = word + text[i], i + 1
            i += 1
        elif c in " \t\r":
            end_word()
            i += 1
        elif c == "#" and word is None:
            j = text.find("\n", i)
            i = len(text) if j < 0 else j
        elif op := next((o for o in OPERATORS if text.startswith(o, i)), None):
            if op in REDIRECTIONS and word is not None and word.isdigit():
                word = None
            end_word()
            out.append(("op", op))
            i += len(op)
            if op in ("<<", "<<-"):
                delimiter_for = op
            if op == "\n":
                i = skip_heredocs(text, i, heredocs)
                heredocs.clear()
        else:
            word, i = (word or "") + c, i + 1
    end_word()
    return out


def skip_heredocs(text, i, heredocs):
    for delimiter, strip_tabs in heredocs:
        while i < len(text):
            j = text.find("\n", i)
            j = len(text) if j < 0 else j
            line, i = text[i:j], j + 1
            if (line.lstrip("\t") if strip_tabs else line) == delimiter:
                break
    return i


def simple_commands(toks):
    """The argv of each simple command, without redirections and their targets."""
    commands, argv, skip = [], [], False
    for kind, text in toks:
        if kind == "word":
            if not skip:
                argv.append(text)
            skip = False
        elif text in REDIRECTIONS:
            skip = True
        else:
            commands.append(argv)
            argv = []
    commands.append(argv)
    return [c for c in commands if c]


def words(text):
    return [text for kind, text in tokens(text) if kind == "word"]


def unwrap(name, argv):
    """The argv a wrapper runs, or None when it runs nothing."""
    valued, lookups = WRAPPERS[name]
    i = 1
    while i < len(argv) and (argv[i].startswith("-") or (name == "env" and ASSIGNMENT.match(argv[i]))):
        if argv[i] in lookups:
            return None
        if name == "env" and argv[i] in ("-S", "--split-string"):
            return words(argv[i + 1]) + argv[i + 2:] if i + 1 < len(argv) else None
        i += 2 if argv[i] in valued else 1
    return argv[i:]


def swift_refusal(argv):
    name = os.path.basename(argv[0])
    args = argv[1:argv.index("--")] if "--" in argv else argv[1:]
    sub = name[len("swift-"):] if name != "swift" else next((a for a in args if not a.startswith("-")), None)
    if sub not in ("build", "test", "run"):
        return None
    if name == "swift":
        args = args[args.index(sub) + 1:]
    flags = args
    if sub == "run":
        flags = args[:next((i for i, a in enumerate(args) if not a.startswith("-")), len(args))]
    if SWIFT_NO_COMPILE.intersection(flags) or (sub != "build" and "--skip-build" in flags):
        return None
    return {COVERAGE} if sub == "test" and "--enable-code-coverage" in args else set()


def xcodebuild_refusal(argv):
    if any(a.startswith(XCODEBUILD_INFO) for a in argv[1:]):
        return None
    words_, i = [], 1
    while i < len(argv):
        if argv[i] in XCODEBUILD_VALUED:
            i += 1
        elif not argv[i].startswith("-"):
            words_.append(argv[i])
        i += 1
    actions = XCODEBUILD_ACTIONS.intersection(words_)
    if not actions and "clean" in words_:
        return None
    if actions & {"test", "test-without-building"}:
        return {SIM_TEST}
    return {SIM_BUILD} if "build-for-testing" in actions else set()


RULES = {
    "swift": swift_refusal,
    "swift-build": swift_refusal,
    "swift-test": swift_refusal,
    "swift-run": swift_refusal,
    "xcodebuild": xcodebuild_refusal,
}


def refusal(argv):
    """(replacement argv, kinds) for a raw build, or None to allow."""
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
            found = refusals(argv[flag + 1])[2] if flag + 1 < len(argv) else []
            inner = found and ([], kinds_of(found))
        else:
            inner = None if flag is None else refusal(argv[flag:])
            if inner and REPO_SCRIPT.search(argv[flag]):
                return argv[:flag] + inner[0], inner[1]
    elif name in RULES:
        kinds = RULES[name](argv)
        inner = None if kinds is None else ([], kinds)
    else:
        return None
    return inner and ([SLOT] + argv, inner[1])


def refusals(text):
    """The tokens, the simple commands, and the refusal of each command that is a raw build."""
    toks = tokens(text)
    commands = simple_commands(toks)
    return toks, commands, [r for r in map(refusal, commands) if r]


def kinds_of(found):
    return set().union(*(kinds for _, kinds in found))


def shell_quote(text):
    if "\n" not in text and "\t" not in text:
        return shlex.quote(text)
    escaped = text.replace("\\", "\\\\").replace("'", "\\'").replace("\n", "\\n").replace("\t", "\\t")
    return "$'" + escaped + "'"


def replacement(text):
    """(the command that runs text as written while holding a build slot, kinds), or None to allow."""
    toks, commands, found = refusals(text)
    if not found:
        return None
    lone = len(commands) == 1 and all(kind == "word" or op == "\n" for kind, op in toks)
    assignments = [a.split("=", 1) for a in itertools.takewhile(ASSIGNMENT.match, commands[0])]
    if lone and commands[0][len(assignments)] not in KEYWORDS | BUILTINS and not EXPANSIONS & set(text):
        prefix = [f"{name}={shlex.quote(value)}" for name, value in assignments]
        return " ".join(prefix + [shlex.join(found[0][0])]), kinds_of(found)
    return f"{shlex.quote(SLOT)} bash -c {shell_quote(text.strip())}", kinds_of(found)


def main():
    if len(sys.argv) > 1:
        sys.stderr.write(__doc__)
        return 2
    try:
        found = replacement(json.load(sys.stdin)["tool_input"]["command"])
    except Exception:
        return 0
    if not found:
        return 0
    command, kinds = found
    lines = ["Refused: this Mac is shared by many agents, and a raw build takes no host-wide build slot,"]
    if SIM_TEST in kinds:
        lines += [
            "so it slows every other lane. Run simulator tests through scripts/test-sim.sh, which leases a",
            "simulator and takes a slot (unit, visual, ui, all, or a test ID; see its --help):",
            f"  {shlex.quote(TEST_SIM)} unit",
            "Otherwise run it through a slot (see scripts/build-slot.sh --help):",
        ]
    else:
        lines.append("so it slows every other lane. Run it through a slot (see scripts/build-slot.sh --help):")
    lines.append("  " + command)
    lines += [HINTS[k] for k in (SIM_BUILD, COVERAGE) if k in kinds]
    print("\n".join(lines), file=sys.stderr)
    return 3


if __name__ == "__main__":
    sys.exit(main())
