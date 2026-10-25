#!/usr/bin/env python3
"""Refuse a landing that undoes a commit already on the base branch.

usage: scripts/landing-reverts-main.py BASE HEAD [--body-file FILE] [--allow N,...] [--window N] [--strict]

The landing is what a squash of HEAD onto BASE would leave: HEAD's tree when BASE is an ancestor of
HEAD, otherwise `git merge-tree --write-tree BASE HEAD`. Each -U0 hunk of BASE..landing is compared
with the last --window (40) first-parent commits on BASE. A hunk undoes commit X when 80% of its
significant lines (3 or more letters or digits) are X inverted: lines it removes that `git blame
--first-parent` on BASE says X added, and lines it adds whose text X removed. A removed line that
reappears elsewhere in the landing is a move, not an undo. A hunk is explained when one of the pull
request's own non-merge commits made that same edit, so a reviewer saw it; --strict drops that
exemption.

The check fires for X when the landing undoes 5 or more of X's lines that no own commit explains,
as when a merge commit keeps the branch side of main's changes (#1012), or half of X's lines
whoever undid them, as when a stale tree is squashed onto a newer main.

A deliberate revert names what it reverts on a line of the body outside a code block: `Reverts #N`,
GitHub's `Reverts owner/repo#N` when owner/repo is the origin remote, or `Reverts <sha>` for a commit
with no PR number. One line may list several, as `Reverts #10, #11`. --body-file reads those lines;
--allow N,... adds more, PR numbers or SHA prefixes.

Exit 0 quiet, 1 the landing undoes a commit, 2 the check cannot run (git older than 2.38, a git
failure, or a landing that conflicts), and 3 the clone is too shallow to read every commit the
check needs or the merge base, so fetch deeper and rerun.
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
REVERTS = re.compile(r" {0,3}reverts:?\s+(.*)", re.IGNORECASE)
REVERTED = re.compile(r"(?:([\w.-]+/[\w.-]+)?#(\d+)|([0-9a-f]{7,40}))[.,;]?", re.IGNORECASE)
FENCE = re.compile(r" {0,3}(```|~~~)")
HUNK = re.compile(r"@@ -(\d+)")


def git(*args, check=True):
    r = subprocess.run(["git", *args], capture_output=True, encoding="utf-8", errors="surrogateescape")
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


C_ESCAPES = {b"a": b"\a", b"b": b"\b", b"t": b"\t", b"n": b"\n", b"v": b"\v", b"f": b"\f", b"r": b"\r",
             b'"': b'"', b"\\": b"\\"}


def header_path(name):
    """The path in a --- or +++ line, which git ends with a tab when it holds a space and quotes when it holds
    a control character, quote, or backslash."""
    name = name.removesuffix("\t")
    if name.startswith('"'):
        raw = re.sub(rb"\\([0-7]{3}|.)", lambda m: bytes([int(m[1], 8)]) if len(m[1]) == 3 else C_ESCAPES[m[1]],
                     name[1:-1].encode("utf-8", "surrogateescape"))
        name = raw.decode("utf-8", "surrogateescape")
    return name[2:]


def hunks(diff_text):
    """(path, first removed line's number in the old file, removed lines, added lines) per -U0 hunk."""
    out, path, start, minus, plus, in_header = [], None, 0, [], [], False

    def flush():
        if path and (minus or plus):
            out.append((path, start, minus, plus))

    for line in diff_text.splitlines():
        if line.startswith("diff --git"):
            flush()
            path, minus, plus, in_header = None, [], [], True
        elif in_header and (line.startswith("+++ ") or line.startswith("--- ")):
            if line[4:] != "/dev/null":
                path = header_path(line[4:])
        elif line.startswith("@@"):
            flush()
            start, minus, plus, in_header = int(HUNK.match(line).group(1)), [], [], False
        elif line.startswith("-"):
            minus.append(line[1:].strip())
        elif line.startswith("+"):
            plus.append(line[1:].strip())
    flush()
    return out


def diff(*args):
    return hunks(git("-c", "core.quotePath=false", *args).stdout)


def commit_hunks(commit):
    return diff("show", "-U0", "--format=", "--no-renames", "--diff-merges=first-parent", commit)


def require_history(base, head, window, pr_commits):
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
    if git("merge-base", base, head, check=False).returncode != 0:
        print(f"the clone is too shallow: {base[:8]} and {head[:8]} share no commit here; fetch deeper and rerun",
              file=sys.stderr)
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
        for path, _, minus, plus in commit_hunks(c):
            out[path][0].update(m for m in minus if significant(m))
            out[path][1].update(p for p in plus if significant(p))
    return out


def line_authors(base, bound, wanted):
    """(path, line number on base) -> the first-parent commit on base that added the line.

    Text alone misattributes: when a recent commit adds a copy of an old block and the landing
    deletes the old copy, every deleted line matches the recent commit's text.
    """
    out = {}
    for path, numbers in wanted.items():
        ranges = []
        for n in sorted(numbers):
            if ranges and ranges[-1][1] == n - 1:
                ranges[-1][1] = n
            else:
                ranges.append([n, n])
        spans = [arg for a, b in ranges for arg in ("-L", f"{a},{b}")]
        revs = f"{bound}..{base}" if bound else base
        for line in git("blame", "--first-parent", "--porcelain", *spans, revs, "--", path).stdout.splitlines():
            found = re.match(r"([0-9a-f]{40}) \d+ (\d+)", line)
            if found:
                out[(path, int(found.group(2)))] = found.group(1)
    return out


def findings(base, landing, window, bound, own):
    by_commit = {}
    for c in window:
        files = defaultdict(lambda: (set(), set()))
        for path, _, minus, plus in commit_hunks(c):
            files[path][0].update(m for m in minus if significant(m))
            files[path][1].update(p for p in plus if significant(p))
        by_commit[c] = files
    window_added = defaultdict(set)
    for files in by_commit.values():
        for path, (_, c_added) in files.items():
            window_added[path] |= c_added
    landing_hunks = diff("diff", "-U0", "--no-renames", base, landing)
    all_added = Counter(p for _, _, _, plus in landing_hunks for p in plus)
    wanted, rows = defaultdict(set), []
    for path, start, minus, plus in landing_hunks:
        elsewhere = all_added - Counter(plus)
        removed = [(start + i, m) for i, m in enumerate(minus) if significant(m) and not elsewhere[m]]
        added = {p for p in plus if significant(p)}
        if removed or added:
            rows.append((path, removed, added))
            wanted[path].update(n for n, m in removed if m in window_added[path])
    author = line_authors(base, bound, {p: ns for p, ns in wanted.items() if ns})
    undone, unexplained = defaultdict(set), defaultdict(set)
    for path, removed, added in rows:
        removed_text = {m for _, m in removed}
        own_removed, own_added = own[path] if own is not None and path in own else (None, None)
        explained = own_removed is not None and removed_text <= own_removed and added <= own_added
        for c, files in by_commit.items():
            if path not in files:
                continue
            c_removed, _ = files[path]
            lines = {(path, "-", m) for n, m in removed if author.get((path, n)) == c}
            lines |= {(path, "+", p) for p in added & c_removed}
            if lines and len(lines) >= MATCH_SHARE * (len(removed_text) + len(added)):
                undone[c] |= lines
                if not explained:
                    unexplained[c] |= lines
                break
    out = []
    for c, lines in undone.items():
        size = sum(len(m) + len(a) for m, a in by_commit[c].values())
        if len(unexplained[c]) >= MIN_UNEXPLAINED_LINES or len(lines) >= UNDONE_SHARE * size:
            out.append((c, len(lines), size, Counter(p for p, _, _ in lines)))
    return out


def origin_repo():
    url = git("remote", "get-url", "origin", check=False).stdout.strip()
    found = re.search(r"github\.com[:/]([\w.-]+/[\w.-]+?)(?:\.git)?/?$", url)
    return found.group(1).lower() if found else None


def body_reverts(text, repo):
    """What a body's Reverts lines name: PR numbers and SHA prefixes. Lines inside a code block are examples."""
    out, fence = set(), None
    for line in text.splitlines():
        opened = FENCE.match(line)
        if opened:
            if fence is None:
                fence = opened.group(1)
            elif opened.group(1) == fence:
                fence = None
            continue
        found = None if fence else REVERTS.match(line)
        if not found:
            continue
        for word in re.split(r"[\s,]+", found.group(1)):
            if word.lower() == "and" or not word:
                continue
            ref = REVERTED.fullmatch(word)
            if not ref:
                break
            other_repo, number, sha = ref.groups()
            if number and (other_repo is None or other_repo.lower() == repo):
                out.add(number)
            elif sha:
                out.add(sha.lower())
    return out


def allowed(commit, pr, allow):
    return pr in allow or any(len(a) >= 7 and commit.startswith(a) for a in allow)


def parse_args():
    p = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    p.add_argument("base")
    p.add_argument("head")
    p.add_argument("--body-file")
    p.add_argument("--allow", default="")
    p.add_argument("--window", type=int, default=40)
    p.add_argument("--strict", action="store_true")
    args = p.parse_args()
    allow = {n.strip().lower() for n in args.allow.split(",") if n.strip()}
    if args.body_file:
        with open(args.body_file, encoding="utf-8", errors="replace") as f:
            allow |= body_reverts(f.read(), origin_repo())
    return args, allow


def main():
    args, allow = parse_args()
    require_git_version()
    base, head = (git("rev-parse", "--verify", f"{a}^{{commit}}").stdout.strip() for a in (args.base, args.head))
    window = git("rev-list", "--first-parent", f"--max-count={args.window + 1}", base).stdout.split()
    window, bound = window[: args.window], (window[args.window:] or [None])[0]
    pr_commits = git("rev-list", f"{base}..{head}").stdout.split()
    require_history(base, head, window, pr_commits)
    landing = landing_tree(base, head)
    non_merges = git("rev-list", "--no-merges", f"{base}..{head}").stdout.split()
    own = None if args.strict else own_edits(non_merges)
    found = False
    for c, n, size, paths in findings(base, landing, window, bound, own):
        subject = git("log", "-1", "--format=%s", c).stdout.strip()
        pr = (re.findall(r"\(#(\d+)\)", subject) or [None])[-1]
        if allowed(c, pr, allow):
            continue
        found = True
        print(f"revert: the landing undoes {f'#{pr}' if pr else c[:8]} {n}/{size} lines ({c[:8]} {subject})")
        for path, count in sorted(paths.items()):
            print(f"  {path} ({count} lines)")
    if found:
        print(
            "If a revert is deliberate, add a line 'Reverts #N' to the pull request body, or 'Reverts <sha>'"
            " for a commit with no PR number, then push, an empty commit if nothing changed, so the check"
            " reruns.",
            file=sys.stderr,
        )
        sys.exit(1)
    print(f"quiet: {head[:8]} onto {base[:8]} undoes none of the last {len(window)} commits on the base")


if __name__ == "__main__":
    main()
