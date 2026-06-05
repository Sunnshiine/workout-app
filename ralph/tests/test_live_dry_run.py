from __future__ import annotations

import tempfile
import unittest
from pathlib import Path

from ralph.orchestrator.engine import FakeEngine
from ralph.orchestrator.github import FakeGitHubClient
from ralph.orchestrator.live_dry_run import (
    DRY_RUN_AUTHORIZATION_LINE,
    DRY_RUN_PHASE,
    DRY_RUN_TITLE_PREFIX,
    GitCommandResult,
    LiveDryRunError,
    dry_run_branch,
    evidence_path,
    run_live_github_dry_run,
)
from ralph.orchestrator.publish import (
    LABEL_AGENT_IMPLEMENTED,
    LABEL_AGENT_READY_FOR_REVIEW,
    LABEL_READY_FOR_AGENT,
)


class _RecordingGit:
    def __init__(self) -> None:
        self.calls: list[tuple[Path, list[str]]] = []

    def __call__(self, args, cwd: Path) -> GitCommandResult:
        self.calls.append((cwd, list(args)))
        if args[:2] == ["worktree", "add"]:
            Path(args[-2]).mkdir(parents=True, exist_ok=True)
        return GitCommandResult(returncode=0)


def _control_issue(number: int, *, title: str | None = None) -> dict:
    return {
        "number": number,
        "title": title or f"{DRY_RUN_TITLE_PREFIX} Python control",
        "body": f"{DRY_RUN_AUTHORIZATION_LINE}\n\nNo autonomous code edits.",
        "labels": [{"name": LABEL_READY_FOR_AGENT}],
    }


class LiveGitHubDryRunTests(unittest.TestCase):
    def test_rejects_uncontrolled_issue(self) -> None:
        client = FakeGitHubClient(
            issues={
                213: {
                    "number": 213,
                    "title": "Real implementation issue",
                    "body": DRY_RUN_AUTHORIZATION_LINE,
                    "labels": [],
                }
            }
        )

        with tempfile.TemporaryDirectory() as tmp, self.assertRaises(LiveDryRunError):
            run_live_github_dry_run(
                issue_number=213,
                repo_root=Path(tmp),
                client=client,
                engine=FakeEngine(),
                git=_RecordingGit(),
            )

    def test_rejects_real_engine(self) -> None:
        class RealishEngine(FakeEngine):
            name = "codex"

        client = FakeGitHubClient(issues={213: _control_issue(213)})
        with tempfile.TemporaryDirectory() as tmp, self.assertRaises(LiveDryRunError):
            run_live_github_dry_run(
                issue_number=213,
                repo_root=Path(tmp),
                client=client,
                engine=RealishEngine(),
                git=_RecordingGit(),
            )

    def test_creates_pr_marks_ready_comments_and_writes_evidence(self) -> None:
        client = FakeGitHubClient(issues={213: _control_issue(213)}, next_pr_number=1200)
        engine = FakeEngine()
        git = _RecordingGit()

        with tempfile.TemporaryDirectory() as tmp:
            repo_root = Path(tmp)
            result = run_live_github_dry_run(
                issue_number=213,
                repo_root=repo_root,
                client=client,
                engine=engine,
                git=git,
                timestamp="2026-06-05T00:00:00Z",
            )

            self.assertEqual(result.branch, "ralph/dry-run/issue-213")
            self.assertEqual(result.pr_number, 1200)
            self.assertFalse(result.reused_pr)
            self.assertTrue(result.marked_ready)
            self.assertEqual([call.phase for call in engine.calls], [DRY_RUN_PHASE])

            labels = client.issue_labels(213)
            self.assertIn(LABEL_AGENT_IMPLEMENTED, labels)
            self.assertNotIn(LABEL_READY_FOR_AGENT, labels)
            self.assertFalse(client.pr_is_draft(1200))
            self.assertIn(LABEL_AGENT_READY_FOR_REVIEW, client.pr_labels(1200))

            calls = [call[0] for call in client.calls]
            self.assertEqual(
                calls,
                [
                    "create_pr",
                    "remove_issue_labels",
                    "add_issue_labels",
                    "mark_pr_ready",
                    "add_pr_labels",
                    "comment_issue",
                ],
            )
            comment = client.view_issue(213)["comments"][0]["body"]
            self.assertIn("fake engine", comment)
            self.assertIn("Real agent invocation: none", comment)

            evidence = (repo_root / evidence_path(213)).read_text(encoding="utf-8")
            self.assertIn("Pull request: #1200", evidence)
            self.assertIn("Pushed file scope: docs evidence only", evidence)

        pushed_refs = [
            args[-1] for _cwd, args in git.calls if args[:2] == ["push", "--force-with-lease"]
        ]
        self.assertEqual(
            pushed_refs,
            ["HEAD:ralph/dry-run/issue-213", "HEAD:ralph/dry-run/issue-213"],
        )
        self.assertTrue(any(args[:2] == ["worktree", "remove"] for _cwd, args in git.calls))

    def test_reuses_existing_ready_pr_without_marking_ready_again(self) -> None:
        branch = dry_run_branch(214)
        client = FakeGitHubClient(
            issues={214: _control_issue(214)},
            open_prs=[
                {
                    "number": 1300,
                    "headRefName": branch,
                    "baseRefName": "main",
                    "isDraft": False,
                    "labels": [],
                }
            ],
        )

        with tempfile.TemporaryDirectory() as tmp:
            result = run_live_github_dry_run(
                issue_number=214,
                repo_root=Path(tmp),
                client=client,
                engine=FakeEngine(),
                git=_RecordingGit(),
            )

        self.assertEqual(result.pr_number, 1300)
        self.assertTrue(result.reused_pr)
        self.assertFalse(result.marked_ready)
        calls = [call[0] for call in client.calls]
        self.assertNotIn("create_pr", calls)
        self.assertNotIn("mark_pr_ready", calls)


if __name__ == "__main__":
    unittest.main()
