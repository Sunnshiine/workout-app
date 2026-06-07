"""PR target resolution.

Maps an :class:`IssueContract` to a deterministic :class:`PrTarget`. The Python
runner is PR-only: a target is published through a pull request, never a direct
push, so a target that would push ``main`` is rejected. Most targets base on
``main``; a ``## Blocked by`` dependent instead bases on its chain root's durable
``ralph/issue-<root>`` branch (ADR-0008).
"""

from __future__ import annotations

from dataclasses import dataclass

from .contracts import IssueContract, parse_blocked_by
from .github import GitHubClient, GitHubClientError

BASE_BRANCH = "main"
_PRD_BRANCH_PREFIX = "ralph/prd-"
_ISSUE_BRANCH_PREFIX = "ralph/issue-"


@dataclass(frozen=True)
class PrTarget:
    """Immutable, fully resolved PR target for one issue."""

    branch: str
    base: str
    prd_number: int | None
    issue_number: int
    existing_pr_number: int | None = None

    @property
    def is_stacked_dependent(self) -> bool:
        """Whether this target stacks a ``## Blocked by`` dependent onto its root.

        A stacked dependent shares its chain root's durable branch and bases on
        it, so ``base == branch``. Standalone and root targets base on ``main``.
        """

        return self.base == self.branch


class TargetResolutionError(ValueError):
    """Raised when a target cannot be resolved safely (e.g. would push main)."""


def branch_for_contract(contract: IssueContract) -> str:
    """Return the deterministic branch name for ``contract``.

    PRD-scoped issues stack on ``ralph/prd-<prd_number>``; one-off issues use
    ``ralph/issue-<issue_number>``.
    """

    if contract.prd_number is not None:
        return f"{_PRD_BRANCH_PREFIX}{contract.prd_number}"
    return f"{_ISSUE_BRANCH_PREFIX}{contract.number}"


class TargetResolver:
    """Resolves :class:`PrTarget`s, looking up existing PRs through the seam."""

    def __init__(self, client: GitHubClient) -> None:
        self._client = client

    def resolve(self, contract: IssueContract) -> PrTarget:
        root_branch = self._stacked_root_branch(contract)
        if root_branch is not None:
            # A ``## Blocked by`` dependent stacks onto its chain root: it shares
            # the root's durable branch and bases on it (not on main). The
            # non-main base here is legitimate; only publishing main is forbidden.
            return PrTarget(
                branch=root_branch,
                base=root_branch,
                prd_number=contract.prd_number,
                issue_number=contract.number,
                existing_pr_number=self._existing_pr_number(root_branch),
            )

        branch = branch_for_contract(contract)
        _reject_main_publish(branch)
        return PrTarget(
            branch=branch,
            base=BASE_BRANCH,
            prd_number=contract.prd_number,
            issue_number=contract.number,
            existing_pr_number=self._existing_pr_number(branch),
        )

    def _stacked_root_branch(self, contract: IssueContract) -> str | None:
        """Return the chain root's branch for a stacked dependent, else None.

        PRD-scoped issues are never stacked. A non-PRD issue with an actionable
        ``## Blocked by`` dependency bases on the durable branch of the chain's
        transitive root (the eldest ancestor whose own blocker is ``None`` or
        already merged to ``main``). Standalone and root issues return None and
        fall back to their own ``ralph/issue-<n>`` branch on main.
        """

        if contract.prd_number is not None:
            return None

        blocker = self._actionable_blocker(contract.body)
        if blocker is None:
            return None

        root = self._walk_to_root(blocker)
        return f"{_ISSUE_BRANCH_PREFIX}{root}"

    def _walk_to_root(self, start: int) -> int:
        """Climb ``## Blocked by`` from ``start`` to the transitive chain root.

        The root is the eldest ancestor whose own blocker is ``None`` or already
        merged to ``main``. Visited numbers guard against a malformed cycle.
        """

        root = start
        seen: set[int] = set()
        while root not in seen:
            seen.add(root)
            blocker = self._actionable_blocker(self._body_of(root))
            if blocker is None:
                return root
            root = blocker
        return root

    def _actionable_blocker(self, body: str) -> int | None:
        """Return the first ``## Blocked by`` dependency not merged to ``main``.

        A dependency that is already ``CLOSED`` (merged to main) terminates the
        upward walk, so it is skipped. ``None`` means this issue is a chain root.
        """

        for dep in parse_blocked_by(body):
            if not self._is_merged_to_main(dep):
                return dep
        return None

    def _is_merged_to_main(self, number: int) -> bool:
        try:
            payload = self._client.view_issue(number)
        except GitHubClientError:
            return False
        return payload.get("state") == "CLOSED"

    def _body_of(self, number: int) -> str:
        try:
            payload = self._client.view_issue(number)
        except GitHubClientError:
            return ""
        body = payload.get("body")
        return body if isinstance(body, str) else ""

    def _existing_pr_number(self, branch: str) -> int | None:
        for pr in self._client.list_open_prs(head=branch):
            if pr.get("headRefName") != branch:
                continue
            number = pr.get("number")
            if isinstance(number, int) and not isinstance(number, bool):
                return number
        return None


def _reject_main_publish(branch: str) -> None:
    if branch == BASE_BRANCH:
        raise TargetResolutionError(
            "refusing to resolve a target that would publish to "
            f"{BASE_BRANCH!r}: the Python runner publishes only through pull "
            "requests on ralph/* branches."
        )
