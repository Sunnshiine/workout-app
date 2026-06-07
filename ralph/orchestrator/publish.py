"""Successful publish lifecycle: draft -> ready PR branches.

This slice owns only the *successful* path (issue #209). Blocked/repair rescue
PRs land in later issues. Two collaborators split the work:

- :class:`IssuePublisher` applies the success label transition on the issue.
  It removes ``ready-for-agent``, adds ``agent-implemented``, and leaves the
  issue OPEN. It never adds ``ready-for-human`` and never closes the issue;
  GitHub closes the issue when the PR merges via the ``Closes #<issue>`` keyword
  carried in the successful integration commit message.
- :class:`PullRequestPublisher` commits the integration tree, pushes the PR
  branch through the injectable git runner, then creates a DRAFT PR on the first
  push for a branch (reusing the existing PR by head branch on later pushes).
  A one-off PR is marked ready once its single issue passes; a PRD stack PR is
  marked ready only once every known scoped child issue is implemented.

All GitHub mutations flow through the :class:`GitHubClient` seam and all git
operations through an injectable runner, so tests never touch real ``gh``, real
git, or the network.
"""

from __future__ import annotations

import re
from collections.abc import Callable, Sequence
from dataclasses import dataclass

from .contracts import IssueContract, capture_issue_contract, parse_prd_number
from .github import GitHubClient, _label_names
from .targets import PrTarget

# Issue labels (see spec "Issue labels [CHANGED]").
LABEL_READY_FOR_AGENT = "ready-for-agent"
LABEL_AGENT_ACTIVE = "agent-active"
LABEL_AGENT_IMPLEMENTED = "agent-implemented"
LABEL_READY_FOR_HUMAN = "ready-for-human"
LABEL_AGENT_BLOCKED = "agent-blocked"

# PR label applied when a successful PR becomes ready for review.
LABEL_AGENT_READY_FOR_REVIEW = "agent-ready-for-review"

# Labels that, when present on any scoped child, keep a PRD stack PR in draft.
_PRD_BLOCKING_CHILD_LABELS = frozenset(
    {LABEL_READY_FOR_AGENT, LABEL_AGENT_ACTIVE, LABEL_READY_FOR_HUMAN, LABEL_AGENT_BLOCKED}
)


# A git runner takes the argv that follows ``git`` and returns success/failure.
# Real use wraps ``subprocess.run`` rooted at the worktree; tests inject a fake.
GitRunner = Callable[[Sequence[str]], "GitOutcome"]


@dataclass(frozen=True)
class GitOutcome:
    """Outcome of one git invocation run through the publish git seam."""

    returncode: int
    stdout: str = ""
    stderr: str = ""

    @property
    def ok(self) -> bool:
        return self.returncode == 0


class PublishError(RuntimeError):
    """Raised when a successful publish cannot complete (commit/push failure)."""


class ClaimError(RuntimeError):
    """Raised when Ralph cannot exclusively claim an issue before agent work."""


def integration_commit_message(issue_number: int, engine: str) -> str:
    """Build the successful integration commit message with a closing keyword.

    Mirrors the spec "Successful integration commit [CHANGED]" shape; the
    ``Closes #<issue>`` trailer is what lets GitHub close the issue on merge.
    """

    subject = f"merge: implement issue #{issue_number} via Ralph ({engine})"
    return f"{subject}\n\nCloses #{issue_number}\n"


class IssueClaimer:
    """Moves a ready issue into Ralph's claimed-but-unpublished state."""

    def __init__(self, client: GitHubClient) -> None:
        self._client = client

    def claim(self, issue_number: int) -> IssueContract:
        """Claim ``issue_number`` and return the post-claim issue contract.

        Ralph must claim before creating a worktree. The label edit is the
        durable queue lock: once ``ready-for-agent`` is removed, later loop
        iterations cannot select this issue again unless a human requeues it.
        """

        before = self._client.view_issue(issue_number)
        if not _is_claimable(before):
            raise ClaimError(f"issue #{issue_number} is no longer ready for Ralph to claim")

        self._client.edit_issue_labels(
            issue_number,
            add=[LABEL_AGENT_ACTIVE],
            remove=[LABEL_READY_FOR_AGENT],
        )
        after = self._client.view_issue(issue_number)
        labels = _label_names(after.get("labels"))
        if LABEL_AGENT_ACTIVE not in labels or LABEL_READY_FOR_AGENT in labels:
            raise ClaimError(
                f"issue #{issue_number} claim did not converge: "
                "expected agent-active without ready-for-agent"
            )
        if labels & {LABEL_AGENT_IMPLEMENTED, LABEL_READY_FOR_HUMAN, LABEL_AGENT_BLOCKED}:
            raise ClaimError(f"issue #{issue_number} has conflicting lifecycle labels")

        return capture_issue_contract(self._client, issue_number)


class IssuePublisher:
    """Applies the success label transition to an issue.

    On success: remove ``ready-for-agent``, add ``agent-implemented``, leave the
    issue OPEN. Never adds ``ready-for-human`` and never closes the issue.
    """

    def __init__(self, client: GitHubClient) -> None:
        self._client = client

    def mark_implemented(self, issue_number: int) -> None:
        self._client.remove_issue_labels(
            issue_number,
            [
                LABEL_READY_FOR_AGENT,
                LABEL_AGENT_ACTIVE,
                LABEL_READY_FOR_HUMAN,
                LABEL_AGENT_BLOCKED,
            ],
        )
        self._client.add_issue_labels(issue_number, [LABEL_AGENT_IMPLEMENTED])


class PullRequestPublisher:
    """Commits, pushes, and creates/reuses the draft-or-ready PR for an issue."""

    def __init__(self, client: GitHubClient, runner: GitRunner) -> None:
        self._client = client
        self._runner = runner

    def publish(self, contract: IssueContract, target: PrTarget, *, engine: str) -> int:
        """Commit and push the integration tree, then create or reuse its PR.

        Returns the PR number. The commit carries ``Closes #<issue>``; the PR is
        created as a draft on first push and reused by head branch afterwards.
        Readiness is decided separately: a one-off PR can be made ready once its
        issue passes, while a PRD stack PR waits for every scoped child.
        """

        self._commit_and_push(contract.number, target.branch, engine)
        pr = self._client.find_pr_by_head_branch(target.branch)
        if pr is not None:
            if target.is_stacked_dependent:
                self._accumulate_closes(pr, contract.number)
            return _pr_number(pr)
        return self._create_draft_pr(contract, target)

    def update_readiness(self, contract: IssueContract, pr_number: int) -> bool:
        """Mark the PR ready for review if its scoped issue set is complete.

        A one-off PR (no PRD) is ready as soon as its issue passes. A PRD stack
        PR is ready only when every known scoped child issue is implemented and
        none remain blocking. Returns whether the PR was made ready on this call.
        """

        if not self._is_ready(contract):
            return False
        self._client.mark_pr_ready(pr_number)
        self._client.add_pr_labels(pr_number, [LABEL_AGENT_READY_FOR_REVIEW])
        return True

    def _is_ready(self, contract: IssueContract) -> bool:
        if contract.prd_number is None:
            return True
        return self._prd_children_complete(contract.prd_number)

    def _prd_children_complete(self, prd_number: int) -> bool:
        children = _scoped_children(self._client, prd_number)
        if not children:
            # No known children yet -> nothing to stack as ready; stay draft.
            return False
        for child in children:
            labels = _label_names(child.get("labels"))
            if LABEL_AGENT_IMPLEMENTED not in labels:
                return False
            if labels & _PRD_BLOCKING_CHILD_LABELS:
                return False
        return True

    def _create_draft_pr(self, contract: IssueContract, target: PrTarget) -> int:
        return self._client.create_pr(
            draft=True,
            base=target.base,
            head=target.branch,
            title=_pr_title(contract),
            body=integration_commit_message(contract.number, engine="").strip(),
        )

    def _commit_and_push(self, issue_number: int, branch: str, engine: str) -> None:
        message = integration_commit_message(issue_number, engine)
        self._run(["commit", "--allow-empty", "-m", message], "commit integration tree")
        self._run(["push", "--force-with-lease", "origin", branch], f"push {branch}")

    def _accumulate_closes(self, pr: dict, issue_number: int) -> None:
        """Append a ``Closes #<n>`` line to the root PR body, never duplicating.

        A stacked dependent's work is squashed onto the root branch; the root PR
        accretes one ``Closes`` line per landed issue. If the issue is already
        referenced (e.g. a retried publish) the body is left untouched.
        """

        body = pr.get("body") or ""
        updated = _append_closes_line(body, issue_number)
        if updated == body:
            return
        self._client.edit_pr_body(_pr_number(pr), updated)

    def _run(self, args: Sequence[str], what: str) -> None:
        result = self._runner(list(args))
        if not result.ok:
            detail = result.stderr.strip() or result.stdout.strip()
            raise PublishError(f"failed to {what} (git exit {result.returncode}): {detail}")


def _append_closes_line(body: str, issue_number: int) -> str:
    """Return ``body`` with a ``Closes #<n>`` line appended, or unchanged.

    The body is unchanged if it already references ``Closes #<n>`` exactly (as a
    whole word, so ``Closes #22`` does not satisfy ``Closes #222``).
    """

    pattern = re.compile(rf"Closes #{issue_number}\b")
    if pattern.search(body):
        return body
    separator = "" if body.endswith("\n") or not body else "\n"
    return f"{body}{separator}Closes #{issue_number}\n"


def _pr_title(contract: IssueContract) -> str:
    return f"#{contract.number} {contract.title}".strip()


def _pr_number(pr: dict) -> int:
    number = pr.get("number")
    if isinstance(number, bool) or not isinstance(number, int):
        raise PublishError(f"PR is missing an integer number: {pr!r}")
    return number


def _scoped_children(client: GitHubClient, prd_number: int) -> list[dict]:
    """Known scoped child issues for ``PRD: #<prd_number>``.

    A child is any non-PRD open issue whose body contains the exact
    ``PRD: #<prd_number>`` directive. The PRD issue itself is excluded.
    """

    children: list[dict] = []
    for issue in client.list_open_issues():
        number = issue.get("number")
        if number == prd_number:
            continue
        body = issue.get("body")
        if not isinstance(body, str):
            continue
        if parse_prd_number(body) == prd_number:
            children.append(issue)
    return children


def _is_claimable(issue: dict) -> bool:
    if issue.get("state", "OPEN") != "OPEN":
        return False
    labels = _label_names(issue.get("labels"))
    if LABEL_READY_FOR_AGENT not in labels:
        return False
    if labels & {
        LABEL_AGENT_ACTIVE,
        LABEL_AGENT_IMPLEMENTED,
        LABEL_READY_FOR_HUMAN,
        LABEL_AGENT_BLOCKED,
    }:
        return False
    return _has_actionable_contract(issue)


def _has_actionable_contract(issue: dict) -> bool:
    body = issue.get("body")
    if isinstance(body, str) and body.strip():
        return True
    comments = issue.get("comments")
    if not isinstance(comments, list):
        return False
    for comment in comments:
        if not isinstance(comment, dict):
            continue
        text = comment.get("body")
        if isinstance(text, str) and "Agent Brief" in text:
            return True
    return False
