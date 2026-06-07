from __future__ import annotations

import unittest

from ralph.orchestrator.contracts import capture_issue_contract
from ralph.orchestrator.github import FakeGitHubClient
from ralph.orchestrator.publish import (
    LABEL_AGENT_ACTIVE,
    LABEL_AGENT_IMPLEMENTED,
    LABEL_AGENT_READY_FOR_REVIEW,
    LABEL_READY_FOR_AGENT,
    ClaimError,
    GitOutcome,
    IssueClaimer,
    IssuePublisher,
    PublishError,
    PullRequestPublisher,
    integration_commit_message,
)
from ralph.orchestrator.targets import TargetResolver


class _RecordingGit:
    """Injectable git runner that records argv and always succeeds."""

    def __init__(self) -> None:
        self.calls: list[list[str]] = []

    def __call__(self, args) -> GitOutcome:
        self.calls.append(list(args))
        return GitOutcome(returncode=0)


class _FailingGit:
    def __call__(self, args) -> GitOutcome:
        return GitOutcome(returncode=1, stderr="boom")


def _issue(
    number: int, *, body: str = "", labels: list[str] | None = None, title: str = "T"
) -> dict:
    label_objs = [{"name": name} for name in (labels or [])]
    return {"number": number, "title": title, "body": body, "labels": label_objs}


def _contract(client: FakeGitHubClient, number: int):
    return capture_issue_contract(client, number)


class IntegrationCommitMessageTests(unittest.TestCase):
    def test_message_includes_closing_keyword(self) -> None:
        message = integration_commit_message(42, "claude")
        self.assertIn("Closes #42", message)
        self.assertIn("implement issue #42", message)
        self.assertIn("(claude)", message)


class IssuePublisherTests(unittest.TestCase):
    def test_marks_implemented_and_leaves_issue_open(self) -> None:
        client = FakeGitHubClient(issues={9: _issue(9, labels=[LABEL_AGENT_ACTIVE])})
        IssuePublisher(client).mark_implemented(9)

        labels = client.issue_labels(9)
        self.assertIn(LABEL_AGENT_IMPLEMENTED, labels)
        self.assertNotIn(LABEL_READY_FOR_AGENT, labels)
        self.assertNotIn(LABEL_AGENT_ACTIVE, labels)
        # Never adds ready-for-human, never closes (state untouched here).
        self.assertNotIn("ready-for-human", labels)
        self.assertEqual(client.view_issue(9).get("state", "OPEN"), "OPEN")
        kinds = [call[0] for call in client.calls]
        self.assertEqual(kinds, ["remove_issue_labels", "add_issue_labels"])


class IssueClaimerTests(unittest.TestCase):
    def test_claim_moves_ready_issue_to_agent_active(self) -> None:
        client = FakeGitHubClient(
            issues={9: _issue(9, body="Do it", labels=[LABEL_READY_FOR_AGENT])}
        )

        contract = IssueClaimer(client).claim(9)

        labels = client.issue_labels(9)
        self.assertEqual(contract.number, 9)
        self.assertIn(LABEL_AGENT_ACTIVE, labels)
        self.assertNotIn(LABEL_READY_FOR_AGENT, labels)
        self.assertNotIn(LABEL_AGENT_IMPLEMENTED, labels)
        self.assertEqual(
            client.calls[0],
            ("edit_issue_labels", 9, (LABEL_AGENT_ACTIVE,), (LABEL_READY_FOR_AGENT,)),
        )

    def test_claim_rejects_conflicting_lifecycle_labels(self) -> None:
        client = FakeGitHubClient(
            issues={
                9: _issue(
                    9,
                    labels=[LABEL_READY_FOR_AGENT, LABEL_AGENT_IMPLEMENTED],
                )
            }
        )

        with self.assertRaises(ClaimError):
            IssueClaimer(client).claim(9)


class OneOffPullRequestTests(unittest.TestCase):
    def test_first_push_creates_draft_pr(self) -> None:
        client = FakeGitHubClient(issues={5: _issue(5, title="Add foo")})
        contract = _contract(client, 5)
        target = TargetResolver(client).resolve(contract)
        git = _RecordingGit()

        pr_number = PullRequestPublisher(client, git).publish(contract, target, engine="codex")

        self.assertTrue(client.pr_is_draft(pr_number))
        pr = client.find_pr_by_head_branch("ralph/issue-5")
        self.assertEqual(pr["number"], pr_number)
        self.assertEqual(pr["baseRefName"], "main")
        # Commit then push went through the git seam.
        self.assertEqual(git.calls[0][0], "commit")
        self.assertEqual(git.calls[1][0], "push")
        self.assertIn("ralph/issue-5", git.calls[1])

    def test_one_off_becomes_ready_after_issue_passes(self) -> None:
        client = FakeGitHubClient(issues={5: _issue(5, title="Add foo")})
        contract = _contract(client, 5)
        target = TargetResolver(client).resolve(contract)
        publisher = PullRequestPublisher(client, _RecordingGit())

        pr_number = publisher.publish(contract, target, engine="codex")
        self.assertTrue(client.pr_is_draft(pr_number))

        became_ready = publisher.update_readiness(contract, pr_number)
        self.assertTrue(became_ready)
        self.assertFalse(client.pr_is_draft(pr_number))
        self.assertIn(LABEL_AGENT_READY_FOR_REVIEW, client.pr_labels(pr_number))

    def test_second_push_reuses_existing_pr(self) -> None:
        client = FakeGitHubClient(issues={5: _issue(5, title="Add foo")})
        contract = _contract(client, 5)
        publisher = PullRequestPublisher(client, _RecordingGit())

        first = publisher.publish(contract, TargetResolver(client).resolve(contract), engine="x")
        # Re-resolve so the target now reflects the existing PR.
        second = publisher.publish(contract, TargetResolver(client).resolve(contract), engine="x")

        self.assertEqual(first, second)
        self.assertEqual(len(client.list_open_prs(head="ralph/issue-5")), 1)
        create_calls = [c for c in client.calls if c[0] == "create_pr"]
        self.assertEqual(len(create_calls), 1)

    def test_push_failure_raises_publish_error(self) -> None:
        client = FakeGitHubClient(issues={5: _issue(5)})
        contract = _contract(client, 5)
        target = TargetResolver(client).resolve(contract)
        publisher = PullRequestPublisher(client, _FailingGit())

        with self.assertRaises(PublishError):
            publisher.publish(contract, target, engine="x")


class PrdPullRequestTests(unittest.TestCase):
    def _prd_setup(self, child_labels: dict[int, list[str]]) -> FakeGitHubClient:
        issues = {1: _issue(1, title="PRD parent")}
        for number, labels in child_labels.items():
            issues[number] = _issue(number, body="PRD: #1", labels=labels)
        return FakeGitHubClient(issues=issues)

    def test_prd_pr_stays_draft_with_incomplete_children(self) -> None:
        # Child 2 implemented, child 3 still ready-for-agent.
        client = self._prd_setup({2: [LABEL_AGENT_IMPLEMENTED], 3: [LABEL_READY_FOR_AGENT]})
        contract = _contract(client, 2)
        target = TargetResolver(client).resolve(contract)
        self.assertEqual(target.branch, "ralph/prd-1")
        publisher = PullRequestPublisher(client, _RecordingGit())

        pr_number = publisher.publish(contract, target, engine="x")
        became_ready = publisher.update_readiness(contract, pr_number)

        self.assertFalse(became_ready)
        self.assertTrue(client.pr_is_draft(pr_number))
        self.assertNotIn(LABEL_AGENT_READY_FOR_REVIEW, client.pr_labels(pr_number))

    def test_prd_pr_ready_when_all_children_implemented(self) -> None:
        client = self._prd_setup({2: [LABEL_AGENT_IMPLEMENTED], 3: [LABEL_AGENT_IMPLEMENTED]})
        contract = _contract(client, 3)
        target = TargetResolver(client).resolve(contract)
        publisher = PullRequestPublisher(client, _RecordingGit())

        pr_number = publisher.publish(contract, target, engine="x")
        became_ready = publisher.update_readiness(contract, pr_number)

        self.assertTrue(became_ready)
        self.assertFalse(client.pr_is_draft(pr_number))
        self.assertIn(LABEL_AGENT_READY_FOR_REVIEW, client.pr_labels(pr_number))

    def test_prd_pr_stays_draft_when_a_child_is_blocked(self) -> None:
        client = self._prd_setup(
            {2: [LABEL_AGENT_IMPLEMENTED], 3: [LABEL_AGENT_IMPLEMENTED, "agent-blocked"]}
        )
        contract = _contract(client, 2)
        target = TargetResolver(client).resolve(contract)
        publisher = PullRequestPublisher(client, _RecordingGit())

        pr_number = publisher.publish(contract, target, engine="x")
        self.assertFalse(publisher.update_readiness(contract, pr_number))
        self.assertTrue(client.pr_is_draft(pr_number))

    def test_prd_branch_reused_across_two_children(self) -> None:
        client = self._prd_setup({2: [LABEL_AGENT_IMPLEMENTED], 3: [LABEL_READY_FOR_AGENT]})
        publisher = PullRequestPublisher(client, _RecordingGit())

        c2 = _contract(client, 2)
        pr_a = publisher.publish(c2, TargetResolver(client).resolve(c2), engine="x")
        c3 = _contract(client, 3)
        pr_b = publisher.publish(c3, TargetResolver(client).resolve(c3), engine="x")

        self.assertEqual(pr_a, pr_b)
        self.assertEqual(len(client.list_open_prs(head="ralph/prd-1")), 1)


class StackedDependentPublishTests(unittest.TestCase):
    """A ``## Blocked by`` dependent squashes onto the chain root PR (ADR-0008)."""

    def _chain_client(self) -> FakeGitHubClient:
        # 221 is the root; 222 is blocked by 221; 223 is blocked by 222 (depth-2).
        return FakeGitHubClient(
            issues={
                221: _issue(221, title="root", labels=[LABEL_AGENT_IMPLEMENTED]),
                222: _issue(222, title="dep", body="## Blocked by\n- #221\n"),
                223: _issue(223, title="dep2", body="## Blocked by\n- #222\n"),
            }
        )

    def _publish_root(self, client: FakeGitHubClient, git) -> int:
        root = _contract(client, 221)
        return PullRequestPublisher(client, git).publish(
            root, TargetResolver(client).resolve(root), engine="x"
        )

    def test_dependent_squashes_onto_root_without_new_pr(self) -> None:
        client = self._chain_client()
        git = _RecordingGit()
        root_pr = self._publish_root(client, git)

        dep = _contract(client, 222)
        target = TargetResolver(client).resolve(dep)
        self.assertEqual(target.branch, "ralph/issue-221")
        self.assertTrue(target.is_stacked_dependent)

        dep_pr = PullRequestPublisher(client, git).publish(dep, target, engine="x")

        # Reuses the root PR; no second PR is created for the dependent.
        self.assertEqual(dep_pr, root_pr)
        self.assertEqual(len(client.list_open_prs(head="ralph/issue-221")), 1)
        create_calls = [c for c in client.calls if c[0] == "create_pr"]
        self.assertEqual(len(create_calls), 1)
        # The dependent's single commit was pushed onto the root branch.
        push_calls = [c for c in git.calls if c[0] == "push"]
        self.assertTrue(all("ralph/issue-221" in c for c in push_calls))

    def test_root_pr_accumulates_closes_lines(self) -> None:
        client = self._chain_client()
        git = _RecordingGit()
        root_pr = self._publish_root(client, git)
        body = client.find_pr_by_head_branch("ralph/issue-221")["body"]
        self.assertIn("Closes #221", body)
        self.assertNotIn("Closes #222", body)

        dep = _contract(client, 222)
        PullRequestPublisher(client, git).publish(
            dep, TargetResolver(client).resolve(dep), engine="x"
        )

        body = client.find_pr_by_head_branch("ralph/issue-221")["body"]
        self.assertIn("Closes #221", body)
        self.assertIn("Closes #222", body)
        self.assertEqual(client._pr(root_pr)["number"], root_pr)

    def test_no_duplicate_closes_line(self) -> None:
        client = self._chain_client()
        git = _RecordingGit()
        self._publish_root(client, git)

        dep = _contract(client, 222)
        publisher = PullRequestPublisher(client, git)
        publisher.publish(dep, TargetResolver(client).resolve(dep), engine="x")
        # Re-publishing the same dependent (e.g. a retried push) must not append twice.
        publisher.publish(dep, TargetResolver(client).resolve(dep), engine="x")

        body = client.find_pr_by_head_branch("ralph/issue-221")["body"]
        self.assertEqual(body.count("Closes #222"), 1)

    def test_depth_two_dependent_squashes_onto_transitive_root(self) -> None:
        # 223 is blocked by 222 which is blocked by 221: its root is 221, not 222.
        client = self._chain_client()
        git = _RecordingGit()
        self._publish_root(client, git)

        dep2 = _contract(client, 223)
        target = TargetResolver(client).resolve(dep2)
        self.assertEqual(target.branch, "ralph/issue-221")
        self.assertTrue(target.is_stacked_dependent)

        PullRequestPublisher(client, git).publish(dep2, target, engine="x")

        body = client.find_pr_by_head_branch("ralph/issue-221")["body"]
        self.assertIn("Closes #223", body)
        self.assertEqual(len(client.list_open_prs(head="ralph/issue-221")), 1)
        self.assertEqual(len(client.list_open_prs(head="ralph/issue-223")), 0)


if __name__ == "__main__":
    unittest.main()
