#!/usr/bin/env python3
# /// script
# requires-python = ">=3.9"
# dependencies = []
# ///
"""Fail when a SwiftLint exemption accepts a bug that no live issue tracks.

usage: scripts/lint-exemptions.py [ROOT]

Reads every `swiftlint:disable` in the Swift files git knows under ROOT. An exemption's reason is
the comment on its line and the `//` comment lines directly above it. Each `#N` in the reason is
looked up with `gh issue view`, and an exemption fails when it cites an issue that is closed
without the `wontfix` label, or a number with no issue or pull request. A cited pull request is
history, so it is never failed and never counts as the issue a bug-shaped rule needs.

`unstructured_task_is_held` and `fixture_dates_are_literal` exist to stop bugs, so an exemption
of either, or of `all`, accepts a known bug and must cite an issue. The other rules' exemptions
record design facts, such as a WCAG clause or a parameter count, and may cite none.

Exits 0 when clean, 1 on findings, 2 when gh cannot answer for a cited number, so the check
never passes unchecked, and 64 on a usage error.
"""
from __future__ import annotations

import json
import re
import subprocess
import sys
from concurrent.futures import ThreadPoolExecutor
from dataclasses import dataclass
from pathlib import Path

REPO = "Sunnshiine/workout-app"
BUG_SHAPED_RULES = {"unstructured_task_is_held", "fixture_dates_are_literal"}
DISABLE = re.compile(r"//\s*swiftlint:disable(?::(?:next|this|previous))?\s+(.*)")
RULE = re.compile(r"[a-z_]+")
CITATION = re.compile(r"(?<![\w&])#(\d+)\b")
NOT_FOUND = "Could not resolve to an issue or pull request"


@dataclass(frozen=True)
class Exemption:
    path: str
    line: int
    rules: tuple[str, ...]
    cited: tuple[int, ...]

    @property
    def bug_shaped(self) -> bool:
        return "all" in self.rules or bool(BUG_SHAPED_RULES.intersection(self.rules))


@dataclass(frozen=True)
class Issue:
    exists: bool
    is_pull_request: bool = False
    live: bool = False


class GhUnavailable(Exception):
    pass


def comment(text: str) -> str:
    start = text.find("//")
    return text[start:] if start >= 0 else ""


def exemptions_in(path: str, text: str) -> list[Exemption]:
    lines = text.splitlines()
    found = []
    for index, line in enumerate(lines):
        directive = DISABLE.search(line)
        if not directive:
            continue
        rules = []
        for word in directive.group(1).split():
            if not RULE.fullmatch(word):
                break
            rules.append(word)
        reason = [comment(line)]
        above = index - 1
        while above >= 0:
            stripped = lines[above].strip()
            if not stripped.startswith("//") or stripped.startswith("///"):
                break
            reason.append(stripped)
            above -= 1
        cited = sorted({int(n) for part in reason for n in CITATION.findall(part)})
        found.append(Exemption(path, index + 1, tuple(rules), tuple(cited)))
    return found


def swift_files(root: Path) -> list[str]:
    listed = subprocess.run(
        ["git", "-c", "core.quotePath=false", "ls-files", "--cached", "--others",
         "--exclude-standard", "--", "*.swift"],
        cwd=root, capture_output=True, text=True, check=True,
    )
    return [p for p in listed.stdout.splitlines() if (root / p).is_file()]


def look_up(number: int) -> Issue:
    try:
        answer = subprocess.run(
            ["gh", "issue", "view", str(number), "--repo", REPO, "--json", "state,labels,url"],
            capture_output=True, text=True,
        )
    except FileNotFoundError:
        raise GhUnavailable("gh is not on PATH") from None
    if answer.returncode != 0:
        if NOT_FOUND in answer.stderr:
            return Issue(exists=False)
        first = next((l for l in answer.stderr.splitlines() if l.strip()), "no output")
        raise GhUnavailable(f"gh issue view {number} exited {answer.returncode}: {first}")
    try:
        fields = json.loads(answer.stdout)
        labels = {label["name"] for label in fields["labels"]}
        return Issue(
            exists=True,
            is_pull_request="/pull/" in fields["url"],
            live=fields["state"] == "OPEN" or "wontfix" in labels,
        )
    except (ValueError, KeyError, TypeError):
        raise GhUnavailable(f"gh issue view {number} printed no issue: {answer.stdout[:80]!r}") from None


def findings(exemptions: list[Exemption], issues: dict[int, Issue]) -> list[str]:
    out = []
    for e in exemptions:
        where = f"{e.path}:{e.line}"
        for n in e.cited:
            issue = issues[n]
            if not issue.exists:
                out.append(f"{where}: the exemption cites #{n}, which is no issue in {REPO}.")
            elif not issue.is_pull_request and not issue.live:
                out.append(
                    f"{where}: the exemption cites #{n}, which is closed without the wontfix "
                    f"label. Remove the exemption, reopen #{n}, or label it wontfix."
                )
        tracked = any(issues[n].exists and not issues[n].is_pull_request for n in e.cited)
        if e.bug_shaped and not tracked:
            rules = " ".join(e.rules)
            out.append(
                f"{where}: the {rules} exemption cites no issue. That rule stops a bug, so its "
                f"exemption accepts one. Cite the open issue that tracks it, or a wontfix one."
            )
    return out


def main(argv: list[str]) -> int:
    if len(argv) > 2 or (len(argv) == 2 and argv[1].startswith("-")):
        print(__doc__.strip().splitlines()[2], file=sys.stderr)
        return 64
    root = Path(argv[1] if len(argv) == 2 else ".").resolve()
    exemptions = []
    for path in swift_files(root):
        exemptions += exemptions_in(path, (root / path).read_text(encoding="utf-8"))
    numbers = sorted({n for e in exemptions for n in e.cited})
    try:
        with ThreadPoolExecutor(max_workers=8) as pool:
            issues = dict(zip(numbers, pool.map(look_up, numbers)))
    except GhUnavailable as error:
        print(f"error: {error}", file=sys.stderr)
        print(
            "       The exemption check cannot read the cited issues, so it fails rather than "
            "pass unchecked. Run `gh auth login`, or set GH_TOKEN.",
            file=sys.stderr,
        )
        return 2
    failed = findings(exemptions, issues)
    for line in failed:
        print(line)
    print(f"{len(exemptions)} exemptions cite {len(numbers)} issues, and {len(failed)} fail")
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
