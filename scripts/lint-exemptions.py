#!/usr/bin/env python3
# /// script
# requires-python = ">=3.9"
# dependencies = []
# ///
"""Fail when a SwiftLint exemption accepts a bug that no live issue tracks.

usage: scripts/lint-exemptions.py [ROOT]

Reads every `swiftlint:disable` in the Swift files git knows under ROOT where SwiftLint reads one:
the first `swiftlint:` in a `//` comment, wherever it sits in the comment, and never one in a
string, a block comment, or a `///` doc comment. The rules it exempts are the words before a ` - `,
as SwiftLint reads them, so prose there names rules and `all` disables every rule. Its reason is the
directive's own comment and, when the directive fills its line, the `//` comment lines directly
above it up to another directive. Each bare `#N` in the reason, with N of two to five digits and no
leading zero, is looked up with `gh issue view`. An exemption fails when it cites an issue that is
closed without the `wontfix` label, or a number with no issue or pull request. A cited pull request
is history, so it is never failed and never counts as the issue a bug-shaped rule needs.

`unstructured_task_is_held` and `fixture_dates_are_literal` exist to stop bugs, so an exemption of
either, or of `all`, accepts a known bug and must cite an issue. The other rules' exemptions record
design facts, such as a WCAG clause or a parameter count, and may cite none. A `// default:
<reason>` comment, the reason scripts/lint-defaults.py accepts for a defaulted parameter, is an
exemption of the same kind: it may cite no issue, and any issue it cites must be live.

Exits 0 when clean, 1 on findings, 2 when git, a file, or gh cannot answer, so the check never
passes unchecked, and 64 on a usage error or a LINT_EXEMPTIONS_GH_TIMEOUT that is not a finite
number above zero. Each gh call gets that many seconds (default 30).
"""
from __future__ import annotations

import json
import math
import os
import re
import subprocess
import sys
from concurrent.futures import ThreadPoolExecutor
from dataclasses import dataclass
from pathlib import Path

REPO = "Sunnshiine/workout-app"
BUG_SHAPED_RULES = {"unstructured_task_is_held", "fixture_dates_are_literal"}
DEFAULT_REASON = re.compile(r"//(?!/)\s*default:\s*\S")
COMMAND = re.compile(r"swiftlint:(disable|enable)(?::(?:next|this|previous))?(?:\s+(.*))?$")
STRING_START = re.compile(r'(#*)("""|")')
CITATION = re.compile(r"(?<![\w&])#([1-9]\d{1,4})(?!\w)")
NOT_FOUND = "Could not resolve to an issue or pull request"
UNCHECKED = "The exemption check cannot finish, so it fails rather than pass unchecked."
SIGN_IN = "Run `gh auth login`, or set GH_TOKEN."
OFFLINE = "GitHub is unreachable from this machine. Check the network, then rerun."
GH_FAILURE_HINTS = (
    (re.compile(r"gh auth login|HTTP 401|Bad credentials|GH_TOKEN"), SIGN_IN),
    (re.compile(r"error connecting|dial tcp|no such host|connection refused|i/o timeout"), OFFLINE),
)


@dataclass(frozen=True)
class Exemption:
    path: str
    line: int
    rules: tuple[str, ...]
    cited: tuple[int, ...]

    @property
    def bug_rules(self) -> tuple[str, ...]:
        return tuple(r for r in self.rules if r == "all" or r in BUG_SHAPED_RULES)


@dataclass(frozen=True)
class Issue:
    exists: bool
    is_pull_request: bool = False
    live: bool = False


class Unanswered(Exception):
    def __init__(self, problem: str, hint: str):
        super().__init__(problem)
        self.problem = problem
        self.hint = hint


def line_comments(text: str) -> dict[int, tuple[int, str]]:
    """Maps a line index to the column and text of the `//` comment on it. A `//` inside a string
    or a block comment is no comment, and a `\\(` in a string reopens code up to its `)`."""
    comments = {}
    frames: list[tuple[str, int]] = []
    line = column = i = 0
    n = len(text)
    while i < n:
        kind, value = frames[-1] if frames else ("code", 0)
        if text[i] == "\n":
            line, column, i = line + 1, 0, i + 1
            if kind == "string" and value >= 0:
                frames.pop()
            continue
        step = 1
        if kind == "block":
            if text.startswith("/*", i):
                frames.append(("block", 0))
                step = 2
            elif text.startswith("*/", i):
                frames.pop()
                step = 2
        elif kind == "string":
            hashes = abs(value) - 1
            close = ('"""' if value < 0 else '"') + "#" * hashes
            escape = "\\" + "#" * hashes
            if text.startswith(escape + "(", i):
                frames.append(("code", 1))
                step = len(escape) + 1
            elif text.startswith(escape, i):
                step = len(escape) + 1
            elif text.startswith(close, i):
                frames.pop()
                step = len(close)
        elif text.startswith("//", i):
            end = text.find("\n", i)
            end = n if end < 0 else end
            comments[line] = (column, text[i:end])
            column, i = column + end - i, end
            continue
        elif text.startswith("/*", i):
            frames.append(("block", 0))
            step = 2
        elif opened := STRING_START.match(text, i):
            hashes = len(opened.group(1))
            frames.append(("string", -(hashes + 1) if opened.group(2) == '"""' else hashes + 1))
            step = opened.end() - i
        elif value and text[i] in "()":
            frames[-1] = ("code", value + (1 if text[i] == "(" else -1))
            if frames[-1][1] == 0:
                frames.pop()
        column, i = column + step, i + step
    return comments


def command(comment: str) -> re.Match[str] | None:
    """SwiftLint reads the first `swiftlint:` in a `//` comment, wherever it sits, as the command,
    and ignores one in a `///` doc comment."""
    start = comment.find("swiftlint:")
    if start < 0 or comment.startswith("///"):
        return None
    return COMMAND.match(comment, start)


def exemptions_in(path: str, text: str) -> list[Exemption]:
    comments = line_comments(text)
    lines = text.split("\n")
    found = []
    for index, (column, comment) in sorted(comments.items()):
        if DEFAULT_REASON.match(comment):
            cited = sorted({int(n) for n in CITATION.findall(comment)})
            found.append(Exemption(path, index + 1, ("default",), tuple(cited)))
            continue
        directive = command(comment)
        if not directive or directive.group(1) != "disable":
            continue
        rules = (directive.group(2) or "").split(" - ", 1)[0].split()
        reason = [comment]
        above = index - 1 if not lines[index][:column].strip() else -1
        while above in comments:
            above_column, above_comment = comments[above]
            code_before = lines[above][:above_column].strip()
            if code_before or above_comment.startswith("///") or command(above_comment):
                break
            reason.append(above_comment)
            above -= 1
        cited = sorted({int(n) for part in reason for n in CITATION.findall(part)})
        found.append(Exemption(path, index + 1, tuple(rules), tuple(cited)))
    return found


def swift_files(root: Path) -> list[str]:
    try:
        listed = subprocess.run(
            ["git", "-c", "core.quotePath=false", "ls-files", "--cached", "--others",
             "--exclude-standard", "--", "*.swift"],
            cwd=root, capture_output=True, text=True,
        )
    except OSError as error:
        raise Unanswered(f"git ls-files failed in {root}: {error}", "Install git.") from None
    if listed.returncode != 0:
        first = next((line for line in listed.stderr.splitlines() if line.strip()), "no output")
        raise Unanswered(f"git ls-files failed in {root}: {first}", "Run the check on a git checkout.")
    return [p for p in listed.stdout.splitlines() if (root / p).is_file()]


def read(root: Path, path: str) -> str:
    try:
        return (root / path).read_text(encoding="utf-8")
    except UnicodeDecodeError:
        raise Unanswered(f"{path} is not UTF-8", "Save it as UTF-8, as SwiftLint expects.") from None


def look_up(number: int, timeout: float) -> Issue:
    command = ["gh", "issue", "view", str(number), "--repo", REPO, "--json", "state,labels,url"]
    try:
        answer = subprocess.run(command, capture_output=True, text=True, timeout=timeout)
    except FileNotFoundError:
        raise Unanswered("gh is not on PATH", "Install the GitHub CLI, then run `gh auth login`.") from None
    except subprocess.TimeoutExpired:
        raise Unanswered(
            f"gh issue view {number} did not answer within {timeout:g} s",
            "GitHub may be slow or unreachable. Check the network, then rerun.",
        ) from None
    if answer.returncode != 0:
        if NOT_FOUND in answer.stderr:
            return Issue(exists=False)
        first = next((line for line in answer.stderr.splitlines() if line.strip()), "no output")
        hint = next(
            (hint for pattern, hint in GH_FAILURE_HINTS if pattern.search(answer.stderr)),
            f"Run `{' '.join(command)}` to see why.",
        )
        raise Unanswered(f"gh issue view {number} exited {answer.returncode}: {first}", hint)
    try:
        fields = json.loads(answer.stdout)
        labels = {label["name"] for label in fields["labels"]}
        return Issue(
            exists=True,
            is_pull_request="/pull/" in fields["url"],
            live=fields["state"] == "OPEN" or "wontfix" in labels,
        )
    except (ValueError, KeyError, TypeError):
        raise Unanswered(
            f"gh issue view {number} printed no issue: {answer.stdout[:80]!r}",
            f"Run `{' '.join(command)}` to see why.",
        ) from None


def findings(exemptions: list[Exemption], issues: dict[int, Issue]) -> list[str]:
    out = []
    for e in exemptions:
        where = f"{e.path}:{e.line}"
        for n in e.cited:
            issue = issues[n]
            if not issue.exists:
                out.append(
                    f"{where}: the exemption cites #{n}, which is no issue or pull request in "
                    f"{REPO}. Correct the number, or reword the text so it is no bare #N."
                )
            elif not issue.is_pull_request and not issue.live:
                out.append(
                    f"{where}: the exemption cites #{n}, which is closed without the wontfix "
                    f"label. Remove the exemption, reopen #{n}, or label it wontfix."
                )
        tracked = any(issues[n].exists and not issues[n].is_pull_request for n in e.cited)
        if e.bug_rules and not tracked:
            out.append(
                f"{where}: the {' '.join(e.bug_rules)} exemption cites no issue. That rule stops a "
                f"bug, so its exemption accepts one. Cite the open or wontfix issue that tracks it "
                f"as a bare #N, N of two to five digits with no leading zero, on the directive "
                f"or the comment lines directly above it. An owner/repo#N or a URL does not count."
            )
    return out


def main(argv: list[str]) -> int:
    if len(argv) > 2 or (len(argv) == 2 and argv[1].startswith("-")):
        print(__doc__.strip().splitlines()[2], file=sys.stderr)
        return 64
    root = Path(argv[1] if len(argv) == 2 else ".").resolve()
    setting = os.environ.get("LINT_EXEMPTIONS_GH_TIMEOUT", "30")
    try:
        timeout = float(setting)
    except ValueError:
        timeout = math.nan
    if not 0 < timeout < math.inf:
        print(f"error: LINT_EXEMPTIONS_GH_TIMEOUT is {setting!r}, not a positive number of seconds.", file=sys.stderr)
        return 64
    try:
        exemptions = [e for path in swift_files(root) for e in exemptions_in(path, read(root, path))]
        numbers = sorted({n for e in exemptions for n in e.cited})
        with ThreadPoolExecutor(max_workers=8) as pool:
            issues = dict(zip(numbers, pool.map(lambda n: look_up(n, timeout), numbers)))
    except Unanswered as error:
        print(f"error: {error.problem}", file=sys.stderr)
        print(f"       {UNCHECKED} {error.hint}", file=sys.stderr)
        return 2
    failed = findings(exemptions, issues)
    for line in failed:
        print(line)
    print(f"{len(exemptions)} exemptions cite {len(numbers)} issues, and {len(failed)} fail")
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
