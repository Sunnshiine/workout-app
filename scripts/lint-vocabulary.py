#!/usr/bin/env python3
# /// script
# requires-python = ">=3.9"
# dependencies = []
# ///
"""Fail when a branch adds a Swift identifier that spells a word the glossary avoids.

usage: scripts/lint-vocabulary.py [BASE]
       scripts/lint-vocabulary.py --all

Reads the identifiers on the lines this branch adds to Swift files under Sources/ and App/, against
the merge-base with BASE (default origin/main), uncommitted and untracked files included. With
--all it reads every line instead, to list what the tree holds. Comments and string literals are
not identifiers, so they are never read.

An identifier spells a phrase when its camelCase words contain the phrase's words in order, the
last one allowed up to three more letters, so `displayedSessions` spells "displayed session" and
`conflicted` spells "conflict". The phrases are the [avoid] section of scripts/vocabulary-avoid.txt,
the part of the glossary's Avoid lists that names nothing else in this code. Each must sit on an
Avoid list in CONTEXT.md or docs/context/, which also names the term to use, and must not be words
inside a term's own name, or the glossary contradicts itself.

A name in [kept] spells a phrase but stays, by the operator's choice (P8): a line that uses it gets
a note and passes, while a new name that spells the phrase fails. A kept name the tree no longer
holds fails, so the list only shrinks. A name in [unrelated] spells a phrase but means something
else, and passes silently.

Exits 0 when clean, 1 on findings or a list the glossary does not back, 2 when git cannot answer
or BASE is no commit this branch grew from, and 64 on a usage error.
"""
from __future__ import annotations

import functools
import re
import subprocess
import sys
from dataclasses import dataclass
from pathlib import Path

LIST = "scripts/vocabulary-avoid.txt"
GLOSSARY = ("CONTEXT.md", "docs/context")
TREES = ("Sources", "App")
SECTIONS = ("avoid", "kept", "unrelated")
EXTRA_LETTERS = 3

NOISE = re.compile(
    r'//[^\n]*|/\*.*?\*/|(#*)"""(?:.|\n)*?"""\1|(#+)"[^\n]*?"\2|"(?:\\.|[^"\\\n])*"',
    re.DOTALL,
)
IDENTIFIER = re.compile(r"\b[A-Za-z_][A-Za-z0-9_]*\b")
WORD = re.compile(r"[A-Z]+(?=[A-Z][a-z]|\d|\b)|[A-Z]?[a-z]+|[A-Z]+|\d+[A-Za-z]*")
HUNK = re.compile(r"^@@ -\d+(?:,\d+)? \+(\d+)(?:,(\d+))? @@", re.MULTILINE)
ENTRY = re.compile(r"^\*\*([^*]+)\*\*")
BOLD = re.compile(r"\*\*([^*]+)\*\*")
AVOID = re.compile(r"\bAvoid:\s*(.*)$")


class Unanswered(Exception):
    pass


@dataclass(frozen=True)
class Phrase:
    text: str
    words: tuple[str, ...]
    term: str
    entry_file: str


def words(text: str) -> tuple[str, ...]:
    return tuple(w.lower() for w in WORD.findall(text.replace("_", " ")))


def spells(identifier_words: tuple[str, ...], phrase: tuple[str, ...]) -> bool:
    k = len(phrase)
    for i in range(len(identifier_words) - k + 1):
        window = identifier_words[i:i + k]
        last = window[-1]
        if (window[:-1] == phrase[:-1] and last.startswith(phrase[-1])
                and len(last) <= len(phrase[-1]) + EXTRA_LETTERS):
            return True
    return False


def contains(haystack: tuple[str, ...], needle: tuple[str, ...]) -> bool:
    k = len(needle)
    return any(haystack[i:i + k] == needle for i in range(len(haystack) - k + 1))


def git(root: Path, *args: str, no_match: int | None = None) -> str:
    try:
        done = subprocess.run(["git", "-c", "core.quotePath=false", *args], cwd=root,
                              capture_output=True, text=True)
    except OSError as error:
        raise Unanswered(f"git {args[0]} failed: {error}") from None
    if done.returncode == no_match:
        return ""
    if done.returncode != 0:
        first = next((line for line in done.stderr.splitlines() if line.strip()), "no output")
        raise Unanswered(f"git {' '.join(args)} exited {done.returncode}: {first}")
    return done.stdout


def read_list(root: Path) -> dict[str, list[tuple[int, str]]]:
    sections: dict[str, list[tuple[int, str]]] = {name: [] for name in SECTIONS}
    current = None
    for number, raw in enumerate((root / LIST).read_text(encoding="utf-8").splitlines(), 1):
        line = raw.split("#", 1)[0].strip()
        if not line:
            continue
        if line.startswith("[") and line.endswith("]"):
            current = line[1:-1]
            if current not in sections:
                raise ValueError(f"{LIST}:{number}: [{current}] is no section; use {', '.join(SECTIONS)}.")
        elif current is None:
            raise ValueError(f"{LIST}:{number}: '{line}' sits above the first section.")
        else:
            sections[current].append((number, line))
    return sections


def glossary(root: Path) -> tuple[list[tuple[str, str, tuple[str, ...]]], list[tuple[str, ...]]]:
    """Each Avoid list as (term, file, words), and every bolded term name's words."""
    files = [root / GLOSSARY[0], *sorted((root / GLOSSARY[1]).glob("*.md"))]
    avoids, names = [], []
    for path in files:
        if not path.is_file():
            continue
        relative = path.relative_to(root).as_posix()
        for line in path.read_text(encoding="utf-8").splitlines():
            names.extend(words(name) for name in BOLD.findall(line))
            entry, avoid = ENTRY.match(line), AVOID.search(line)
            if entry and avoid:
                avoids.append((entry.group(1), relative, words(avoid.group(1))))
    return avoids, names


def phrases(root: Path, sections, problems: list[str]) -> list[Phrase]:
    avoids, names = glossary(root)
    found = []
    for number, text in sections["avoid"]:
        phrase = words(text)
        where = f"{LIST}:{number}"
        inside = next((n for n in names if contains(n, phrase)), None)
        backing = next((a for a in avoids if contains(a[2], phrase)), None)
        if inside is not None:
            problems.append(
                f"{where}: \"{text}\" is words inside the glossary term \"{' '.join(inside)}\", so a "
                f"real name would fail. Reword that Avoid list or drop the phrase.")
        elif backing is None:
            problems.append(
                f"{where}: \"{text}\" is on no Avoid list in CONTEXT.md or docs/context/. Add it "
                f"there first, or drop it.")
        else:
            found.append(Phrase(text, phrase, backing[0], backing[1]))
    return found


def code_lines(text: str) -> list[str]:
    stripped = NOISE.sub(lambda m: re.sub(r"[^\n]", " ", m.group()), text)
    return stripped.split("\n")


def added_lines(root: Path, base: str | None) -> dict[str, set[int] | None]:
    """Each changed Swift file under TREES, mapped to its added line numbers (None: every line)."""
    specs = [f"{tree}/*.swift" for tree in TREES]
    if base is None:
        return {p: None for p in git(root, "ls-files", "--cached", "--others", "--exclude-standard",
                                     "--", *specs).splitlines() if (root / p).is_file()}
    try:
        fork = git(root, "merge-base", base, "HEAD").strip()
    except Unanswered as error:
        raise Unanswered(f"{error}. '{base}' is no commit this branch grew from.") from None
    changed: dict[str, set[int] | None] = {}
    for path in git(root, "diff", "--name-only", "--diff-filter=d", fork, "--", *specs).splitlines():
        lines = set()
        for start, count in HUNK.findall(git(root, "diff", "-U0", "--no-renames", fork, "--", path)):
            lines.update(range(int(start), int(start) + (int(count) if count else 1)))
        changed[path] = lines
    for path in git(root, "ls-files", "--others", "--exclude-standard", "--", *specs).splitlines():
        changed[path] = None
    return changed


def main(argv: list[str]) -> int:
    args = argv[1:]
    if len(args) > 1 or (args and args[0].startswith("-") and args[0] != "--all"):
        print(__doc__.strip().splitlines()[2], file=sys.stderr)
        return 64
    whole_tree = args == ["--all"]
    base = None if whole_tree else (args[0] if args else "origin/main")
    try:
        root = Path(git(Path.cwd(), "rev-parse", "--show-toplevel").strip())
        changed = added_lines(root, base)
    except Unanswered as error:
        print(f"error: {error}", file=sys.stderr)
        print("       The vocabulary check cannot finish, so it fails rather than pass unchecked.",
              file=sys.stderr)
        return 2
    problems: list[str] = []
    try:
        sections = read_list(root)
    except (OSError, ValueError) as error:
        print(f"error: {error}", file=sys.stderr)
        return 1
    avoided = phrases(root, sections, problems)
    kept = {name for _, name in sections["kept"]}
    unrelated = {name for _, name in sections["unrelated"]}
    for number, name in sections["kept"]:
        if not any(spells(words(name), p.words) for p in avoided):
            problems.append(f"{LIST}:{number}: kept name {name} spells no [avoid] phrase. Delete it.")
        elif not git(root, "grep", "-l", "-w", "-F", name, "--", *TREES, no_match=1).strip():
            problems.append(
                f"{LIST}:{number}: kept name {name} is gone from {' and '.join(t + '/' for t in TREES)}. Delete it, "
                f"so the list only shrinks.")
    spelled = functools.lru_cache(maxsize=None)(
        lambda name: next((p for p in avoided if spells(words(name), p.words)), None))
    notes, failures, checked = [], [], 0
    for path, wanted in sorted(changed.items()):
        lines = code_lines((root / path).read_text(encoding="utf-8"))
        for number, line in enumerate(lines, 1):
            if wanted is not None and number not in wanted:
                continue
            checked += 1
            for name in dict.fromkeys(IDENTIFIER.findall(line)):
                if name in unrelated:
                    continue
                phrase = spelled(name)
                if phrase is None:
                    continue
                said = (f"{path}:{number}: {name} spells \"{phrase.text}\", which {phrase.entry_file} "
                        f"avoids for {phrase.term}.")
                if name in kept:
                    notes.append(f"note: {said} It is a kept name, so this line passes. A new name "
                                 f"must use the glossary's word.")
                else:
                    failures.append(f"{said} Name it with the glossary's word.")
    for line in notes + failures + problems:
        print(line)
    scope = "every line" if whole_tree else f"the lines added since {base}"
    print(f"{checked} lines read ({scope}), {len(failures)} names fail, {len(notes)} kept names noted, "
          f"{len(problems)} list problems")
    return 1 if failures or problems else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
