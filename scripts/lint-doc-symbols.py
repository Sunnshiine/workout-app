#!/usr/bin/env python3
# /// script
# requires-python = ">=3.9"
# dependencies = []
# ///
"""Fail when an agent doc names a path, file, symbol, or launch flag this tree does not have.

usage: scripts/lint-doc-symbols.py [ROOT]

Reads the inline code spans of AGENTS.md, docs/, and the verify skill, and the repo paths in their
fenced blocks (a token whose first segment is a top-level entry of this tree, such as
scripts/flake-hunt.sh). ADRs and research notes are history and stay out. A span that names
something outside the tree on purpose is exempted in its doc with
<!-- doc-symbols: not-in-tree NAME... -->. Every -UITEST_ flag in those docs, fenced commands
included, and in every file outside Markdown must be a row of the generated launch-flag table, and
the app's sources may spell one only in LaunchFlag.

Exits 0 when clean, 1 on findings, 2 on a usage error.
"""
from __future__ import annotations

import difflib
import fnmatch
import os
import re
import subprocess
import sys
from dataclasses import dataclass
from enum import Enum
from typing import Iterator

DOC_SCOPE = ("AGENTS.md", "docs/*.md", ".agents/skills/verify/*.md")
HISTORY = ("docs/adr/", "docs/research/")
FLAG_TABLE = ".agents/skills/verify/launch-flags.md"
FLAG_SOURCE = "Sources/WorkoutTracker/Fixtures/LaunchFlag.swift"
APP_SOURCES = ("Sources/", "App/", "WorkoutShared/", "WorkoutWidgets/")
# This lint and its test spell missing names on purpose, so they vouch for nothing.
SELF = ("scripts/lint-doc-symbols.py", "scripts/tests/lint-doc-symbols.test.sh")
CODE_EXTENSIONS = {
    "swift", "pbxproj", "xcscheme", "py", "sh", "yml", "yaml", "ts", "mjs", "js", "awk", "plist",
    "entitlements", "xcconfig",
}
# A token with one of these extensions claims a file even when its directory starts nowhere in the
# tree, so a directory move (WorkoutTracker/AppIcon.icon) still gets checked.
CLAIM_EXTENSIONS = CODE_EXTENSIONS | {
    "md", "json", "toml", "svg", "png", "xcstrings", "tsv", "html", "icon", "xcassets",
    "appiconset", "xcodeproj", "xctestplan", "template",
}

FLAG = re.compile(r"-UITEST_[A-Z0-9_]+")
IDENT = r"[A-Za-z_][A-Za-z0-9_]*"
CHAIN = re.compile(rf"{IDENT}(\.{IDENT})*")
HUMP = re.compile(r"[a-z0-9][A-Z]")
FILE_NAME = re.compile(r"\.?[\w+-]+(\.[\w+-]+)*\.([A-Za-z]+)")
SPAN = re.compile(r"(?<!`)(`+)(?!`)(.+?)(?<!`)\1(?!`)", re.S)
FENCE = re.compile(r"\s*(```+|~~~+)")
LIST_OR_ROW = re.compile(r"\s*([-*+]|\d+[.)])\s|\s*\|")
EXEMPTION = re.compile(r"<!--\s*doc-symbols:\s*not-in-tree\s+(.*?)\s*-->")
TABLE_ROW = re.compile(r"^\|\s*`(-UITEST_[A-Z0-9_]+)`", re.M)


class Kind(Enum):
    FLAG = "flag"
    PATH = "path"
    FILE = "file"
    IDENT = "ident"


@dataclass(frozen=True)
class Claim:
    kind: Kind
    token: str
    names: tuple[str, ...]


@dataclass(frozen=True)
class Tree:
    paths: frozenset[str]
    top: frozenset[str]
    basenames: frozenset[str]
    identifiers: frozenset[str]
    flags: frozenset[str]
    ignored: frozenset[str]


@dataclass(frozen=True)
class Snippet:
    line: int
    text: str
    fenced: bool


@dataclass(frozen=True)
class Finding:
    doc: str
    line: int
    message: str
    hint: str = ""


def classify(token: str, doc_dir: str, top: frozenset[str]) -> Claim | None:
    t = token.strip("'\"").rstrip(",;:.")
    if not t or "://" in t or ("@" in t and "/" in t):
        return None
    if FLAG.fullmatch(t):
        return Claim(Kind.FLAG, t, (t,))
    if t.startswith(("/", "~", "$", "-")):
        return None
    t = re.sub(r"#[\w-]*$", "", re.sub(r":\d+(-\d+)?$", "", t))
    if "/" in t:
        pattern = re.sub(r"<[^>]+>", "*", t).rstrip("/")
        first = pattern.split("/")[0]
        extension = FILE_NAME.fullmatch(pattern.rsplit("/", 1)[-1])
        if first in top or first in (".", "..") or (extension and extension.group(2) in CLAIM_EXTENSIONS):
            relative = os.path.normpath(os.path.join(doc_dir, pattern))
            return Claim(Kind.PATH, t, (pattern, relative))
        return None
    extension = FILE_NAME.fullmatch(t)
    if (extension and extension.group(2) in CLAIM_EXTENSIONS) or (t.startswith(".") and "-" in t):
        return Claim(Kind.FILE, t, (re.sub(r"<[^>]+>", "*", t),))
    s = re.sub(r"^[@#\\]", "", t).lstrip(".")
    labels: list[str] = []
    call = re.fullmatch(r"(.*?)\((.*)\)", s)
    if call:
        s = call.group(1)
        if re.fullmatch(r"(\w+:)+", call.group(2)):
            labels = [label for label in call.group(2).split(":") if label and label != "_"]
    s = re.sub(r"[?!]$", "", re.sub(r"<.*>$", "", s))
    if not CHAIN.fullmatch(s):
        return None
    humped = [segment for segment in s.split(".") if HUMP.search(segment)]
    return Claim(Kind.IDENT, t, tuple(humped + labels)) if humped else None


def is_glob(name: str) -> bool:
    return any(c in name for c in "*?[")


def through_links(path: str, links: dict[str, str]) -> str:
    for link, target in links.items():
        if path == link or path.startswith(link + "/"):
            return target + path[len(link):]
    return path


def resolve(claim: Claim, tree: Tree) -> tuple[str, ...]:
    if claim.kind is Kind.FLAG:
        return () if claim.token in tree.flags else (claim.token,)
    if claim.kind is Kind.IDENT:
        return tuple(name for name in claim.names if name not in tree.identifiers)
    if claim.kind is Kind.FILE:
        (name,) = claim.names
        if is_glob(name):
            found = any(fnmatch.fnmatchcase(b, name) for b in tree.basenames)
        else:
            found = name in tree.basenames or name in tree.ignored
        return () if found else (claim.token,)
    for name in claim.names:
        if is_glob(name):
            patterns = (name, "*/" + name, name[2:] if name.startswith("*/") else name)
            if any(fnmatch.fnmatchcase(p, pattern) for p in tree.paths for pattern in patterns):
                return ()
        elif name in tree.paths or name in tree.ignored or name + "/" in tree.ignored:
            return ()
    pattern = claim.names[0]
    shorthand = pattern.split("/")[0] not in tree.top
    if shorthand and not is_glob(pattern) and any(p.endswith("/" + pattern) for p in tree.paths):
        return ()
    return (claim.token,)


def hint(claim: Claim, missing: tuple[str, ...], tree: Tree) -> str:
    if claim.kind is Kind.PATH:
        segments = claim.names[0].split("/")
        for k in range(len(segments) - 1, 0, -1):
            suffix = "/".join(segments[-k:])
            near = sorted(p for p in tree.paths if p == suffix or p.endswith("/" + suffix))
            if near:
                return "Closest: " + ", ".join(near[:3]) + "."
        return ""
    pool = {Kind.FLAG: tree.flags, Kind.FILE: tree.basenames, Kind.IDENT: tree.identifiers}[claim.kind]
    near = difflib.get_close_matches(missing[0], pool, n=1, cutoff=0.8)
    return f"Closest: {near[0]}." if near else ""


def message(claim: Claim, missing: tuple[str, ...]) -> str:
    if claim.kind is Kind.FLAG:
        return f"`{claim.token}` is not a row of {FLAG_TABLE}, so the app ignores it."
    if claim.kind is Kind.PATH:
        return f"`{claim.token}` is not a path in this tree."
    if claim.kind is Kind.FILE:
        return f"`{claim.token}` names no file in this tree."
    named = claim.token if missing == claim.names else ", ".join(missing)
    return f"`{named}` is named in no Swift, project, or script file."


def snippets(text: str) -> list[Snippet]:
    out: list[Snippet] = []
    paragraph: list[str] = []
    start = 0
    fence = ""

    def flush() -> None:
        joined = "\n".join(paragraph)
        for m in SPAN.finditer(joined):
            span_line = start + joined.count("\n", 0, m.start())
            out.append(Snippet(span_line, m.group(2).replace("\n", " ").strip(), fenced=False))
        paragraph.clear()

    for number, line in enumerate(text.splitlines(), 1):
        marker = FENCE.match(line)
        if fence:
            if marker and marker.group(1)[0] == fence[0] and len(marker.group(1)) >= len(fence):
                fence = ""
            else:
                out.append(Snippet(number, line, fenced=True))
        elif marker:
            flush()
            fence = marker.group(1)
        elif not line.strip():
            flush()
        else:
            if LIST_OR_ROW.match(line):
                flush()
            if not paragraph:
                start = number
            paragraph.append(line)
    flush()
    return out


def names_repo_path(claim: Claim, top: frozenset[str]) -> bool:
    return claim.kind is Kind.PATH and claim.names[0].split("/")[0] in top


def claims(doc: str, text: str, top: frozenset[str]) -> Iterator[tuple[int, Claim]]:
    for snippet in snippets(text):
        for token in snippet.text.split():
            claim = classify(token, os.path.dirname(doc), top)
            if claim is None or claim.kind is Kind.FLAG:
                continue
            if snippet.fenced and not names_repo_path(claim, top):
                continue
            yield snippet.line, claim


def exemptions(text: str) -> dict[str, int]:
    exempt: dict[str, int] = {}
    for m in EXEMPTION.finditer(text):
        for name in m.group(1).split():
            exempt[name] = text.count("\n", 0, m.start()) + 1
    return exempt


def lint_doc(doc: str, text: str, tree: Tree, top: frozenset[str]) -> list[Finding]:
    exempt = exemptions(text)
    used: set[str] = set()
    findings = []
    for line, claim in claims(doc, text, top):
        missing = resolve(claim, tree)
        used.update(name for name in missing if name in exempt)
        missing = tuple(name for name in missing if name not in exempt)
        if missing:
            findings.append(Finding(doc, line, message(claim, missing), hint(claim, missing, tree)))
    for m in FLAG.finditer(text):
        if m.group() in exempt:
            used.add(m.group())
        elif m.group() not in tree.flags:
            claim = Claim(Kind.FLAG, m.group(), (m.group(),))
            line = text.count("\n", 0, m.start()) + 1
            findings.append(Finding(doc, line, message(claim, (m.group(),)), hint(claim, (m.group(),), tree)))
    for name, line in exempt.items():
        if name not in used:
            findings.append(
                Finding(doc, line, f"the exemption names `{name}`, which nothing in this file fails on. Drop it.")
            )
    return findings


def lint_callers(path: str, text: str, flags: frozenset[str]) -> list[Finding]:
    findings = []
    for m in FLAG.finditer(text):
        line = text.count("\n", 0, m.start()) + 1
        if path.startswith(APP_SOURCES) and path != FLAG_SOURCE:
            findings.append(
                Finding(path, line, f"`{m.group()}` reads a launch flag outside LaunchFlag. "
                        "Declare it there and read it through UITestLaunch.")
            )
        elif path == FLAG_SOURCE and m.group() not in flags:
            findings.append(
                Finding(path, line, f"`{m.group()}` is declared in LaunchFlag but missing from LaunchFlag.all. "
                        "Add it there, then run: RECORD_LAUNCH_FLAGS=1 swift test --filter LaunchFlagTableTests")
            )
        elif m.group() not in flags:
            findings.append(Finding(path, line, message(Claim(Kind.FLAG, m.group(), (m.group(),)), ())))
    return findings


def git(root: str, *args: str, stdin: str = "") -> str:
    """Exit 1 is an answer (check-ignore found nothing); above 1 is fatal."""
    result = subprocess.run(
        ["git", "-C", root, "-c", "core.quotePath=false", *args],
        input=stdin, capture_output=True, text=True, check=False,
    )
    if result.returncode > 1:
        sys.exit(usage_error(f"git {' '.join(args)} failed: {result.stderr.strip()}"))
    return result.stdout


def read_text(root: str, path: str) -> str | None:
    full = os.path.join(root, path)
    if os.path.islink(full) or not os.path.isfile(full):
        return None
    raw = open(full, "rb").read()
    return None if b"\0" in raw[:8000] else raw.decode("utf-8", errors="replace")


def usage_error(text: str) -> int:
    print(f"error: {text}", file=sys.stderr)
    return 2


def main(argv: list[str]) -> int:
    if argv[:1] in (["-h"], ["--help"]):
        print(__doc__.strip())
        return 0
    if len(argv) > 1 or (argv and argv[0].startswith("-")):
        print("usage: scripts/lint-doc-symbols.py [ROOT]", file=sys.stderr)
        return 2
    root = argv[0] if argv else os.path.join(os.path.dirname(os.path.abspath(__file__)), "..")
    if not os.path.isdir(os.path.join(root, ".git")) and not os.path.isfile(os.path.join(root, ".git")):
        return usage_error(f"{root} is not a git checkout.")

    listed = git(root, "ls-files", "--cached", "--others", "--exclude-standard").splitlines()
    files = sorted(set(listed) - set(git(root, "ls-files", "--deleted").splitlines()))
    docs = [
        f for f in files
        if any(fnmatch.fnmatchcase(f, pattern) for pattern in DOC_SCOPE) and not f.startswith(HISTORY)
    ]
    if not docs:
        return usage_error(f"{root} holds no AGENTS.md, docs/, or verify skill Markdown, so this run would check nothing.")
    if FLAG_TABLE not in files:
        return usage_error(f"{FLAG_TABLE} is missing. Run: RECORD_LAUNCH_FLAGS=1 swift test --filter LaunchFlagTableTests")

    texts = {f: text for f in files if f not in SELF and (text := read_text(root, f)) is not None}
    flags = frozenset(TABLE_ROW.findall(texts[FLAG_TABLE]))
    if not flags:
        return usage_error(f"{FLAG_TABLE} has no flag rows.")

    paths = set(files)
    for f in files:
        parent = os.path.dirname(f)
        while parent:
            paths.add(parent)
            parent = os.path.dirname(parent)
    top = frozenset(f.split("/")[0] for f in files)
    identifiers = {os.path.splitext(os.path.basename(f))[0] for f in files}
    for f, text in texts.items():
        if f.rsplit(".", 1)[-1] in CODE_EXTENSIONS:
            identifiers.update(re.findall(IDENT, text))

    links = {}
    for entry in git(root, "ls-files", "-s").splitlines():
        mode, _, rest = entry.partition(" ")
        if mode == "120000":
            link = rest.split("\t", 1)[1]
            links[link] = os.path.normpath(os.path.join(os.path.dirname(link), os.readlink(os.path.join(root, link))))

    for link, target in links.items():
        paths.update(link + p[len(target):] for p in list(paths) if p.startswith(target + "/"))

    candidates = set()
    for doc in docs:
        for _, claim in claims(doc, texts[doc], top):
            if claim.kind in (Kind.PATH, Kind.FILE):
                for name in (through_links(n, links) for n in claim.names):
                    if not is_glob(name) and not name.startswith(("..", "/")):
                        candidates.update((name, name + "/"))
    ignored = git(root, "check-ignore", "--no-index", "--stdin", stdin="\n".join(sorted(candidates)))

    tree = Tree(
        paths=frozenset(paths),
        top=top,
        basenames=frozenset(os.path.basename(p) for p in paths),
        identifiers=frozenset(identifiers),
        flags=flags,
        ignored=frozenset(ignored.splitlines()),
    )
    findings = [finding for doc in docs for finding in lint_doc(doc, texts[doc], tree, top)]
    for f, text in texts.items():
        if not f.endswith(".md"):
            findings.extend(lint_callers(f, text, flags))

    for finding in findings:
        print(f"error: {finding.doc}:{finding.line}: {finding.message}", file=sys.stderr)
        if finding.hint:
            print(f"       {finding.hint}", file=sys.stderr)
    if findings:
        print(f"{len(findings)} finding(s). Fix each line above.", file=sys.stderr)
        if any(finding.doc.endswith(".md") for finding in findings):
            print(
                "When a doc names something outside this tree on purpose (an Apple accessibility role, a retired\n"
                "name), add <!-- doc-symbols: not-in-tree NAME... --> to that doc.",
                file=sys.stderr,
            )
        return 1
    print(f"==> Clean: {len(docs)} docs, {len(flags)} launch flags")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
