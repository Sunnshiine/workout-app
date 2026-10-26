#!/usr/bin/env python3
# /// script
# requires-python = ">=3.9"
# dependencies = []
# ///
"""Fail when a change adds a defaulted parameter that lets a caller skip a decision.

usage: scripts/lint-defaults.py [ROOT]
       scripts/lint-defaults.py --write-baseline [ROOT]
       scripts/lint-defaults.py --base REV [--rev REV] [ROOT]

Reads the Swift files under Sources/ and App/ and lists two kinds of default. One is a defaulted
parameter of a func, init, or subscript. The other is a struct's stored `var` with a default, or an
Optional `var` with none, when the struct declares no init in its body, because the synthesized
memberwise init hands that default to every caller. Only a default whose value is nil, true or
false, a closure, Date() or .now, a number, or an empty collection or string counts. A case or any
other expression is left out, since most of those inject a production service.

Each default is keyed `Type|function|label|kind`, with no path or line, so moving code between
files changes no key. A memberwise default's function is `init`. A default whose line carries a
`// default: <reason>` comment is accepted and never keyed. scripts/lint-exemptions.py checks any
issue that reason cites.

With no option, the keys in the working tree are compared with scripts/lint-defaults-baseline.txt,
counting repeats. A key the tree has more often than the baseline is a new default and fails. A key
the baseline has more often than the tree also fails, so a removed default cannot come back
unnoticed. --write-baseline rewrites the baseline from the tree, for a rename or a removal.
--base REV takes the baseline from the keys at REV instead, and --rev REV reads REV's tree instead
of the working tree, so a past commit can be replayed against its merge base. Neither reads the
baseline file, and neither fails on a removed key.

Exits 0 when clean, 1 on findings, 2 when git or the baseline cannot answer, and 64 on a usage
error.
"""
from __future__ import annotations

import os
import re
import subprocess
import sys
from collections import Counter
from dataclasses import dataclass
from pathlib import Path

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from swift_lex import DEFAULT_REASON, lex

TREES = ("Sources", "App")
BASELINE = "scripts/lint-defaults-baseline.txt"
KINDS = {"nil", "bool", "closure", "now", "number", "empty"}
SIGNATURE = re.compile(
    r"(?<![.\w])(?:func\s+([A-Za-z_]\w*|[^\s(<]+)|(init)[?!]?|(subscript))\s*(?:<[^(){}]*>)?\s*\("
)
TYPE = re.compile(r"\b(struct|class|enum|actor|extension|protocol)\s+([A-Za-z_][\w.]*)")
NOT_A_TYPE = {"func", "var", "let", "subscript", "init", "override", "final"}
STORED_VAR = re.compile(
    r"[ \t]*(?:(?:public|internal|package)\s+)?var\s+(\w+)\s*(?::\s*([^={]+?))?\s*(?:=\s*(.*?))?\s*(\{.*)?$"
)
OPEN, CLOSE = "([{", ")]}"


@dataclass(frozen=True)
class Default:
    path: str
    line: int
    type: str
    function: str
    label: str
    name: str
    value: str
    kind: str

    @property
    def key(self) -> str:
        return f"{self.type}|{self.function}|{self.label}|{self.kind}"

    def describe(self) -> str:
        owner = f"{self.type}.{self.function}" if self.type else self.function
        return f"{self.path}:{self.line}: new {self.kind} default, {owner} {self.name} = {self.value}"


class Unanswered(Exception):
    pass


def kind_of(value: str) -> str:
    v = value.strip()
    if v == "nil":
        return "nil"
    if v in ("true", "false"):
        return "bool"
    if v.startswith("{"):
        return "closure"
    if re.fullmatch(r"Date\(\)|Date\.now|\.now", v):
        return "now"
    if v in ("[]", "[:]", '""') or re.fullmatch(r"\.?(empty|init\(\))", v):
        return "empty"
    if re.fullmatch(r"-?[\d_.]+", v):
        return "number"
    if re.fullmatch(r"\.[a-z]\w*", v):
        return "case"
    return "expr"


def closing(text: str, start: int) -> int:
    """Returns the index just past the bracket that closes the one before `start`."""
    i, depth = start, 1
    while i < len(text) and depth:
        if text[i] in OPEN:
            depth += 1
        elif text[i] in CLOSE:
            depth -= 1
        i += 1
    return i


@dataclass(frozen=True)
class Scope:
    kind: str
    name: str
    start: int
    end: int


def scopes(text: str) -> list[Scope]:
    """Every type and extension body, named as Swift qualifies it: Outer.Inner for a nested type,
    and the extended name for an extension."""
    found: list[Scope] = []
    for m in TYPE.finditer(text):
        if m.group(2) in NOT_A_TYPE:
            continue
        brace = text.find("{", m.end())
        if brace < 0:
            continue
        found.append(Scope(m.group(1), m.group(2).split("<")[0], brace + 1, closing(text, brace + 1)))
    named: list[Scope] = []
    for s in found:
        outer = enclosing(named, s.start - 1)
        name = s.name if s.kind == "extension" or not outer else f"{outer.name}.{s.name}"
        named.append(Scope(s.kind, name, s.start, s.end))
    return named


def enclosing(named: list[Scope], at: int) -> Scope | None:
    inside = [s for s in named if s.start <= at < s.end]
    return max(inside, key=lambda s: s.start) if inside else None


def split_top(s: str) -> list[tuple[int, str]]:
    """Splits at each comma outside brackets and generic arguments. A `<` opens generic arguments
    only right after a name, so a spaced `a < b` compares, and the `>` of `->` closes none."""
    parts, depth, angles, start = [], 0, 0, 0
    for i, c in enumerate(s):
        if c in OPEN:
            depth += 1
        elif c in CLOSE:
            depth -= 1
        elif c == "<" and i and (s[i - 1].isalnum() or s[i - 1] == "_"):
            angles += 1
        elif c == ">" and angles and s[i - 1] != "-":
            angles -= 1
        elif c == "," and depth == 0 and angles == 0:
            parts.append((start, s[start:i]))
            start = i + 1
    parts.append((start, s[start:]))
    return parts


def reasoned(comments: dict[int, tuple[int, str]], line: int) -> bool:
    return bool(DEFAULT_REASON.match(comments.get(line - 1, (0, ""))[1]))


def signature_defaults(path: str, code: str, text: str, named: list[Scope], comments: dict[int, tuple[int, str]]) -> list[Default]:
    found = []
    for m in SIGNATURE.finditer(text):
        function = m.group(1) or m.group(2) or m.group(3)
        end = closing(text, m.end())
        params = text[m.end(): end - 1]
        owner = enclosing(named, m.start())
        for offset, param in split_top(params):
            depth, eq = 0, -1
            for j, c in enumerate(param):
                if c in OPEN:
                    depth += 1
                elif c in CLOSE:
                    depth -= 1
                elif c == "=" and depth == 0 and param[j - 1] not in "=!<>" and param[j + 1: j + 2] != "=":
                    eq = j
                    break
            if eq < 0 or ":" not in param[:eq]:
                continue
            at = m.end() + offset
            value = " ".join(code[at + eq + 1: at + len(param)].split())
            kind = kind_of(text[at + eq + 1: at + len(param)])
            line = text.count("\n", 0, at + eq) + 1
            names = [w for w in param[:eq].split(":", 1)[0].split() if not w.startswith("@")]
            label = "_" if function == "subscript" and len(names) < 2 else names[0] if names else ""
            if kind in KINDS and not reasoned(comments, line):
                found.append(
                    Default(path, line, owner.name if owner else "", function, label, " ".join(names), value, kind)
                )
    return found


def memberwise_defaults(path: str, code: str, text: str, named: list[Scope], comments: dict[int, tuple[int, str]]) -> list[Default]:
    found = []
    for s in named:
        if s.kind != "struct":
            continue
        body = list(text[s.start: s.end - 1])
        depth = 0
        for i, c in enumerate(body):
            if c == "{":
                depth += 1
            if depth and c != "\n":
                body[i] = " "
            if c == "}":
                depth -= 1
        top = "".join(body)
        if re.search(r"(?<![.\w])init\s*[?!]?\s*[(<]", top):
            continue
        offset = 0
        previous = ""
        for top_line in top.split("\n"):
            at = s.start + offset
            offset += len(top_line) + 1
            if not top_line.strip():
                continue
            prior, previous = previous, top_line.strip()
            newline = text.find("\n", at)
            m = STORED_VAR.match(text, at, newline if newline >= 0 else len(text))
            if not m or prior.startswith("@"):
                continue
            name, type_, value, accessor = m.groups()
            if value is None and accessor is None:
                if not (type_ or "").rstrip().endswith("?"):
                    continue
                shown, kind = "nil (implicit)", "nil"
            elif value is None:
                continue
            else:
                group = 3 if value else 4
                shown = " ".join(code[m.start(group): m.end(group)].split())
                kind = kind_of(m.group(group))
            line = text.count("\n", 0, at) + 1
            if kind in KINDS and not reasoned(comments, line):
                found.append(Default(path, line, s.name, "init", name, name, shown, kind))
    return found


def defaults_in(path: str, raw: str) -> list[Default]:
    lexed = lex(raw)
    text, code = lexed.blanked(raw, literals=True), lexed.blanked(raw, literals=False)
    named = scopes(text)
    return (
        signature_defaults(path, code, text, named, lexed.comments)
        + memberwise_defaults(path, code, text, named, lexed.comments)
    )


def git(root: Path, *args: str) -> str:
    try:
        done = subprocess.run(["git", "-c", "core.quotePath=false", *args], cwd=root, capture_output=True, text=True)
    except OSError as error:
        raise Unanswered(f"git {args[0]} failed in {root}: {error}") from None
    if done.returncode != 0:
        first = next((line for line in done.stderr.splitlines() if line.strip()), "no output")
        raise Unanswered(f"git {' '.join(args[:3])} failed in {root}: {first}")
    return done.stdout


def tree_files(root: Path) -> list[tuple[str, str]]:
    listed = git(root, "ls-files", "--cached", "--others", "--exclude-standard", "--", *TREES)
    paths = [p for p in listed.splitlines() if p.endswith(".swift") and (root / p).is_file()]
    return [(p, (root / p).read_text(encoding="utf-8")) for p in paths]


def rev_files(root: Path, rev: str) -> list[tuple[str, str]]:
    listed = git(root, "ls-tree", "-r", "--name-only", rev, "--", *TREES)
    paths = [p for p in listed.splitlines() if p.endswith(".swift")]
    if not paths:
        return []
    batch = subprocess.run(
        ["git", "cat-file", "--batch"], cwd=root, input="".join(f"{rev}:{p}\n" for p in paths).encode(), capture_output=True
    )
    if batch.returncode != 0:
        raise Unanswered(f"git cat-file --batch failed in {root}: {batch.stderr.decode(errors='replace').strip()}")
    blobs = batch.stdout
    files, at = [], 0
    for path in paths:
        header_end = blobs.index(b"\n", at)
        size = int(blobs[at:header_end].split()[2])
        files.append((path, blobs[header_end + 1: header_end + 1 + size].decode("utf-8")))
        at = header_end + 1 + size + 1
    return files


def keys(defaults: list[Default]) -> Counter[str]:
    return Counter(d.key for d in defaults)


def read_baseline(root: Path) -> Counter[str]:
    try:
        lines = (root / BASELINE).read_text(encoding="utf-8").splitlines()
    except OSError as error:
        raise Unanswered(f"{BASELINE} cannot be read: {error.strerror}") from None
    return Counter(line for line in lines if line.strip() and not line.startswith("#"))


def write_baseline(root: Path, counted: Counter[str]) -> None:
    header = (
        "# Defaults scripts/lint-defaults.py accepts without a `// default:` reason, one line per\n"
        "# Type|function|label|kind, repeated per occurrence. Shrink it; never grow it by hand.\n"
    )
    body = "".join(f"{key}\n" for key in sorted(counted.elements()))
    (root / BASELINE).write_text(header + body, encoding="utf-8")


def parse(argv: list[str]) -> tuple[dict[str, str], Path] | None:
    options: dict[str, str] = {}
    rest = []
    it = iter(argv)
    for arg in it:
        if arg in ("--base", "--rev"):
            value = next(it, None)
            if value is None:
                return None
            options[arg] = value
        elif arg == "--write-baseline":
            options[arg] = ""
        elif arg.startswith("-") or rest:
            return None
        else:
            rest.append(arg)
    if "--write-baseline" in options and len(options) > 1:
        return None
    if "--rev" in options and "--base" not in options:
        return None
    return options, Path(rest[0] if rest else ".").resolve()


def main(argv: list[str]) -> int:
    parsed = parse(argv[1:])
    if parsed is None:
        print("\n".join(__doc__.strip().splitlines()[2:5]), file=sys.stderr)
        return 64
    options, root = parsed
    try:
        rev = options.get("--rev")
        found = [d for path, raw in (rev_files(root, rev) if rev else tree_files(root)) for d in defaults_in(path, raw)]
        if "--write-baseline" in options:
            write_baseline(root, keys(found))
            print(f"wrote {len(found)} keys to {BASELINE}")
            return 0
        base = options.get("--base")
        if base:
            accepted = keys([d for path, raw in rev_files(root, base) for d in defaults_in(path, raw)])
        else:
            accepted = read_baseline(root)
    except (Unanswered, UnicodeDecodeError, ValueError) as error:
        print(f"error: {error}", file=sys.stderr)
        print("       The defaults check cannot finish, so it fails rather than pass unchecked.", file=sys.stderr)
        return 2
    counted = keys(found)
    added = counted - accepted
    new = []
    for d in sorted(found, key=lambda d: (d.path, d.line)):
        if added[d.key] > 0:
            added[d.key] -= 1
            new.append(d)
    stale = [] if base else sorted((accepted - counted).elements())
    for d in new:
        print(d.describe())
    if new:
        print(
            "A default lets a caller skip a decision (CODING_STANDARDS.md, Optionals). Drop it and pass "
            "the value at each call site, or keep it and say why it is the safe answer with a "
            "`// default: <reason>` comment on its line."
        )
    for key in stale:
        print(f"{BASELINE}: delete one `{key}` line, since the tree no longer has that default.")
    if stale:
        print(
            "A removed default keeps no place in the baseline, so it cannot come back unnoticed. When "
            "the only change is a rename or a move into another type, run "
            "`scripts/lint-defaults.py --write-baseline` and commit the swap."
        )
    print(f"{len(found)} defaults, {len(new)} new, {len(stale)} gone from the tree")
    return 1 if new or stale else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
