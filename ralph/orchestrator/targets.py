"""PR target resolution.

Maps an :class:`IssueContract` to a deterministic :class:`PrTarget`. The Python
runner is PR-only: every target bases on ``main`` and is published through a
pull request. There is no direct-main or direct-branch publish path, so a target
that would push ``main`` is rejected.
"""

from __future__ import annotations

from dataclasses import dataclass

from .contracts import IssueContract
from .github import GitHubClient

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
        branch = branch_for_contract(contract)
        _reject_main_publish(branch)
        return PrTarget(
            branch=branch,
            base=BASE_BRANCH,
            prd_number=contract.prd_number,
            issue_number=contract.number,
            existing_pr_number=self._existing_pr_number(branch),
        )

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
