#!/usr/bin/env python3
"""Refuse a landing that undoes a commit already on the base branch.

usage: scripts/landing-reverts-main.py BASE HEAD [--body-file FILE] [--allow N,...] [--window N] [--strict]

The landing is what a squash of HEAD onto BASE would leave: HEAD's tree when BASE is an ancestor of
HEAD, otherwise `git merge-tree --write-tree BASE HEAD`. Each -U0 hunk of BASE..landing is compared
with the last --window (40) first-parent commits on BASE. A hunk undoes commit X when 80% of its
significant lines (3 or more letters or digits) are X inverted, lines it removes that X added and
lines it adds that X removed. A removed line that reappears elsewhere in the landing is a move, not
an undo. A hunk is explained when one of the pull request's own non-merge commits made that same
edit, so a reviewer saw it; --strict drops that exemption.

The check fires for X when the landing undoes 5 or more of X's lines that no own commit explains,
as when a merge commit keeps the branch side of main's changes (#1012), or half of X's lines
whoever undid them, as when a stale tree is squashed onto a newer main.

A deliberate revert names its pull request on a line of the body, `Reverts #N` or GitHub's
`Reverts owner/repo#N`. --body-file reads those lines; --allow N,... adds more.

Exit 0 quiet, 1 the landing undoes a commit, 2 the check cannot run (git older than 2.38, a git
failure, or a landing that conflicts), and 3 the clone is too shallow to read every commit the
check needs, so fetch deeper and rerun.
"""
import argparse
import os
import re
import subprocess
import sys
from collections import Counter, defaultdict

MIN_GIT = (2, 38)
MATCH_SHARE = 0.8
MIN_UNEXPLAINED_LINES = 5
UNDONE_SHARE = 0.5
REVERTS = re.compile(r"^\s*Reverts\s+(?:[\w.-]+/[\w.-]+)?#(\d+)\b", re.MULTILINE)


def git(*args, check=True):
    r = subprocess.run(["git", *args], capture_output=True, text=True)
    if check and r.returncode != 0:
        print(f"git {' '.join(args)} failed: {r.stderr.strip()}", file=sys.stderr)
        sys.exit(2)
    return r


def require_git_version():
    out = git("version").stdout.strip()
    found = re.search(r"(\d+)\.(\d+)", out)
    if not found or tuple(map(int, found.groups())) < MIN_GIT:
        print(f"needs git 2.38 or later for merge-tree --write-tree; found {out}", file=sys.stderr)
        sys.exit(2)


def significant(line):
    return len(re.findall(r"[A-Za-z0-9]", line)) >= 3


def hunks(diff_text):
    """(path, removed lines, added lines) per -U0 hunk."""
    out, path, minus, plus, in_header = [], None, [], [], False

    def flush():
        if path and (minus or plus):
            out.append((path, minus, plus))

    for line in diff_text.splitlines():
        if line.startswith("diff --git"):
            flush()
            path, minus, plus, in_header = None, [], [], True
        elif in_header and (line.startswith("+++ ") or line.startswith("--- ")):
            if line[4:] != "/dev/null":
                path = line[6:]
        elif line.startswith("@@"):
            flush()
            minus, plus, in_header = [], [], False
        elif line.startswith("-"):
            minus.append(line[1:].strip())
        elif line.startswith("+"):
            plus.append(line[1:].strip())
    flush()
    return out


def commit_hunks(commit):
    return hunks(git("show", "-U0", "--format=", "--no-renames", commit).stdout)


def require_history(window, pr_commits):
    """A shallow-boundary commit shows its whole tree as added, so every check against it is wrong."""
    shallow_file = git("rev-parse", "--git-path", "shallow").stdout.strip()
    if not os.path.exists(shallow_file):
        return
    with open(shallow_file) as f:
        boundary = set(f.read().split())
    cut = [c for c in window + pr_commits if c in boundary]
    if cut:
        print(f"the clone is too shallow: {cut[0][:8]} has no parent here; fetch deeper and rerun", file=sys.stderr)
        sys.exit(3)


def landing_tree(base, head):
    if git("merge-base", "--is-ancestor", base, head, check=False).returncode == 0:
        return git("rev-parse", f"{head}^{{tree}}").stdout.strip()
    r = git("merge-tree", "--write-tree", "--name-only", base, head, check=False)
    if r.returncode == 1:
        conflicted = r.stdout.split("\n\n")[0].splitlines()[1:]
        print(f"the landing conflicts: {head[:8]} does not merge cleanly onto {base[:8]} in {', '.join(conflicted)}")
        sys.exit(2)
    if r.returncode != 0:
        print(f"git merge-tree failed: {r.stderr.strip()}", file=sys.stderr)
        sys.exit(2)
    return r.stdout.split()[0]


def own_edits(pr_commits):
    """path -> (lines the PR's own commits removed, lines they added)."""
    out = defaultdict(lambda: (set(), set()))
    for c in pr_commits:
        for path, minus, plus in commit_hunks(c):
            out[path][0].update(m for m in minus if significant(m))
            out[path][1].update(p for p in plus if significant(p))
    return out


def findings(base, landing, window, allow, own):
    by_commit = {}
    for c in window:
        files = defaultdict(lambda: (set(), set()))
        for path, minus, plus in commit_hunks(c):
            files[path][0].update(m for m in minus if significant(m))
            files[path][1].update(p for p in plus if significant(p))
        by_commit[c] = files
    undone, unexplained = defaultdict(set), defaultdict(set)
    landing_hunks = hunks(git("diff", "-U0", "--no-renames", base, landing).stdout)
    all_added = Counter(p for _, _, plus in landing_hunks for p in plus)
    for path, minus, plus in landing_hunks:
        elsewhere = all_added - Counter(plus)
        removed = {m for m in minus if significant(m) and not elsewhere[m]}
        added = {p for p in plus if significant(p)}
        if not removed and not added:
            continue
        own_removed, own_added = own[path] if own is not None and path in own else (None, None)
        explained = own_removed is not None and removed <= own_removed and added <= own_added
        for c, files in by_commit.items():
            if path not in files:
                continue
            c_removed, c_added = files[path]
            lines = {(path, "-", m) for m in removed & c_added} | {(path, "+", p) for p in added & c_removed}
            if len(lines) >= MATCH_SHARE * (len(removed) + len(added)):
                undone[c] |= lines
                if not explained:
                    unexplained[c] |= lines
                break
    out = []
    for c, lines in undone.items():
        subject = git("log", "-1", "--format=%s", c).stdout.strip()
        pr = (re.findall(r"\(#(\d+)\)", subject) or ["?"])[-1]
        size = sum(len(m) + len(a) for m, a in by_commit[c].values())
        if pr in allow:
            continue
        if len(unexplained[c]) < MIN_UNEXPLAINED_LINES and len(lines) < UNDONE_SHARE * size:
            continue
        out.append((c, pr, subject, len(lines), size, Counter(p for p, _, _ in lines)))
    return out


def parse_args():
    p = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    p.add_argument("base")
    p.add_argument("head")
    p.add_argument("--body-file")
    p.add_argument("--allow", default="")
    p.add_argument("--window", type=int, default=40)
    p.add_argument("--strict", action="store_true")
    args = p.parse_args()
    allow = {n for n in args.allow.split(",") if n}
    if args.body_file:
        with open(args.body_file) as f:
            allow |= set(REVERTS.findall(f.read()))
    return args, allow


def main():
    args, allow = parse_args()
    require_git_version()
    base, head = (git("rev-parse", "--verify", f"{a}^{{commit}}").stdout.strip() for a in (args.base, args.head))
    window = git("rev-list", "--first-parent", f"--max-count={args.window}", base).stdout.split()
    pr_commits = git("rev-list", f"{base}..{head}").stdout.split()
    require_history(window, pr_commits)
    landing = landing_tree(base, head)
    non_merges = git("rev-list", "--no-merges", f"{base}..{head}").stdout.split()
    own = None if args.strict else own_edits(non_merges)
    found = findings(base, landing, window, allow, own)
    for c, pr, subject, n, size, paths in found:
        print(f"revert: the landing undoes #{pr} {n}/{size} lines ({c[:8]} {subject})")
        for path, count in sorted(paths.items()):
            print(f"  {path} ({count} lines)")
    if found:
        print(
            "If a revert is deliberate, add a line 'Reverts #N' to the pull request body, then push, an empty"
            " commit if nothing changed, so the check reruns.",
            file=sys.stderr,
        )
        sys.exit(1)
    print(f"quiet: {head[:8]} onto {base[:8]} undoes none of the last {len(window)} commits on the base")


if __name__ == "__main__":
    main()
