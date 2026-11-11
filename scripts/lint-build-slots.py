#!/usr/bin/env python3
"""Fail on a heavy build a repo script starts outside a host-wide hostgate slot.

Scans every shell script under scripts/ and .agents/skills/ (a .sh file, or a file whose first line
names bash, sh or zsh). A heavy build is one that compiles: swift build, swift test or swift run
without --skip-build, and an xcodebuild build, build-for-testing, test or archive. An xcodebuild
test-without-building only runs tests and takes no slot. Each one must follow scripts/build-slot.sh
or sim-lock.sh's with_build_slot in the same simple command, which run it through `hostgate run`.
It reads scripts the way scripts/refuse-raw-builds.py reads a Bash command, with the same misses:
a build inside a quoted string, as in sh -c '...', goes unseen. Exits 1 and prints one `error:` line
per finding, or 2 when the root has neither directory."""
from __future__ import annotations

import importlib.machinery
import importlib.util
import os
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
            except ValueError as e:
                yield f"{relative}: cannot read it as shell ({e}), so its builds go unchecked"
                continue
            for offset, words in found:
                line = text.count("\n", 0, offset) + 1
                yield (f"{relative}:{line}: runs {' '.join(words[:2])} outside a host-wide slot; "
                       f"prefix it with scripts/build-slot.sh --as {file.name}")


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
