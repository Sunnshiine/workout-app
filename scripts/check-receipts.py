#!/usr/bin/env python3
"""Check a PR body's receipts against the head, and its commits' closing keywords against the body.

usage: scripts/check-receipts.py --body-file FILE --head SHA [--base REF] [-C DIR]

A receipt is a fenced block with the info string `receipt`, as scripts/receipt.sh writes it. Each
receipt fails when a field is missing, when it says dirty: yes, when its sha is not a commit in this
repository (in CI, one never pushed to GitHub), or when its tree differs from HEAD's in a path
outside docs/ and *.md. The trees are compared, not the history, so a receipt survives a docs-only
commit, merge, or rebase. A merge of the base that brings code in makes every earlier receipt stale.

With --base, every commit on HEAD and not on REF that carries a closing keyword (`Fixes
#N`, `closes #N`, `resolved: owner/repo#N`) fails unless the body closes #N too. The repository
squashes with the commit messages as the body, so such a commit closes #N when the PR lands
whatever the PR body says.

Exit 0 when every check passes, 1 when one fails, and 2 on bad arguments or a git failure.
"""
import argparse
import os
import re
import subprocess
import sys

FIELDS = ("name", "command", "sha", "dirty", "exit")
FENCE_OPEN = re.compile(r" {0,3}```receipt[ \t]*$")
FENCE_CLOSE = re.compile(r" {0,3}```[ \t]*$")
FIELD = re.compile(r"([a-z]+):[ \t]?(.*)")
CLOSING = re.compile(r"\b(?:close[sd]?|fix(?:e[sd])?|resolve[sd]?):?[ \t]+(?:[\w.-]+/[\w.-]+)?#(\d+)\b", re.IGNORECASE)
MAX_LISTED_PATHS = 3


def git(repo, *args):
    r = subprocess.run(["git", "-C", repo, *args], capture_output=True, encoding="utf-8", errors="replace")
    return r.returncode, r.stdout


def must_git(repo, *args):
    code, out = git(repo, *args)
    if code != 0:
        print(f"git {' '.join(args)} failed in {repo}", file=sys.stderr)
        sys.exit(2)
    return out


def receipts(body):
    found, block = [], None
    for line in body.splitlines():
        if block is None:
            if FENCE_OPEN.match(line):
                block = {}
        elif FENCE_CLOSE.match(line):
            found.append(block)
            block = None
        else:
            field = FIELD.match(line.strip())
            if field:
                block.setdefault(field.group(1), field.group(2).strip())
    if block is not None:
        found.append(block)
    return found


def is_code(path):
    return not (path.startswith("docs/") or path.endswith(".md"))


def check_receipt(repo, receipt, head):
    name = receipt.get("name") or "(unnamed)"
    missing = [f for f in FIELDS if not receipt.get(f)]
    if missing:
        return f"receipt {name} lacks {', '.join(missing)}; write it with scripts/receipt.sh"
    sha = receipt["sha"]
    if receipt["dirty"] != "no":
        return f"receipt {name} at {sha[:12]} ran on a dirty tree, so no commit holds what it tested; rerun it on a clean checkout of {head[:12]}"
    code, resolved = git(repo, "rev-parse", "--verify", "--quiet", f"{sha}^{{commit}}")
    if code != 0:
        return f"receipt {name} names {sha}, which is not a commit in this repository; push it, then rerun the receipt at the head {head[:12]}"
    resolved = resolved.strip()
    if resolved == head:
        return None
    changed = must_git(repo, "diff", "--no-renames", "--name-only", resolved, head).split("\n")
    code_paths = [p for p in changed if p and is_code(p)]
    if not code_paths:
        return None
    listed = ", ".join(code_paths[:MAX_LISTED_PATHS])
    more = len(code_paths) - MAX_LISTED_PATHS
    if more > 0:
        listed += f", and {more} more"
    return f"receipt {name} at {resolved[:12]} is stale: the head {head[:12]} changes code since then ({listed}); rerun it at the head"


def check_closing(repo, body, head, base):
    closed_by_body = {m.group(1) for m in CLOSING.finditer(body)}
    log = must_git(repo, "log", "--format=%H%x00%B%x1e", head, "--not", base)
    problems = []
    for entry in log.split("\x1e"):
        sha, _, message = entry.strip().partition("\x00")
        for m in CLOSING.finditer(message):
            if m.group(1) not in closed_by_body:
                problems.append(f'commit {sha[:12]} says "{m.group(0)}", and the body closes no #{m.group(1)}; '
                                f"the squash would close it, so add it to the body or drop it from the commit")
    return problems


def main():
    parser = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    parser.add_argument("--body-file", required=True)
    parser.add_argument("--head", required=True)
    parser.add_argument("--base")
    parser.add_argument("-C", dest="repo", default=".")
    args = parser.parse_args()

    with open(args.body_file, encoding="utf-8", errors="replace") as f:
        body = f.read().replace("\r\n", "\n")
    head = must_git(args.repo, "rev-parse", "--verify", f"{args.head}^{{commit}}").strip()
    found = receipts(body)
    problems = [p for p in (check_receipt(args.repo, r, head) for r in found) if p]
    if args.base:
        must_git(args.repo, "rev-parse", "--verify", f"{args.base}^{{commit}}")
        problems += check_closing(args.repo, body, head, args.base)

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
