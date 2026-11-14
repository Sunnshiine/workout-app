#!/usr/bin/env python3
"""Fail on a heavy build a repo script starts outside a host-wide hostgate slot.

Scans every shell script under scripts/ and .agents/skills/ (a .sh file, or a file whose first line
names bash, sh or zsh). A heavy build is one that compiles: swift build, swift test or swift run
without --skip-build, and an xcodebuild build, build-for-testing, test or archive. An xcodebuild
test-without-building only runs tests and takes no slot. Running a .swift file by path, or through
swift FILE.swift, compiles it with swift-frontend too, so it counts: a literal path, or a $name or
${name} the same file assigns a value ending in .swift. Each one must follow scripts/build-slot.sh
or sim-lock.sh's with_build_slot in the same simple command, which run it through `hostgate run`.
A by-path call that must run outside a slot is listed in BY_PATH_EXCEPTIONS with its reason.
It reads scripts the way scripts/refuse-raw-builds.py reads a Bash command, with the same misses:
a build inside a quoted string, as in sh -c '...', goes unseen. Exits 1 and prints one `error:` line
per finding, or 2 when the root has neither directory."""
from __future__ import annotations

import importlib.machinery
import importlib.util
import os
import re
import sys
from pathlib import Path

SCANNED = ("scripts", ".agents/skills")
SLOTTED_BY = {"build-slot.sh", "with_build_slot"}
SHELLS = ("bash", "sh", "zsh")
# Each exception and why. A path ending in / covers its whole tree.
EXCEPTIONS = {
    "scripts/ci/": "runs only on a single-tenant GitHub runner, which has no hostgate and no other agent",
    "scripts/tests/": "fakes and fixtures that feed these commands to the scripts under test",
    ".agents/skills/verify/tests/": "fakes and fixtures that feed these commands to verify.sh",
}
NO_COMPILE_ACTIONS = {"test-without-building"}
# (script, .swift file it runs by path) -> why that call runs outside a slot.
BY_PATH_EXCEPTIONS = {
    ("scripts/contact-sheet.sh", "contact-sheet.swift"):
        "the one fallback when the cached tiler cannot be built, because a contact sheet is never refused",
}
EXPANSION = re.compile(r"^\$\{?([A-Za-z_]\w*)\}?$")


def load_guard():
    path = Path(__file__).with_name("refuse-raw-builds.py")
    loader = importlib.machinery.SourceFileLoader("refuse_raw_builds", str(path))
    spec = importlib.util.spec_from_loader(loader.name, loader)
    module = importlib.util.module_from_spec(spec)
    loader.exec_module(module)
    return module


GUARD = load_guard()


def exempt(relative: str) -> bool:
    return any(relative == path or (path.endswith("/") and relative.startswith(path)) for path in EXCEPTIONS)


def is_shell_script(file: Path) -> bool:
    if file.suffix == ".sh":
        return True
    try:
        with file.open("rb") as handle:
            first = handle.readline(200).decode("utf-8", "replace")
    except OSError:
        return False
    return first.startswith("#!") and os.path.basename(first.split()[-1] if first.split() else "") in SHELLS


def heavy(argv: list[str]) -> bool:
    """True when argv, which starts at a swift or xcodebuild program, compiles."""
    name = os.path.basename(argv[0])
    if name == "xcodebuild":
        if GUARD.xcodebuild_refusal(argv) is None:
            return False
        actions = {a for a in argv[1:] if a in GUARD.XCODEBUILD_ACTIONS}
        return not actions or not actions <= NO_COMPILE_ACTIONS
    return GUARD.swift_refusal(argv) is not None


def unslotted(text: str):
    """(offset, words) of each heavy build in text that no slot wrapper precedes."""
    for argv in GUARD.simple_commands(GUARD.tokens(text)):
        words = [w.text for w in argv]
        for k, word in enumerate(words):
            if os.path.basename(word) in GUARD.RULES:
                if heavy(words[k:]) and not SLOTTED_BY.intersection(os.path.basename(w) for w in words[:k]):
                    yield argv[k].offset, words[k:]
                break


def swift_scripts(toks) -> dict[str, str]:
    """Each variable the text assigns a value ending in .swift, to that value."""
    found = {}
    for kind, text, _ in toks:
        if kind == "word" and GUARD.ASSIGNMENT.match(text):
            name, value = text.split("=", 1)
            if value.endswith(".swift"):
                found[name] = value
    return found


def swift_script(word: str, variables: dict[str, str]) -> str | None:
    """The .swift file word names, as a literal path or an expansion of one, or None."""
    if word.endswith(".swift"):
        return word
    match = EXPANSION.match(word)
    return variables.get(match.group(1)) if match else None


def by_path(argv, variables):
    """(offset, .swift file) when argv runs a .swift file by path outside a slot, else None."""
    while argv:
        name = os.path.basename(argv[0].text)
        if GUARD.ASSIGNMENT.match(argv[0].text) or name in GUARD.KEYWORDS:
            argv = argv[1:]
        elif name in SLOTTED_BY:
            return None
        elif name in GUARD.WRAPPERS:
            argv = GUARD.unwrap(name, argv) or []
        elif name == "perl":
            code = next((i for i, w in enumerate(argv) if re.fullmatch(r"-\w*[eE]", w.text)), None)
            argv = [] if code is None else argv[code + 2:]
        elif name == "swift":
            script = next((w for w in argv[1:] if not w.text.startswith("-")), None)
            target = script and swift_script(script.text, variables)
            return (argv[0].offset, target) if target else None
        else:
            target = swift_script(argv[0].text, variables)
            return (argv[0].offset, target) if target else None
    return None


def without_case_patterns(toks):
    """toks without each case pattern, so a pattern such as *.swift) does not read as a command."""
    out, cases, prev = [], [], None
    for tok in toks:
        kind, text, offset = tok
        leading = prev is None or prev[0] == "op" or prev[1] in GUARD.KEYWORDS
        prev = tok
        if cases and cases[-1] == "pattern":
            if kind == "word" and text == "esac":
                cases.pop()
                out.append(tok)
            elif kind == "op" and text == ")":
                cases[-1] = "body"
                out.append(("op", "\n", offset))
            continue
        if kind == "word" and text == "case" and leading:
            cases.append("head")
        elif kind == "word" and text == "in" and cases and cases[-1] == "head":
            cases[-1] = "pattern"
        elif kind == "op" and text == ";;" and cases:
            cases[-1] = "pattern"
        elif kind == "word" and text == "esac" and leading and cases:
            cases.pop()
        out.append(tok)
    return out


def by_path_calls(text):
    """(offset, .swift file) of each .swift file text runs by path outside a slot."""
    toks = without_case_patterns(GUARD.tokens(text))
    variables = swift_scripts(toks)
    for argv in GUARD.simple_commands(toks):
        found = by_path(argv, variables)
        if found:
            yield found


def findings(root: Path):
    for entry in SCANNED:
        for file in sorted((root / entry).rglob("*")):
            relative = file.relative_to(root).as_posix()
            if not file.is_file() or exempt(relative) or not is_shell_script(file):
                continue
            try:
                text = file.read_text(encoding="utf-8")
            except (UnicodeDecodeError, OSError):
                continue
            try:
                found = list(unslotted(text))
                scripts = [(offset, target) for offset, target in by_path_calls(text)
                           if (relative, os.path.basename(target)) not in BY_PATH_EXCEPTIONS]
            except ValueError as e:
                yield f"{relative}: cannot read it as shell ({e}), so its builds go unchecked"
                continue
            for offset, words in found:
                line = text.count("\n", 0, offset) + 1
                yield (f"{relative}:{line}: runs {' '.join(words[:2])} outside a host-wide slot; "
                       f"prefix it with scripts/build-slot.sh --as {file.name}")
            for offset, target in scripts:
                line = text.count("\n", 0, offset) + 1
                yield (f"{relative}:{line}: runs {target} by path, which compiles it with swift-frontend outside "
                       f"a host-wide slot; run a compiled copy (scripts/contact-sheet.sh does it for the tiler), "
                       f"or list ({relative!r}, {os.path.basename(target)!r}) in BY_PATH_EXCEPTIONS with its reason")


def main(root: Path) -> int:
    if not any((root / entry).is_dir() for entry in SCANNED):
        print(f"error: {root} has neither scripts/ nor .agents/skills/", file=sys.stderr)
        return 2
    found = list(findings(root))
    for line in found:
        print(f"error: {line}")
    return 1 if found else 0


if __name__ == "__main__":
    sys.exit(main(Path(sys.argv[1]) if len(sys.argv) > 1 else Path(".")))
