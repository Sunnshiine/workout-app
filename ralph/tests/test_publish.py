from __future__ import annotations

import unittest

from ralph.orchestrator.contracts import capture_issue_contract
from ralph.orchestrator.github import FakeGitHubClient
from ralph.orchestrator.publish import (
    LABEL_AGENT_IMPLEMENTED,
    LABEL_AGENT_READY_FOR_REVIEW,
    LABEL_READY_FOR_AGENT,
    GitOutcome,
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
        client = FakeGitHubClient(issues={9: _issue(9, labels=[LABEL_READY_FOR_AGENT])})
        IssuePublisher(client).mark_implemented(9)

        labels = client.issue_labels(9)
        self.assertIn(LABEL_AGENT_IMPLEMENTED, labels)
        self.assertNotIn(LABEL_READY_FOR_AGENT, labels)
        # Never adds ready-for-human, never closes (state untouched here).
        self.assertNotIn("ready-for-human", labels)
        self.assertEqual(client.view_issue(9).get("state", "OPEN"), "OPEN")
        kinds = [call[0] for call in client.calls]
        self.assertEqual(kinds, ["remove_issue_labels", "add_issue_labels"])


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


if __name__ == "__main__":
    unittest.main()
