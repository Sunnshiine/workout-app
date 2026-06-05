from __future__ import annotations

import contextlib
import io
import subprocess
import tempfile
import unittest
from datetime import datetime, timedelta, timezone
from pathlib import Path

from ralph.orchestrator.config import RunConfig
from ralph.orchestrator.engine import FakeEngine
from ralph.orchestrator.gates import CommandResult, GateRunner
from ralph.orchestrator.github import FakeGitHubClient
from ralph.orchestrator.loop import (
    IssueSelector,
    OriginMain,
    RalphLoop,
    RalphLoopError,
    _format_ralph_log_line,
)
from ralph.orchestrator.publish import (
    LABEL_AGENT_ACTIVE,
    LABEL_AGENT_IMPLEMENTED,
    LABEL_READY_FOR_AGENT,
    LABEL_READY_FOR_HUMAN,
    GitOutcome,
)
from ralph.orchestrator.worktree import WorktreeManager, default_git_runner


def _git(repo: Path, *args: str) -> None:
    subprocess.run(
        ["git", "-C", str(repo), *args],
        check=True,
        capture_output=True,
        text=True,
    )


def _init_repo(repo: Path) -> None:
    _git(repo, "init", "-b", "main")
    _git(repo, "config", "user.email", "ralph@example.com")
    _git(repo, "config", "user.name", "Ralph")
    (repo / "README.md").write_text("seed\n", encoding="utf-8")
    prompts = repo / "ralph" / "prompts"
    prompts.mkdir(parents=True)
    for name in ("implement.md", "swift-review.md", "ui-verify.md"):
        (prompts / name).write_text(f"{name}\n", encoding="utf-8")
    _git(repo, "add", "README.md", "ralph/prompts")
    _git(repo, "commit", "-m", "seed")


def _issue(number: int, *, title: str = "T", body: str = "Do it", labels=None) -> dict:
    return {
        "number": number,
        "title": title,
        "body": body,
        "labels": [{"name": label} for label in (labels or [LABEL_READY_FOR_AGENT])],
        "comments": [],
    }


class _OriginMain(OriginMain):
    def __init__(self) -> None:
        self.polls = 0

    def poll(self) -> None:
        self.polls += 1

    def base_ref_for(self, _target) -> str:
        self.poll()
        return "main"


class _RecordingPublishRunner:
    def __init__(self) -> None:
        self.calls: list[list[str]] = []

    def factory(self, _workdir: Path):
        def run(args) -> GitOutcome:
            self.calls.append(list(args))
            return GitOutcome(returncode=0)

        return run


class _StaleReadyListClient(FakeGitHubClient):
    def __init__(self, *, stale_numbers: tuple[int, ...], issues: dict[int, dict]) -> None:
        super().__init__(issues=issues)
        self._stale_numbers = stale_numbers

    def list_open_issues(self, *, label: str | None = None) -> list[dict]:
        if label != LABEL_READY_FOR_AGENT:
            return super().list_open_issues(label=label)
        return [
            {
                "number": number,
                "title": self.view_issue(number).get("title", ""),
                "labels": [{"name": LABEL_READY_FOR_AGENT}],
            }
            for number in self._stale_numbers
        ]


class _NonConvergingClaimClient(FakeGitHubClient):
    def edit_issue_labels(self, number: int, *, add=(), remove=()) -> None:
        self.calls.append(("edit_issue_labels", number, tuple(add), tuple(remove)))


class IssueSelectorTests(unittest.TestCase):
    def test_selects_bug_before_lower_non_bug_and_skips_unready(self) -> None:
        client = FakeGitHubClient(
            issues={
                1: _issue(1, title="Small cleanup"),
                2: _issue(2, title="PRD: Umbrella"),
                3: _issue(
                    3,
                    title="Needs human",
                    labels=[LABEL_READY_FOR_AGENT, LABEL_READY_FOR_HUMAN],
                ),
                4: _issue(4, title="Bug fix", labels=[LABEL_READY_FOR_AGENT, "bug"]),
                5: _issue(5, title="No body", body=""),
                6: _issue(6, title="Claimed", labels=[LABEL_READY_FOR_AGENT, LABEL_AGENT_ACTIVE]),
                7: _issue(
                    7,
                    title="Implemented",
                    labels=[LABEL_READY_FOR_AGENT, LABEL_AGENT_IMPLEMENTED],
                ),
                8: _issue(8, title="Closed", labels=[LABEL_READY_FOR_AGENT]) | {"state": "CLOSED"},
            }
        )

        selected = IssueSelector(client).select_next()

        self.assertIsNotNone(selected)
        self.assertEqual(selected.number, 4)


class RalphLogTests(unittest.TestCase):
    def test_formats_local_timestamp_before_ralph_message(self) -> None:
        now = datetime(2026, 6, 5, 14, 31, 8, tzinfo=timezone(timedelta(hours=-4)))

        line = _format_ralph_log_line("issue #190 ui-verify started", now=now)

        self.assertEqual(
            line,
            "2026-06-05T14:31:08-04:00 | Ralph: issue #190 ui-verify started",
        )


class RalphLoopTests(unittest.TestCase):
    def setUp(self) -> None:
        self.tmp = tempfile.TemporaryDirectory()
        self.repo = Path(self.tmp.name) / "repo"
        self.repo.mkdir()
        _init_repo(self.repo)

    def tearDown(self) -> None:
        self.tmp.cleanup()

    def test_successful_iteration_polls_origin_main_and_publishes_pr(self) -> None:
        client = FakeGitHubClient(issues={7: _issue(7, title="Add thing")})
        origin = _OriginMain()
        publish = _RecordingPublishRunner()
        loop = RalphLoop(
            config=RunConfig(engine="fake", max_iterations=1),
            repo_root=self.repo,
            client=client,
            engine=FakeEngine(),
            origin_main=origin,
            worktrees=WorktreeManager(self.repo, runner=default_git_runner),
            gate_runner_factory=lambda _w, _i, _n: GateRunner(
                lambda _c: CommandResult(exit_status=0)
            ),
            publish_runner_factory=publish.factory,
        )

        summary = loop.run()

        self.assertEqual(summary.issues_selected, (7,))
        self.assertEqual(summary.issues_completed, (7,))
        self.assertGreaterEqual(origin.polls, 1)
        self.assertIn(LABEL_AGENT_IMPLEMENTED, client.issue_labels(7))
        self.assertNotIn(LABEL_READY_FOR_AGENT, client.issue_labels(7))
        self.assertNotIn(LABEL_AGENT_ACTIVE, client.issue_labels(7))
        pr = client.find_pr_by_head_branch("ralph/issue-7")
        self.assertIsNotNone(pr)
        self.assertFalse(client.pr_is_draft(pr["number"]))
        self.assertEqual([call[0] for call in publish.calls], ["commit", "push"])

    def test_stale_ready_list_cannot_select_completed_issue_twice(self) -> None:
        client = _StaleReadyListClient(
            stale_numbers=(7, 8),
            issues={7: _issue(7, title="First"), 8: _issue(8, title="Second")},
        )
        publish = _RecordingPublishRunner()
        loop = RalphLoop(
            config=RunConfig(engine="fake", max_iterations=2),
            repo_root=self.repo,
            client=client,
            engine=FakeEngine(),
            origin_main=_OriginMain(),
            worktrees=WorktreeManager(self.repo, runner=default_git_runner),
            gate_runner_factory=lambda _w, _i, _n: GateRunner(
                lambda _c: CommandResult(exit_status=0)
            ),
            publish_runner_factory=publish.factory,
        )

        summary = loop.run()

        self.assertEqual(summary.issues_selected, (7, 8))
        self.assertEqual(summary.issues_completed, (7, 8))
        self.assertIn(LABEL_AGENT_IMPLEMENTED, client.issue_labels(7))
        self.assertIn(LABEL_AGENT_IMPLEMENTED, client.issue_labels(8))

    def test_claim_must_converge_before_worktree_creation(self) -> None:
        client = _NonConvergingClaimClient(issues={7: _issue(7, title="Add thing")})
        publish = _RecordingPublishRunner()
        loop = RalphLoop(
            config=RunConfig(engine="fake", max_iterations=1),
            repo_root=self.repo,
            client=client,
            engine=FakeEngine(),
            origin_main=_OriginMain(),
            worktrees=WorktreeManager(self.repo, runner=default_git_runner),
            gate_runner_factory=lambda _w, _i, _n: GateRunner(
                lambda _c: CommandResult(exit_status=0)
            ),
            publish_runner_factory=publish.factory,
        )

        with self.assertRaises(RalphLoopError):
            loop.run()

        self.assertFalse((self.repo / ".claude" / "worktrees" / "issue-7").exists())
        self.assertEqual(publish.calls, [])

    def test_select_only_stops_before_worktree_creation(self) -> None:
        out = io.StringIO()
        client = FakeGitHubClient(issues={8: _issue(8)})
        loop = RalphLoop(
            config=RunConfig(engine="fake", max_iterations=3, select_only=True),
            repo_root=self.repo,
            client=client,
            engine=FakeEngine(),
            origin_main=_OriginMain(),
        )

        with contextlib.redirect_stdout(out):
            summary = loop.run()

        self.assertEqual(summary.issues_selected, (8,))
        self.assertEqual(summary.issues_completed, ())
        self.assertEqual(summary.stopped_reason, "select-only")
        lines = out.getvalue().splitlines()
        self.assertRegex(
            lines[0],
            r"^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}[+-]\d{2}:\d{2} "
            r"\| Ralph: polling",
        )
        self.assertIn(
            " | Ralph: select-only target for issue #8: ralph/issue-8",
            lines[-1],
        )


if __name__ == "__main__":
    unittest.main()
