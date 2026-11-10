#!/usr/bin/env python3
"""Usage: scripts/refuse-raw-builds.py < PreToolUse-JSON
Claude Code's PreToolUse hook for the Bash tool (.claude/settings.json). This Mac is shared by many
agents, and a raw swift build, swift test, swift run, or xcodebuild build takes none of the
host-wide build slots that scripts/build-slot.sh hands out, so it slows every other lane. The guard
reads the hook's JSON on stdin, splits tool_input.command into simple commands, and exits 3 when one
of them is a raw build. The settings hook turns 3 into the blocking exit 2. Anything it cannot read,
it allows with exit 0. Any argument prints this and exits 2; the hook passes none.
The replacement on stderr is the command exactly as written, with scripts/build-slot.sh inserted
before each refused program, so it runs in the caller's own shell with its options, functions,
directory, and variables. A multi-line command prints as a block indented two spaces.
Known misses: builds inside a quoted $(...), inside ${...}, or in backticks; builds that xargs,
make, eval, an alias, or a function body defined elsewhere run; and a case pattern inside $(...),
which miscounts its parentheses and allows.
"""
import json
import os
import re
import shlex
import sys
from typing import NamedTuple

PROJECT = os.environ.get("CLAUDE_PROJECT_DIR")
SLOT = os.path.join(PROJECT, "scripts/build-slot.sh") if PROJECT else "scripts/build-slot.sh"
TEST_SIM = os.path.join(PROJECT, "scripts/test-sim.sh") if PROJECT else "scripts/test-sim.sh"
ASSIGNMENT = re.compile(r"^[A-Za-z_]\w*=")
REPO_SCRIPT = re.compile(r"(^|/)scripts/[^/]+$")

REDIRECTIONS = ["<<<", "<<-", "&>>", "<<", "&>", ">>", "<>", ">&", "<&", ">|", "<", ">"]
SEPARATORS = ["&&", "||", "|&", ";;", ";", "&", "|", "(", ")", "\n"]
OPERATORS = sorted(REDIRECTIONS + SEPARATORS, key=len, reverse=True)
DQUOTE_ESCAPES = '"\\$`'
ANSI_ESCAPES = {"n": "\n", "t": "\t", "r": "\r", "e": "\x1b", "a": "\a", "b": "\b"}
CLOSERS = {"$(": ")", "${": "}", "`": "`"}
HEREDOC = re.compile(r"""(?<!<)<<(?!<)(-?)[ \t]*(['"]?)([^\s'"();&|<>]+)\2""")


class Word(NamedTuple):
    text: str
    offset: int


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
# These run inside the shell, so build-slot.sh cannot exec them; the slot goes before their program.
BUILTINS = {"exec", "builtin", "command", "time"}
KEYWORDS = {"!", "{", "}", "if", "then", "else", "elif", "do", "while", "until"}
SHELLS = {"bash", "sh", "zsh"}

SWIFT_NO_COMPILE = {"--help", "-h", "-help", "--version", "--show-bin-path"}
SWIFT_VALUED = {
    "-Xlinker", "-Xswiftc", "-Xcc", "-Xcxx", "-Xbuild-tools-swiftc", "--package-path", "-C",
    "--scratch-path", "--build-path", "-c", "--configuration", "--product", "--target", "--filter",
    "--skip", "--triple", "--sdk", "--toolchain", "--swift-sdk", "--arch", "-j", "--jobs",
    "--cache-path", "--config-path", "--security-path", "--pkg-config-path", "--num-workers",
    "--xunit-output", "--sanitize",
}
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
    """[(kind, text, offset)] with kind "word" or "op" and offset where it starts in text. Quotes are
    removed; ${...}, backticks, and substitutions inside double quotes stay raw in their word;
    heredoc bodies and comments are skipped. Raises ValueError on anything left unclosed."""
    out, word, start, i, heredocs, delimiter_for = [], None, 0, 0, [], None

    def extend(piece, at):
        nonlocal word, start
        if word is None:
            word, start = "", at
        word += piece

    def end_word():
        nonlocal word, delimiter_for
        if word is not None:
            out.append(("word", word, start))
            if delimiter_for:
                heredocs.append((word, delimiter_for == "<<-"))
            word, delimiter_for = None, None

    while i < len(text):
        c, nxt = text[i], text[i + 1:i + 2]
        if c == "\\":
            if nxt != "\n":
                extend(nxt, i)
            i += 2
        elif c == "'":
            j = text.find("'", i + 1)
            if j < 0:
                raise ValueError("unclosed quote")
            extend(text[i + 1:j], i)
            i = j + 1
        elif c == "$" and nxt == "'":
            extend("", i)
            i += 2
            while text[i:i + 1] != "'":
                if not text[i:]:
                    raise ValueError("unclosed quote")
                if text[i] == "\\":
                    extend(ANSI_ESCAPES.get(text[i + 1:i + 2], text[i + 1:i + 2]), i)
                    i += 2
                else:
                    extend(text[i], i)
                    i += 1
            i += 1
        elif c == '"':
            j = dquote_end(text, i)
            extend(unescape_dquoted(text[i + 1:j - 1]), i)
            i = j
        elif c == "`" or (c == "$" and nxt == "{"):
            j = substitution_end(text, i)
            extend(text[i:j], i)
            i = j
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
            out.append(("op", op, i))
            i += len(op)
            if op in ("<<", "<<-"):
                delimiter_for = op
            if op == "\n":
                i = skip_heredocs(text, i, heredocs)
                heredocs.clear()
        else:
            extend(c, i)
            i += 1
    end_word()
    return out


def dquote_end(text, i):
    """The index just past the double quote that closes the one at i."""
    i += 1
    while i < len(text):
        c = text[i]
        if c == "\\":
            i += 2
        elif c == '"':
            return i + 1
        elif c == "`" or text.startswith(("$(", "${"), i):
            i = substitution_end(text, i)
        else:
            i += 1
    raise ValueError("unclosed quote")


def substitution_end(text, i):
    """The index just past the $(, ${, or backtick at i, through its matching closer."""
    opener = "`" if text[i] == "`" else text[i:i + 2]
    closer, depth, heredocs = CLOSERS[opener], 0, []
    i += len(opener)
    while i < len(text):
        c = text[i]
        if c == "\\":
            i += 2
        elif closer == ")" and (heredoc := HEREDOC.match(text, i)):
            heredocs.append((heredoc.group(3), heredoc.group(1) == "-"))
            i = heredoc.end()
        elif c == "\n" and heredocs:
            i = skip_heredocs(text, i + 1, heredocs)
            heredocs = []
        elif c == closer and depth == 0:
            return i + 1
        elif c == "'":
            j = text.find("'", i + 1)
            if j < 0:
                raise ValueError("unclosed quote")
            i = j + 1
        elif c == '"':
            i = dquote_end(text, i)
        elif closer != "`" and (c == "`" or text.startswith(("$(", "${"), i)):
            i = substitution_end(text, i)
        else:
            depth += (c == "(") - (c == ")") if closer == ")" else 0
            i += 1
    raise ValueError("unclosed substitution")


def unescape_dquoted(raw):
    return re.sub(r"\\\n|\\([\"\\$`])", lambda m: m.group(1) or "", raw)


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
    """The Words of each simple command, without redirections and their targets."""
    commands, argv, skip = [], [], False
    for kind, text, offset in toks:
        if kind == "word":
            if not skip:
                argv.append(Word(text, offset))
            skip = False
        elif text in REDIRECTIONS:
            skip = True
        else:
            commands.append(argv)
            argv = []
    commands.append(argv)
    return [c for c in commands if c]


def nested_refusals(text):
    """The refusals of a nested script, as in sh -c or env -S; one it cannot read refuses nothing."""
    try:
        return refusals(text)
    except ValueError:
        return []


def unwrap(name, argv):
    """The Words a wrapper runs, or None when it runs nothing."""
    valued, lookups = WRAPPERS[name]
    i = 1
    while i < len(argv) and (argv[i].text.startswith("-") or (name == "env" and ASSIGNMENT.match(argv[i].text))):
        flag = argv[i].text
        if flag in lookups:
            return None
        if name == "env" and flag in ("-S", "--split-string"):
            if i + 1 >= len(argv):
                return None
            try:
                split = [Word(text, 0) for kind, text, _ in tokens(argv[i + 1].text) if kind == "word"]
            except ValueError:
                return None
            return split + argv[i + 2:]
        i += 2 if flag in valued else 1
    return argv[i:]


def swift_options(args):
    """(flags, positionals) of a swift argv as (index, arg), with each single-value option's value
    skipped, so a value such as -Xlinker --skip-build is not read as a flag."""
    flags, positionals, i = [], [], 0
    while i < len(args):
        (flags if args[i].startswith("-") else positionals).append((i, args[i]))
        i += 2 if args[i] in SWIFT_VALUED else 1
    return flags, positionals


def swift_refusal(argv):
    name = os.path.basename(argv[0])
    args = argv[1:argv.index("--")] if "--" in argv else argv[1:]
    if name == "swift":
        _, positionals = swift_options(args)
        at, sub = positionals[0] if positionals else (0, None)
        args = args[at + 1:]
    else:
        sub = name[len("swift-"):]
    if sub not in ("build", "test", "run"):
        return None
    flags, positionals = swift_options(args)
    if sub == "run" and positionals:
        flags = [f for f in flags if f[0] < positionals[0][0]]
    flags = {flag for _, flag in flags}
    skips_build = "--skip-build" in flags and not (sub == "run" and "--repl" in flags)
    if SWIFT_NO_COMPILE & flags or (sub != "build" and skips_build):
        return None
    return {COVERAGE} if sub == "test" and "--enable-code-coverage" in flags else set()


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
    """(offset in the text to insert the slot at, kinds) for a raw build, or None to allow."""
    while argv and ASSIGNMENT.match(argv[0].text):
        argv = argv[1:]
    if not argv:
        return None
    head, texts = argv[0], [w.text for w in argv]
    name = os.path.basename(head.text)
    if name == "hostgate" and texts[1:2] == ["run"]:
        return None
    if REPO_SCRIPT.search(head.text):
        if name == "receipt.sh" and "--" in texts:
            return refusal(argv[texts.index("--") + 1:])
        return None
    if name in KEYWORDS:
        return refusal(argv[1:])
    if name in WRAPPERS:
        program = unwrap(name, argv)
        inner = program and refusal(program)
        if name in BUILTINS:
            return inner
    elif name == "perl":
        code = next((i for i, a in enumerate(texts) if re.fullmatch(r"-\w*[eE]", a)), None)
        inner = None if code is None else refusal(argv[code + 2:])
    elif name in SHELLS:
        flag = next((i for i, a in enumerate(texts[1:], 1) if not a.startswith("-") or re.fullmatch(r"-[a-z]*c[a-z]*", a)), None)
        if flag is not None and texts[flag].startswith("-"):
            found = nested_refusals(texts[flag + 1]) if flag + 1 < len(argv) else []
            inner = found and (None, kinds_of(found))
        else:
            inner = None if flag is None else refusal(argv[flag:])
            if inner and REPO_SCRIPT.search(texts[flag]):
                return inner
    elif name in RULES:
        kinds = RULES[name](texts)
        inner = None if kinds is None else (None, kinds)
    else:
        return None
    return inner and (head.offset, inner[1])


def refusals(text):
    return [r for r in map(refusal, simple_commands(tokens(text))) if r]


def kinds_of(found):
    return set().union(*(kinds for _, kinds in found))


def replacement(text):
    """(text with the slot inserted before each raw build, kinds), or None to allow."""
    found = refusals(text)
    if not found:
        return None
    for offset in sorted({offset for offset, _ in found}, reverse=True):
        text = text[:offset] + shlex.quote(SLOT) + " " + text[offset:]
    return text, kinds_of(found)


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
    if "\n" in command:
        lines.append("It is your command with the slot inserted, indented two spaces; drop the indent:")
    lines += ["  " + line for line in command.split("\n")]
    lines += [HINTS[k] for k in (SIM_BUILD, COVERAGE) if k in kinds]
    print("\n".join(lines), file=sys.stderr)
    return 3


if __name__ == "__main__":
    sys.exit(main())
