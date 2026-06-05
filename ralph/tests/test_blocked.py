from __future__ import annotations

import unittest

from ralph.orchestrator.blocked import (
    MAX_EXCERPT_BYTES,
    MAX_EXCERPT_LINES,
    REDACTION_PLACEHOLDER,
    BlockedReport,
    BlockedReportWriter,
    BlockedRescuePublisher,
    blocked_branch,
    blocked_commit_message,
    blocked_pr_title,
    cap_excerpt,
    redact_secrets,
)
from ralph.orchestrator.contracts import capture_issue_contract
from ralph.orchestrator.github import FakeGitHubClient
from ralph.orchestrator.publish import (
    LABEL_AGENT_BLOCKED,
    LABEL_AGENT_IMPLEMENTED,
    LABEL_READY_FOR_AGENT,
    LABEL_READY_FOR_HUMAN,
    GitOutcome,
    PublishError,
)

# A representative slice of Secrets.xcconfig content that must never reach GitHub.
SECRETS_XCCONFIG = (
    "GOOGLE_CLIENT_ID = 123-abc.apps.googleusercontent.com\n"
    "GOOGLE_API_KEY = AIzaSyTOPSECRETVALUE\n"
    "OPENAI_API_KEY = sk-livesecretkey0000\n"
    "GH_TOKEN = ghp_realtokenvalue1234\n"
)


class _RecordingGit:
    """Injectable publish git runner that records argv and always succeeds."""

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


def _report(issue: int = 5, *, prd_number: int | None = None, **overrides) -> BlockedReport:
    base = {
        "issue": issue,
        "title": "Add foo",
        "prd_number": prd_number,
        "intended_branch": f"ralph/issue-{issue}",
        "failed_phase_or_gate": "swift-test",
        "failing_command": "swift test",
        "exit_status": 1,
        "repair_attempted": False,
        "repair_result": None,
    }
    base.update(overrides)
    return BlockedReport(**base)


class RedactionTests(unittest.TestCase):
    def test_redacts_token_secret_key_and_password_values(self) -> None:
        text = (
            "GH_TOKEN=ghp_realtoken\n"
            "MY_SECRET = hunter2\n"
            "SIGNING_KEY: keymaterial\n"
            "PASSWORD = letmein\n"
        )
        out = redact_secrets(text)
        for leaked in ("ghp_realtoken", "hunter2", "keymaterial", "letmein"):
            self.assertNotIn(leaked, out)
        self.assertEqual(out.count(REDACTION_PLACEHOLDER), 4)
        # Key names survive for context; only values are scrubbed.
        self.assertIn("GH_TOKEN", out)
        self.assertIn("PASSWORD", out)

    def test_redacts_named_api_keys_and_google_prefix(self) -> None:
        text = (
            "OPENAI_API_KEY=sk-live000\n"
            "CODEX_API_KEY=cx-live111\n"
            "GITHUB_TOKEN=gh-222\n"
            "GOOGLE_CLIENT_ID=client-333\n"
            "GOOGLE_REFRESH_TOKEN=refresh-444\n"
        )
        out = redact_secrets(text)
        for leaked in ("sk-live000", "cx-live111", "gh-222", "client-333", "refresh-444"):
            self.assertNotIn(leaked, out)

    def test_leaves_non_secret_lines_untouched(self) -> None:
        text = "Build succeeded\nTOTAL_TESTS = 42\nplain prose line\n"
        out = redact_secrets(text)
        # TOTAL_TESTS is not a secret pattern; value preserved.
        self.assertIn("TOTAL_TESTS = 42", out)
        self.assertIn("Build succeeded", out)
        self.assertIn("plain prose line", out)
        self.assertNotIn(REDACTION_PLACEHOLDER, out)

    def test_secrets_xcconfig_values_never_survive(self) -> None:
        out = redact_secrets(SECRETS_XCCONFIG)
        for leaked in (
            "AIzaSyTOPSECRETVALUE",
            "sk-livesecretkey0000",
            "ghp_realtokenvalue1234",
            "123-abc.apps.googleusercontent.com",
        ):
            self.assertNotIn(leaked, out)


class CapExcerptTests(unittest.TestCase):
    def test_caps_by_line_count(self) -> None:
        text = "\n".join(str(i) for i in range(MAX_EXCERPT_LINES + 20))
        out = cap_excerpt(text)
        self.assertLessEqual(len(out.split("\n")), MAX_EXCERPT_LINES + 1)
        self.assertIn("truncated", out)

    def test_caps_by_byte_count(self) -> None:
        text = "x" * (MAX_EXCERPT_BYTES + 500)
        out = cap_excerpt(text)
        self.assertLessEqual(len(out.encode("utf-8")), MAX_EXCERPT_BYTES + 100)
        self.assertIn("truncated", out)

    def test_short_text_unchanged(self) -> None:
        text = "line one\nline two"
        self.assertEqual(cap_excerpt(text), text)


class BlockedReportWriterTests(unittest.TestCase):
    def test_body_uses_refs_and_no_closing_keyword(self) -> None:
        body = BlockedReportWriter().render(_report(7))
        self.assertIn("Refs #7", body)
        for keyword in ("Closes #7", "Fixes #7", "Resolves #7"):
            self.assertNotIn(keyword, body)

    def test_body_includes_structured_context(self) -> None:
        report = _report(
            7,
            prd_number=3,
            repair_attempted=True,
            repair_result="second UI failure",
            changed_files=("WorkoutTracker/Foo.swift", "Tests/Unit/FooTests.swift"),
            diffstat=" 2 files changed, 10 insertions(+)",
            local_artifact_paths=("ralph/.artifacts/issue-7/gate.log",),
            recommended_next_action="Inspect the failing swift test locally.",
        )
        body = BlockedReportWriter().render(report)
        self.assertIn("#7", body)
        self.assertIn("PRD: #3", body)
        self.assertIn("swift-test", body)
        self.assertIn("Repair attempted: yes", body)
        self.assertIn("second UI failure", body)
        self.assertIn("WorkoutTracker/Foo.swift", body)
        self.assertIn("2 files changed", body)
        self.assertIn("ralph/.artifacts/issue-7/gate.log", body)
        self.assertIn("Inspect the failing swift test", body)

    def test_excerpt_is_redacted_and_secrets_never_published(self) -> None:
        report = _report(7, sanitized_excerpt=SECRETS_XCCONFIG)
        body = BlockedReportWriter().render(report)
        for leaked in (
            "AIzaSyTOPSECRETVALUE",
            "sk-livesecretkey0000",
            "ghp_realtokenvalue1234",
        ):
            self.assertNotIn(leaked, body)
        self.assertIn(REDACTION_PLACEHOLDER, body)

    def test_excerpt_is_capped(self) -> None:
        excerpt = "\n".join(f"log line {i}" for i in range(MAX_EXCERPT_LINES + 50))
        report = _report(7, sanitized_excerpt=excerpt)
        body = BlockedReportWriter().render(report)
        self.assertIn("truncated", body)
        # The deepest log lines never make it into the published body.
        self.assertNotIn(f"log line {MAX_EXCERPT_LINES + 49}", body)


class BlockedTitleAndBranchTests(unittest.TestCase):
    def test_branch_name(self) -> None:
        self.assertEqual(blocked_branch(42), "ralph/issue-42-blocked")

    def test_title_shape(self) -> None:
        client = FakeGitHubClient(issues={42: _issue(42, title="Add bar")})
        contract = _contract(client, 42)
        self.assertEqual(blocked_pr_title(contract), "Blocked: #42 Add bar")

    def test_commit_message_refs_not_closes(self) -> None:
        message = blocked_commit_message(42)
        self.assertIn("Refs #42", message)
        self.assertNotIn("Closes #42", message)


class BlockedRescuePublisherTests(unittest.TestCase):
    def test_pushes_blocked_branch_and_creates_draft_pr(self) -> None:
        client = FakeGitHubClient(issues={5: _issue(5, title="Add foo")})
        contract = _contract(client, 5)
        git = _RecordingGit()

        pr_number = BlockedRescuePublisher(client, git).publish(contract, _report(5))

        pr = client.find_pr_by_head_branch("ralph/issue-5-blocked")
        self.assertIsNotNone(pr)
        self.assertEqual(pr["number"], pr_number)
        self.assertTrue(client.pr_is_draft(pr_number))
        self.assertEqual(pr["title"], "Blocked: #5 Add foo")
        self.assertEqual(pr["baseRefName"], "main")
        self.assertIn(LABEL_AGENT_BLOCKED, client.pr_labels(pr_number))
        # Commit then push went through the git seam against the blocked branch.
        self.assertEqual(git.calls[0][0], "commit")
        self.assertEqual(git.calls[1][0], "push")
        self.assertIn("ralph/issue-5-blocked", git.calls[1])
        self.assertIn("--force-with-lease", git.calls[1])

    def test_pr_body_refs_issue_and_has_no_closing_keyword(self) -> None:
        client = FakeGitHubClient(issues={5: _issue(5, title="Add foo")})
        contract = _contract(client, 5)
        pr_number = BlockedRescuePublisher(client, _RecordingGit()).publish(contract, _report(5))

        body = client.find_pr_by_head_branch("ralph/issue-5-blocked")["body"]
        self.assertIn("Refs #5", body)
        for keyword in ("Closes #5", "Fixes #5", "Resolves #5"):
            self.assertNotIn(keyword, body)
        _ = pr_number

    def test_blocked_label_transition(self) -> None:
        client = FakeGitHubClient(
            issues={5: _issue(5, title="Add foo", labels=[LABEL_READY_FOR_AGENT])}
        )
        contract = _contract(client, 5)
        BlockedRescuePublisher(client, _RecordingGit()).publish(contract, _report(5))

        labels = client.issue_labels(5)
        self.assertNotIn(LABEL_READY_FOR_AGENT, labels)
        self.assertIn(LABEL_READY_FOR_HUMAN, labels)
        self.assertIn(LABEL_AGENT_BLOCKED, labels)
        self.assertNotIn(LABEL_AGENT_IMPLEMENTED, labels)
        # Issue is never closed by Ralph.
        self.assertEqual(client.view_issue(5).get("state", "OPEN"), "OPEN")

    def test_posts_sanitized_report_comment(self) -> None:
        client = FakeGitHubClient(issues={5: _issue(5, title="Add foo")})
        contract = _contract(client, 5)
        report = _report(5, sanitized_excerpt=SECRETS_XCCONFIG)
        BlockedRescuePublisher(client, _RecordingGit()).publish(contract, report)

        comment_calls = [c for c in client.calls if c[0] == "comment_issue"]
        self.assertEqual(len(comment_calls), 1)
        comment_body = comment_calls[0][2]
        self.assertIn("Refs #5", comment_body)
        self.assertNotIn("ghp_realtokenvalue1234", comment_body)

    def test_prd_targets_stack_branch_when_pr_exists(self) -> None:
        client = FakeGitHubClient(
            issues={6: _issue(6, title="Child", body="PRD: #1")},
            open_prs=[{"number": 900, "headRefName": "ralph/prd-1", "state": "OPEN"}],
        )
        contract = _contract(client, 6)
        pr_number = BlockedRescuePublisher(client, _RecordingGit()).publish(contract, _report(6))

        pr = client.find_pr_by_head_branch("ralph/issue-6-blocked")
        self.assertEqual(pr["baseRefName"], "ralph/prd-1")
        _ = pr_number

    def test_prd_targets_main_when_stack_branch_absent(self) -> None:
        client = FakeGitHubClient(issues={6: _issue(6, title="Child", body="PRD: #1")})
        contract = _contract(client, 6)
        BlockedRescuePublisher(client, _RecordingGit()).publish(contract, _report(6))

        pr = client.find_pr_by_head_branch("ralph/issue-6-blocked")
        self.assertEqual(pr["baseRefName"], "main")

    def test_reuses_existing_blocked_pr(self) -> None:
        client = FakeGitHubClient(issues={5: _issue(5, title="Add foo")})
        contract = _contract(client, 5)
        publisher = BlockedRescuePublisher(client, _RecordingGit())

        first = publisher.publish(contract, _report(5))
        second = publisher.publish(contract, _report(5))

        self.assertEqual(first, second)
        self.assertEqual(len(client.list_open_prs(head="ralph/issue-5-blocked")), 1)
        create_calls = [c for c in client.calls if c[0] == "create_pr"]
        self.assertEqual(len(create_calls), 1)

    def test_push_failure_raises_publish_error(self) -> None:
        client = FakeGitHubClient(issues={5: _issue(5, title="Add foo")})
        contract = _contract(client, 5)
        publisher = BlockedRescuePublisher(client, _FailingGit())

        with self.assertRaises(PublishError):
            publisher.publish(contract, _report(5))


if __name__ == "__main__":
    unittest.main()
