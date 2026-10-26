#!/usr/bin/env python3
# /// script
# requires-python = ">=3.9"
# dependencies = []
# ///
"""Fail when a branch adds a Swift identifier that spells a word the glossary avoids.

usage: scripts/lint-vocabulary.py [BASE]
       scripts/lint-vocabulary.py --all

Reads the identifiers on the lines this branch adds to Swift files under Sources/, App/,
WorkoutShared/, and WorkoutWidgets/, against the merge-base with BASE (default origin/main),
uncommitted and untracked files included. A moved file's lines are added only where the move edits
them. With --all it reads every line instead, to list what the tree holds. Comments and string
literals are not identifiers, so they are never read.

An identifier spells a phrase when its words, split at case changes and around digits, hold the
phrase's words in order, the last one as written or inflected (s, es, ies, d, ed, ing, a doubled
last letter, a dropped e). So `displayedSessions` spells "displayed session", `e1rmValue` spells
"e1rm", `dictationLogged` spells "dictation log", and `temporal` spells nothing. The phrases are
the [avoid] section of scripts/vocabulary-avoid.txt, the part of the glossary's Avoid lists that
names nothing else in this code. Each must sit on an Avoid list in CONTEXT.md or docs/context/,
which also names the term to use, and must not be words inside a term's own name, or the glossary
contradicts itself.

A name in [kept] spells a phrase but stays, by the operator's choice (P8). A line that uses it gets
a note and passes. A name in [unrelated] spells a phrase but means something else, and a line that
uses it passes silently. Either way the exemption covers only the declarations the tree already
holds: when the branch raises the count of let, var, func, type, enum case, parameter (a wrapped
signature's too), or closure declarations of the name, the added declaration is a new name and
fails. A listed name the tree no longer holds fails too, so the list only shrinks.

Exits 0 when clean, 1 on findings or a list the glossary does not back, 2 when git cannot answer
or BASE is no commit this branch grew from, and 64 on a usage error.
"""
from __future__ import annotations

import functools
import re
import subprocess
import sys
from collections import Counter
from dataclasses import dataclass
from pathlib import Path

LIST = "scripts/vocabulary-avoid.txt"
GLOSSARY = ("CONTEXT.md", "docs/context")
TREES = ("Sources", "App", "WorkoutShared", "WorkoutWidgets")
SPECS = tuple(f"{tree}/*.swift" for tree in TREES)
SECTIONS = ("avoid", "kept", "unrelated")
ENDINGS = ("", "s", "es", "d", "ed", "ing")

NOISE = re.compile(
    r'//[^\n]*|/\*.*?\*/|(#*)"""(?:.|\n)*?"""\1|(#+)"[^\n]*?"\2|"(?:\\.|[^"\\\n])*"',
    re.DOTALL,
)
IDENTIFIER = re.compile(r"\b[A-Za-z_][A-Za-z0-9_]*\b")
WORD = re.compile(r"[A-Z]+(?=[A-Z][a-z]|\d|\b)|[A-Z]?[a-z]+|[A-Z]+|\d+")
HUNK = re.compile(r"^@@ -\d+(?:,\d+)? \+(\d+)(?:,(\d+))? @@")
ENTRY = re.compile(r"^\*\*([^*]+)\*\*")
BOLD = re.compile(r"\*\*([^*]+)\*\*")
AVOID = re.compile(r"\bAvoid:\s*(.*)$")

NAMED = re.compile(
    r"\b(?:let|var|func|class|struct|enum|protocol|actor|typealias|associatedtype|for)\s+\(?\s*([A-Za-z_]\w*)")
ENUM_CASE = re.compile(r"(?:^|[{;])\s*(?:indirect\s+)?case\s+(?!let\b|var\b)(?=[A-Za-z_])")
SIGNATURE = re.compile(r"(?<![.\w])(?:func\b|init[?!]?\s*[(<]|subscript\s*[(<])")
SIGNATURE_END = re.compile(r"->|\{")
PARAMETER = re.compile(r"[(,]\s*(?:[A-Za-z_]\w*\s+)?([A-Za-z_]\w*)\s*:(?!:)")
PARENS = re.compile(r"\([^()]*\)")
CLOSURE = re.compile(r"\{\s*\(?\s*([A-Za-z_][\w\s,:.?\[\]<>]*?)\)?\s+in\b")


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


def inflects(word: str, stem: str) -> bool:
    return (any(word in (stem + ending, stem + stem[-1] + ending) for ending in ENDINGS)
            or (stem.endswith("y") and word == stem[:-1] + "ies")
            or (stem.endswith("e") and word == stem[:-1] + "ing"))


def spells(identifier_words: tuple[str, ...], phrase: tuple[str, ...]) -> bool:
    k = len(phrase)
    return any(identifier_words[i:i + k - 1] == phrase[:-1] and inflects(identifier_words[i + k - 1], phrase[-1])
               for i in range(len(identifier_words) - k + 1))


def contains(haystack: tuple[str, ...], needle: tuple[str, ...]) -> bool:
    k = len(needle)
    return any(haystack[i:i + k] == needle for i in range(len(haystack) - k + 1))


def depth_after(text: str, depth: int = 0) -> tuple[int, int]:
    """The paren depth at the end of text, starting from depth, and where it first returns to 0."""
    for at, char in enumerate(text):
        depth += (char == "(") - (char == ")")
        if depth == 0 and char == ")":
            return 0, at
    return depth, len(text)


def declared(line: str) -> tuple[list[str], int]:
    """The names a line of code declares (bindings, functions, types, enum cases, parameters, and
    closure parameters), and the paren depth of a signature or enum case it leaves open."""
    names = NAMED.findall(line)
    still_open = 0
    case = ENUM_CASE.search(line)
    if case:
        rest = line[case.end():]
        names += PARAMETER.findall(rest)
        still_open = depth_after(rest)[0]
        while PARENS.search(rest):
            rest = PARENS.sub("", rest)
        names += [m.group() for piece in rest.split(",") if (m := IDENTIFIER.search(piece))]
    signature = SIGNATURE.search(line)
    if signature:
        rest = line[signature.end() - 1:]
        end = SIGNATURE_END.search(rest)
        head = rest[:end.start()] if end else rest
        names += PARAMETER.findall(head)
        still_open = depth_after(head)[0]
    for closure in CLOSURE.finditer(line):
        names += [m.group() for piece in closure.group(1).split(",") if (m := IDENTIFIER.search(piece))]
    return names, still_open


def declared_lines(lines: list[str]) -> list[list[str]]:
    """What each line declares. A line inside a signature or enum case that an earlier line opened
    declares the parameters it holds before the list closes."""
    found, open_depth = [], 0
    for line in lines:
        names, still_open = declared(line)
        if open_depth:
            open_depth, close = depth_after(line, open_depth)
            names += PARAMETER.findall("," + line[:close])
        found.append(names)
        open_depth = open_depth or still_open
    return found


def git(root: Path, *args: str, no_match: int | None = None, stdin: bytes | None = None):
    """git's stdout as text, or as bytes when stdin is given."""
    try:
        done = subprocess.run(["git", "-c", "core.quotePath=false", *args], cwd=root, input=stdin,
                              capture_output=True, text=stdin is None)
    except OSError as error:
        raise Unanswered(f"git {args[0]} failed: {error}") from None
    if done.returncode == no_match:
        return ""
    if done.returncode != 0:
        stderr = done.stderr if stdin is None else done.stderr.decode("utf-8", "replace")
        first = next((line for line in stderr.splitlines() if line.strip()), "no output")
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


def fork_of(root: Path, base: str) -> str:
    try:
        return git(root, "merge-base", base, "HEAD").strip()
    except Unanswered as error:
        raise Unanswered(f"{error}. '{base}' is no commit this branch grew from.") from None


def added_lines(root: Path, fork: str | None) -> dict[str, set[int] | None]:
    """Each changed Swift file under TREES, mapped to its added line numbers (None: every line)."""
    if fork is None:
        return {p: None for p in git(root, "ls-files", "--cached", "--others", "--exclude-standard",
                                     "--", *SPECS).splitlines() if (root / p).is_file()}
    changed: dict[str, set[int] | None] = {}
    lines: set[int] = set()
    diff = git(root, "diff", "-U0", "-M", "--diff-filter=d", "--no-color", "--no-ext-diff",
               "--src-prefix=a/", "--dst-prefix=b/", fork, "--", *SPECS)
    for line in diff.splitlines():
        if line.startswith("+++ b/"):
            lines = changed.setdefault(line[len("+++ b/"):], set())
        elif hunk := HUNK.match(line):
            start, count = int(hunk.group(1)), int(hunk.group(2) or 1)
            lines.update(range(start, start + count))
    for path in git(root, "ls-files", "--others", "--exclude-standard", "--", *SPECS).splitlines():
        changed[path] = None
    return changed


def listed_names_in(root: Path, names: set[str], fork: str | None) -> dict[str, str]:
    """The text of every Swift file under TREES that holds one of the names, at the fork or, with
    fork None, in the working tree."""
    patterns = [arg for name in sorted(names) for arg in ("-e", name)]
    if fork is None:
        paths = git(root, "grep", "-l", "--untracked", "-w", "-F", *patterns, "--", *SPECS,
                    no_match=1).splitlines()
        return {p: (root / p).read_text(encoding="utf-8") for p in paths if (root / p).is_file()}
    blobs = git(root, "grep", "-l", "-w", "-F", *patterns, fork, "--", *SPECS, no_match=1).splitlines()
    if not blobs:
        return {}
    out = git(root, "cat-file", "--batch", stdin=("\n".join(blobs) + "\n").encode("utf-8"))
    texts, at = {}, 0
    for blob in blobs:
        header_end = out.index(b"\n", at)
        size = int(out[at:header_end].split()[2])
        start = header_end + 1
        texts[blob.split(":", 1)[1]] = out[start:start + size].decode("utf-8")
        at = start + size + 1
    return texts


def declarations(texts: dict[str, str], names: set[str]) -> tuple[Counter, set[str]]:
    """How many times the files declare each name, and which names their code uses at all."""
    count: Counter = Counter()
    used: set[str] = set()
    for text in texts.values():
        lines = code_lines(text)
        for line, declares in zip(lines, declared_lines(lines)):
            used.update(names.intersection(IDENTIFIER.findall(line)))
            count.update(name for name in declares if name in names)
    return count, used


def times(n: int) -> str:
    return f"{n} time" if n == 1 else f"{n} times"


def main(argv: list[str]) -> int:
    args = argv[1:]
    if len(args) > 1 or (args and args[0].startswith("-") and args[0] != "--all"):
        print(__doc__.strip().splitlines()[2], file=sys.stderr)
        return 64
    whole_tree = args == ["--all"]
    base = None if whole_tree else (args[0] if args else "origin/main")
    try:
        root = Path(git(Path.cwd(), "rev-parse", "--show-toplevel").strip())
        fork = None if base is None else fork_of(root, base)
        changed = added_lines(root, fork)
        problems: list[str] = []
        try:
            sections = read_list(root)
        except (OSError, ValueError) as error:
            print(f"error: {error}", file=sys.stderr)
            return 1
        listed = {name: section for section in ("kept", "unrelated") for _, name in sections[section]}
        now, used = declarations(listed_names_in(root, set(listed), None), set(listed))
        before = declarations(listed_names_in(root, set(listed), fork), set(listed))[0] if fork else now
    except Unanswered as error:
        print(f"error: {error}", file=sys.stderr)
        print("       The vocabulary check cannot finish, so it fails rather than pass unchecked.",
              file=sys.stderr)
        return 2
    avoided = phrases(root, sections, problems)
    for section in ("kept", "unrelated"):
        for number, name in sections[section]:
            if not any(spells(words(name), p.words) for p in avoided):
                problems.append(f"{LIST}:{number}: {section} name {name} spells no [avoid] phrase. Delete it.")
            elif name not in used:
                problems.append(f"{LIST}:{number}: {section} name {name} is gone from the Swift this check "
                                f"reads. Delete it, so the list only shrinks.")
    spelled = functools.lru_cache(maxsize=None)(
        lambda name: next((p for p in avoided if spells(words(name), p.words)), None))
    notes, failures, checked = [], [], 0
    for path, wanted in sorted(changed.items()):
        lines = code_lines((root / path).read_text(encoding="utf-8"))
        for number, (line, declares) in enumerate(zip(lines, declared_lines(lines)), 1):
            if wanted is not None and number not in wanted:
                continue
            checked += 1
            new = {name for name in declares if now[name] > before[name]}
            for name in dict.fromkeys(IDENTIFIER.findall(line)):
                phrase = spelled(name)
                if phrase is None:
                    continue
                said = (f"spells \"{phrase.text}\", which {phrase.entry_file} avoids for {phrase.term}.")
                section = listed.get(name)
                if section is None:
                    failures.append(f"{path}:{number}: {name} {said} Name it with the glossary's word.")
                elif name in new:
                    failures.append(
                        f"{path}:{number}: {name} declares the {section} name anew (the tree declared it "
                        f"{times(before[name])}, now {now[name]}), and it {said} Name it with the "
                        f"glossary's word.")
                elif section == "kept":
                    notes.append(f"note: {path}:{number}: {name} {said} It is a kept name, so this line "
                                 f"passes. A new name must use the glossary's word.")
    for line in notes + failures + problems:
        print(line)
    scope = "every line" if whole_tree else f"the lines added since {base}"
    print(f"{checked} lines read ({scope}), {len(failures)} names fail, {len(notes)} kept names noted, "
          f"{len(problems)} list problems")
    return 1 if failures or problems else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
