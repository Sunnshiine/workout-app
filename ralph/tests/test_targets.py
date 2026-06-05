from __future__ import annotations

import unittest
from dataclasses import FrozenInstanceError

from ralph.orchestrator.contracts import IssueContract
from ralph.orchestrator.github import FakeGitHubClient
from ralph.orchestrator.targets import (
    BASE_BRANCH,
    PrTarget,
    TargetResolutionError,
    TargetResolver,
    branch_for_contract,
)


def _contract(number: int, prd_number: int | None = None) -> IssueContract:
    return IssueContract(
        number=number,
        title=f"Issue {number}",
        body="",
        prd_number=prd_number,
    )


class BranchNamingTests(unittest.TestCase):
    def test_prd_issue_uses_prd_branch(self) -> None:
        self.assertEqual(branch_for_contract(_contract(40, prd_number=7)), "ralph/prd-7")

    def test_one_off_issue_uses_issue_branch(self) -> None:
        self.assertEqual(branch_for_contract(_contract(40)), "ralph/issue-40")


class TargetResolverTests(unittest.TestCase):
    def test_prd_routing(self) -> None:
        resolver = TargetResolver(FakeGitHubClient())
        target = resolver.resolve(_contract(40, prd_number=7))
        self.assertIsInstance(target, PrTarget)
        self.assertEqual(target.branch, "ralph/prd-7")
        self.assertEqual(target.base, BASE_BRANCH)
        self.assertEqual(target.prd_number, 7)
        self.assertEqual(target.issue_number, 40)

    def test_one_off_routing(self) -> None:
        resolver = TargetResolver(FakeGitHubClient())
        target = resolver.resolve(_contract(40))
        self.assertEqual(target.branch, "ralph/issue-40")
        self.assertIsNone(target.prd_number)

    def test_branch_reuse_when_pr_exists(self) -> None:
        client = FakeGitHubClient(open_prs=[{"number": 88, "headRefName": "ralph/prd-7"}])
        target = TargetResolver(client).resolve(_contract(40, prd_number=7))
        self.assertEqual(target.existing_pr_number, 88)

    def test_no_existing_pr_returns_none(self) -> None:
        client = FakeGitHubClient(open_prs=[{"number": 88, "headRefName": "ralph/prd-99"}])
        target = TargetResolver(client).resolve(_contract(40, prd_number=7))
        self.assertIsNone(target.existing_pr_number)

    def test_base_is_always_main(self) -> None:
        target = TargetResolver(FakeGitHubClient()).resolve(_contract(1, prd_number=2))
        self.assertEqual(target.base, "main")

    def test_target_is_immutable(self) -> None:
        target = TargetResolver(FakeGitHubClient()).resolve(_contract(1))
        with self.assertRaises(FrozenInstanceError):
            target.branch = "other"  # type: ignore[misc]


class MainRejectionTests(unittest.TestCase):
    def test_resolving_main_branch_is_rejected(self) -> None:
        # A contrived contract that would name the base branch must be refused;
        # the runner never pushes main.
        from ralph.orchestrator import targets as targets_module

        bad = IssueContract(number=1, title="t", body="")
        original = targets_module.branch_for_contract

        try:
            targets_module.branch_for_contract = lambda _c: BASE_BRANCH
            resolver = TargetResolver(FakeGitHubClient())
            with self.assertRaises(TargetResolutionError) as ctx:
                resolver.resolve(bad)
            self.assertIn("pull request", str(ctx.exception))
        finally:
            targets_module.branch_for_contract = original


if __name__ == "__main__":
    unittest.main()
