#!/usr/bin/env python3
"""Check a PR body's receipts against the head, and its commits' closing keywords against the body.

usage: scripts/check-receipts.py --body-file FILE --head SHA [--base REF] [--repo OWNER/NAME] [-C DIR]

A receipt is a fenced block, ``` or ~~~, whose info string is `receipt` in any case, as
scripts/receipt.sh writes it. A receipt quoted inside another fence is not one. Each receipt fails
when it does not parse (no closing fence, a line that is not a field, an unknown or repeated
field), when a field is missing, when it says dirty: yes, when its exit is not 0, when its sha is
not a commit in this repository (in CI, one never pushed to GitHub), or when its tree differs from
HEAD's in a path outside docs/. A receipt named lint is stale on any change, docs/ included,
because the lint reads the docs. The trees are compared, not the history, so a receipt survives a
docs/-only commit, merge, or rebase. A merge of the base that brings code in makes every earlier
receipt stale. The summary field is not checked.

With --base, every commit on HEAD and not on REF that carries a closing keyword (`Fixes #N`,
`closes owner/repo#N`, `resolved: https://github.com/owner/repo/issues/N`) fails unless the body
closes the same issue outside code spans and fences. The repository squashes with the commit
messages as the body, so such a commit closes the issue when the PR lands whatever the PR body
says. --repo, or else GITHUB_REPOSITORY or the origin remote, names this repository, so that its
owner/repo#N matches #N.

Exit 0 when every check passes, 1 when one fails, and 2 on bad arguments or a git failure.
"""
import argparse
import os
import re
import subprocess
import sys
from dataclasses import dataclass, field

FIELDS = ("name", "command", "sha", "dirty", "exit", "summary")
REQUIRED = FIELDS[:-1]
FENCE_OPEN = re.compile(r" {0,3}(`{3,}|~{3,})(.*)")
FIELD = re.compile(r"([a-z]+):[ \t]?(.*)")
NESTED_RECEIPT = re.compile(r"[ \t]*(?:>[ \t]*|[-*+][ \t]+|\d+[.)][ \t]+)+(?:`{3,}|~{3,})[ \t]*receipt\b", re.IGNORECASE)
INLINE_CODE = re.compile(r"(`+)(?!`).*?(?<!`)\1(?!`)", re.DOTALL)
CLOSING = re.compile(
    r"\b(?:close[sd]?|fix(?:e[sd])?|resolve[sd]?):?[ \t]+"
    r"(?:https?://github\.com/(?P<url>[\w.-]+/[\w.-]+)/issues/|(?P<repo>[\w.-]+/[\w.-]+)?#)(?P<number>\d+)\b",
    re.IGNORECASE,
)
REMOTE = re.compile(r"github\.com[:/]([\w.-]+/[\w.-]+?)(?:\.git)?/?$")
MAX_LISTED_PATHS = 3


@dataclass
class Fence:
    info: str
    lines: list = field(default_factory=list)
    closed: bool = False


@dataclass
class Receipt:
    fields: dict
    errors: list

    @property
    def name(self):
        return self.fields.get("name") or "(unnamed)"


def git(repo, *args):
    r = subprocess.run(["git", "-C", repo, *args], capture_output=True, encoding="utf-8", errors="replace")
    return r.returncode, r.stdout


def must_git(repo, *args):
    code, out = git(repo, *args)
    if code != 0:
        print(f"git {' '.join(args)} failed in {repo}", file=sys.stderr)
        sys.exit(2)
    return out


def split_body(body):
    """Splits a Markdown body into its top-level fences and the prose lines outside them."""
    fences, prose, fence, close = [], [], None, None
    for line in body.splitlines():
        if fence is not None:
            if close.fullmatch(line):
                fence.closed, fence = True, None
            else:
                fence.lines.append(line)
            continue
        m = FENCE_OPEN.fullmatch(line)
        if m and not (m.group(1)[0] == "`" and "`" in m.group(2)):
            fence = Fence(m.group(2).strip())
            fences.append(fence)
            close = re.compile(rf" {{0,3}}{re.escape(m.group(1)[0])}{{{len(m.group(1))},}}[ \t]*")
        else:
            prose.append(line)
    return fences, prose


def parse_receipt(fence):
    fields, errors = {}, []
    for line in fence.lines:
        if not line.strip():
            continue
        m = FIELD.fullmatch(line.strip())
        if not m:
            errors.append(f"has a line that is not a field: {line.strip()}")
        elif m.group(1) not in FIELDS:
            errors.append(f"has an unknown field {m.group(1)}")
        elif m.group(1) in fields:
            errors.append(f"repeats {m.group(1)}")
        else:
            fields[m.group(1)] = m.group(2).strip()
    if not fence.closed:
        errors.append("has no closing fence")
    return Receipt(fields, errors)


def is_receipt(fence):
    words = fence.info.split()
    return bool(words) and words[0].lower() == "receipt"


def stale_paths(receipt, changed):
    if receipt.fields["name"] == "lint":
        return changed
    return [p for p in changed if not p.startswith("docs/")]


def check_receipt(repo, receipt, head):
    name = receipt.name
    if receipt.errors:
        return f"receipt {name} {'; '.join(receipt.errors)}; paste it as scripts/receipt.sh printed it"
    missing = [f for f in REQUIRED if not receipt.fields.get(f)]
    if missing:
        return f"receipt {name} lacks {', '.join(missing)}; write it with scripts/receipt.sh"
    sha = receipt.fields["sha"]
    if receipt.fields["dirty"] != "no":
        return f"receipt {name} at {sha[:12]} ran on a dirty tree, so no commit holds what it tested; rerun it on a clean checkout of {head[:12]}"
    if receipt.fields["exit"] != "0":
        return (f"receipt {name} at {sha[:12]} records exit {receipt.fields['exit']}; rerun it at the head {head[:12]} "
                "until it passes, and put a red run from before a fix in prose")
    code, resolved = git(repo, "rev-parse", "--verify", "--quiet", f"{sha}^{{commit}}")
    if code != 0:
        return f"receipt {name} names {sha}, which is not a commit in this repository; push it, then rerun the receipt at the head {head[:12]}"
    resolved = resolved.strip()
    if resolved == head:
        return None
    changed = [p for p in must_git(repo, "diff", "--no-renames", "--name-only", resolved, head).split("\n") if p]
    code_paths = stale_paths(receipt, changed)
    if not code_paths:
        return None
    listed = ", ".join(code_paths[:MAX_LISTED_PATHS])
    more = len(code_paths) - MAX_LISTED_PATHS
    if more > 0:
        listed += f", and {more} more"
    return f"receipt {name} at {resolved[:12]} is stale: the head {head[:12]} changes code since then ({listed}); rerun it at the head"


def this_repo(repo, named):
    if named:
        return named.lower()
    if os.environ.get("GITHUB_REPOSITORY"):
        return os.environ["GITHUB_REPOSITORY"].lower()
    _, url = git(repo, "remote", "get-url", "origin")
    m = REMOTE.search(url.strip())
    return m.group(1).lower() if m else ""


def closed_issues(text, own):
    """Maps each issue a closing keyword in text names, as (repository, number), to the words that close it."""
    issues = {}
    for m in CLOSING.finditer(text):
        repo = (m.group("url") or m.group("repo") or own).lower()
        issues.setdefault((repo, m.group("number")), m.group(0))
    return issues


def check_closing(repo, prose, head, base, own):
    closed_by_body = closed_issues(INLINE_CODE.sub("", "\n".join(prose)), own)
    log = must_git(repo, "log", "--format=%H%x00%B%x1e", head, "--not", base)
    problems = []
    for entry in log.split("\x1e"):
        sha, _, message = entry.strip().partition("\x00")
        for (issue_repo, number), words in closed_issues(message, own).items():
            if (issue_repo, number) not in closed_by_body:
                label = f"#{number}" if issue_repo == own else f"{issue_repo}#{number}"
                problems.append(f'commit {sha[:12]} says "{words}", and the body closes no {label}; '
                                f"the squash would close it, so add it to the body or drop it from the commit")
    return problems


def main():
    parser = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    parser.add_argument("--body-file", required=True)
    parser.add_argument("--head", required=True)
    parser.add_argument("--base")
    parser.add_argument("--repo")
    parser.add_argument("-C", dest="repo_dir", default=".")
    args = parser.parse_args()

    with open(args.body_file, encoding="utf-8", errors="replace") as f:
        body = f.read().replace("\r\n", "\n")
    head = must_git(args.repo_dir, "rev-parse", "--verify", f"{args.head}^{{commit}}").strip()
    fences, prose = split_body(body)
    found = [parse_receipt(f) for f in fences if is_receipt(f)]
    problems = [p for p in (check_receipt(args.repo_dir, r, head) for r in found) if p]
    problems += [f"a receipt fence inside a quote or list item is not checked, so move it to the top level: {line.strip()}"
                 for line in prose if NESTED_RECEIPT.match(line)]
    if args.base:
        must_git(args.repo_dir, "rev-parse", "--verify", f"{args.base}^{{commit}}")
        problems += check_closing(args.repo_dir, prose, head, args.base, this_repo(args.repo_dir, args.repo))

    prefix = "::error::" if os.environ.get("GITHUB_ACTIONS") == "true" else ""
    for problem in problems:
        print(prefix + problem)
    if problems:
        return 1
    scope = " and every closing keyword" if args.base else ""
    print(f"{len(found)} receipt(s){scope} match the head {head[:12]}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
