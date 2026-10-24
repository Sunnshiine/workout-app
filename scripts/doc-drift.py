#!/usr/bin/env python3
"""List the doc lines that name a file this branch split or moved, so a reviewer reads each one.

usage: scripts/doc-drift.py [BASE]

Compares HEAD with its merge-base with BASE (default origin/main). A file moved when at least half
of the lines it lost reappear in other files the branch added to, as when a test is split into
parts or a doc into area files. A doc that still names it may now point at one part of what it
describes. A shell script whose lines went into a helper it sources stays the entry point, so it
is not listed. The docs read are the ones scripts/lint-doc-symbols.py checks, minus the lines this
branch added. A doc names the file by its path, or by its bare name when no other tracked file
shares that name or the doc sits beside it.

Advisory: it cannot tell a stale pointer from a sound one, so it always exits 0 after a listing,
and 2 on a usage error.
"""
from __future__ import annotations

import fnmatch
import importlib.util
import os
import re
import subprocess
import sys
from collections import defaultdict

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
MIN_MOVED_LINES = 15
MIN_MOVED_SHARE = 0.5
HUNK = re.compile(r"@@ -\d+(?:,\d+)? \+(\d+)(?:,\d+)? @@")


def git(*args: str) -> str:
    return subprocess.run(["git", "-C", ROOT, *args], capture_output=True, text=True, check=True).stdout


def doc_scope() -> tuple[tuple[str, ...], tuple[str, ...]]:
    spec = importlib.util.spec_from_file_location("doc_symbols", os.path.join(ROOT, "scripts/lint-doc-symbols.py"))
    module = importlib.util.module_from_spec(spec)
    sys.modules[spec.name] = module
    spec.loader.exec_module(module)
    return module.DOC_SCOPE, module.HISTORY


def parse_diff(text: str):
    removed: dict[str, list[str]] = defaultdict(list)
    added: dict[str, list[str]] = defaultdict(list)
    added_at: dict[str, set[int]] = defaultdict(set)
    old = new = None
    line_no = 0
    for line in text.splitlines():
        if line.startswith("--- "):
            old = line[6:] if line.startswith("--- a/") else None
        elif line.startswith("+++ "):
            new = line[6:] if line.startswith("+++ b/") else None
        elif line.startswith("@@"):
            line_no = int(HUNK.match(line).group(1))
        elif line.startswith("-") and old:
            removed[old].append(line[1:].strip())
        elif line.startswith("+") and new:
            added[new].append(line[1:].strip())
            added_at[new].add(line_no)
            line_no += 1
    return removed, added, added_at


def sources(path: str, target: str) -> bool:
    try:
        text = open(os.path.join(ROOT, path)).read()
    except OSError:
        return False
    name = re.escape(os.path.basename(target))
    return re.search(rf"^\s*(\.|source)\s.*{name}\b", text, re.M) is not None


def moves(removed, added) -> dict[str, list[str]]:
    found = {}
    for path, lines in removed.items():
        body = [line for line in lines if len(line) > 20]
        if len(body) < MIN_MOVED_LINES:
            continue
        homes = {other: set(other_lines) for other, other_lines in added.items() if other != path}
        landed = [line for line in body if any(line in home for home in homes.values())]
        if len(landed) < MIN_MOVED_SHARE * len(body):
            continue
        targets = sorted(other for other, home in homes.items() if any(line in home for line in landed))
        if not path.endswith(".sh") or not all(sources(path, target) for target in targets):
            found[path] = targets
    return found


def spellings(path: str, doc: str, tracked: list[str]) -> set[str]:
    """The full path, plus the bare file name when it can mean only this file from that doc."""
    name = os.path.basename(path)
    unique = sum(1 for f in tracked if os.path.basename(f) == name) == 1
    sibling = os.path.join(os.path.dirname(doc), name) == path
    return {path, name} if unique or sibling else {path}


def names(line: str, spelled: set[str]) -> bool:
    return any(re.search(rf"(?<![\w./-]){re.escape(name)}(?![\w-])", line) for name in spelled)


def main(argv: list[str]) -> int:
    if len(argv) > 1 or (argv and argv[0].startswith("-")):
        print(__doc__.strip(), file=sys.stderr)
        return 2
    base = argv[0] if argv else "origin/main"
    try:
        merge_base = git("merge-base", base, "HEAD").strip()
    except subprocess.CalledProcessError:
        print(f"doc-drift: {base} does not resolve, or shares no history with HEAD.", file=sys.stderr)
        return 2
    removed, added, added_at = parse_diff(git("diff", "--unified=0", "--no-renames", merge_base, "HEAD"))
    moved = moves(removed, added)
    if not moved:
        return 0
    scope, history = doc_scope()
    tracked = git("ls-files").splitlines()
    docs = [
        f for f in tracked
        if any(fnmatch.fnmatchcase(f, pattern) for pattern in scope) and not f.startswith(history)
    ]
    for path, targets in sorted(moved.items()):
        hits = []
        for doc in docs:
            if doc == path or doc in targets:
                continue
            spelled = spellings(path, doc, tracked)
            with open(os.path.join(ROOT, doc)) as handle:
                for number, line in enumerate(handle, 1):
                    if number not in added_at.get(doc, ()) and names(line, spelled):
                        hits.append(f"  {doc}:{number}: {line.strip()}")
        if hits:
            print(f"{path} moved lines into {', '.join(targets)}. Check that each line still points at the right part:")
            print("\n".join(hits))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
