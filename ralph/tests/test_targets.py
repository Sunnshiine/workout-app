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


def _contract(
    number: int,
    prd_number: int | None = None,
    body: str = "",
) -> IssueContract:
    return IssueContract(
        number=number,
        title=f"Issue {number}",
        body=body,
        prd_number=prd_number,
    )


def _issue(number: int, *, body: str = "", state: str = "OPEN") -> dict:
    return {"number": number, "title": f"Issue {number}", "body": body, "state": state}


def _blocked_by(number: int) -> str:
    return f"## Blocked by\n\n#{number}\n"


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


class StackedDependentTests(unittest.TestCase):
    def test_depth_1_dependent_bases_on_root_branch(self) -> None:
        # 222 -> 221 (root). 221 has no blocker, so it is the root.
        client = FakeGitHubClient(
            issues={
                221: _issue(221),
                222: _issue(222, body=_blocked_by(221)),
            }
        )
        target = TargetResolver(client).resolve(_contract(222, body=_blocked_by(221)))
        self.assertEqual(target.branch, "ralph/issue-221")
        self.assertEqual(target.base, "ralph/issue-221")
        self.assertEqual(target.issue_number, 222)
        self.assertIsNone(target.prd_number)

    def test_depth_2_dependent_bases_on_chain_root_not_parent(self) -> None:
        # 223 -> 222 -> 221. Root is 221; never the discarded scratch 222.
        client = FakeGitHubClient(
            issues={
                221: _issue(221),
                222: _issue(222, body=_blocked_by(221)),
                223: _issue(223, body=_blocked_by(222)),
            }
        )
        target = TargetResolver(client).resolve(_contract(223, body=_blocked_by(222)))
        self.assertEqual(target.branch, "ralph/issue-221")
        self.assertEqual(target.base, "ralph/issue-221")
        self.assertNotEqual(target.branch, "ralph/issue-222")

    def test_root_issue_with_blocked_by_none_bases_on_main(self) -> None:
        body = "## Blocked by\n\nNone\n"
        client = FakeGitHubClient(issues={221: _issue(221, body=body)})
        target = TargetResolver(client).resolve(_contract(221, body=body))
        self.assertEqual(target.branch, "ralph/issue-221")
        self.assertEqual(target.base, "main")

    def test_standalone_issue_bases_on_main(self) -> None:
        client = FakeGitHubClient(issues={40: _issue(40)})
        target = TargetResolver(client).resolve(_contract(40))
        self.assertEqual(target.branch, "ralph/issue-40")
        self.assertEqual(target.base, "main")

    def test_blocker_merged_to_main_makes_dependent_its_own_root(self) -> None:
        # 222 -> 221, but 221 is CLOSED (merged to main). 222's own blocker is
        # therefore satisfied: 222 is the root and bases on main, no stacking.
        client = FakeGitHubClient(
            issues={
                221: _issue(221, state="CLOSED"),
                222: _issue(222, body=_blocked_by(221)),
            }
        )
        target = TargetResolver(client).resolve(_contract(222, body=_blocked_by(221)))
        self.assertEqual(target.branch, "ralph/issue-222")
        self.assertEqual(target.base, "main")

    def test_dependent_with_merged_grandparent_roots_at_open_ancestor(self) -> None:
        # 223 -> 222 -> 221(CLOSED). 222's blocker is merged, so 222 is the root.
        client = FakeGitHubClient(
            issues={
                221: _issue(221, state="CLOSED"),
                222: _issue(222, body=_blocked_by(221)),
                223: _issue(223, body=_blocked_by(222)),
            }
        )
        target = TargetResolver(client).resolve(_contract(223, body=_blocked_by(222)))
        self.assertEqual(target.branch, "ralph/issue-222")
        self.assertEqual(target.base, "ralph/issue-222")

    def test_prd_dependent_keeps_prd_branch_on_main(self) -> None:
        # PRD membership wins over Blocked-by stacking; PRD issues are unaffected.
        body = _blocked_by(221)
        client = FakeGitHubClient(
            issues={
                221: _issue(221),
                222: _issue(222, body=body),
            }
        )
        target = TargetResolver(client).resolve(_contract(222, prd_number=7, body=body))
        self.assertEqual(target.branch, "ralph/prd-7")
        self.assertEqual(target.base, "main")


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
