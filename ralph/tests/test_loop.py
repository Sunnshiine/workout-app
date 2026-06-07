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
from ralph.orchestrator.gates import (
    GATE_SWIFT_TEST,
    GATE_SWIFTLINT,
    GATE_UI_INTEGRATION,
    GATE_UNIT_COMPONENT,
    GATE_VISUAL_REGRESSION,
    GATE_XCODEGEN,
    CommandResult,
    GateRunner,
)
from ralph.orchestrator.github import FakeGitHubClient
from ralph.orchestrator.loop import (
    UI_INTEGRATION_SMOKE_SELECTORS,
    IssueSelector,
    OriginMain,
    RalphLoop,
    RalphLoopError,
    _format_ralph_log_line,
    _gate_name_for_command,
    _gate_specs,
)
from ralph.orchestrator.publish import (
    LABEL_AGENT_ACTIVE,
    LABEL_AGENT_BLOCKED,
    LABEL_AGENT_IMPLEMENTED,
    LABEL_READY_FOR_AGENT,
    LABEL_READY_FOR_HUMAN,
    GitOutcome,
)
from ralph.orchestrator.repair import PHASE_REPAIR_UI_GATE
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
    for name in ("implement.md", "review.md", "ui-verify.md"):
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

    def test_skips_candidate_whose_blocked_by_dependency_is_open(self) -> None:
        client = FakeGitHubClient(
            issues={
                10: _issue(10, title="Dependency", labels=[LABEL_AGENT_ACTIVE]),
                11: _issue(11, title="Dependent", body="## Blocked by\n\n- #10\n"),
            }
        )

        selected = IssueSelector(client).select_next()

        self.assertIsNone(selected)

    def test_selects_candidate_when_blocked_by_dependency_is_closed(self) -> None:
        client = FakeGitHubClient(
            issues={
                10: _issue(10, title="Dependency", body="Done") | {"state": "CLOSED"},
                11: _issue(11, title="Dependent", body="## Blocked by\n\n- #10\n"),
            }
        )

        selected = IssueSelector(client).select_next()

        self.assertIsNotNone(selected)
        self.assertEqual(selected.number, 11)

    def test_selects_candidate_when_blocked_by_dependency_is_agent_implemented(self) -> None:
        client = FakeGitHubClient(
            issues={
                10: _issue(10, title="Dependency", labels=[LABEL_AGENT_IMPLEMENTED]),
                11: _issue(11, title="Dependent", body="## Blocked by\n\n- #10\n"),
            }
        )

        selected = IssueSelector(client).select_next()

        self.assertIsNotNone(selected)
        self.assertEqual(selected.number, 11)

    def test_skips_candidate_whose_blocked_by_dependency_is_agent_active(self) -> None:
        client = FakeGitHubClient(
            issues={
                10: _issue(10, title="Dependency", labels=[LABEL_AGENT_ACTIVE]),
                11: _issue(11, title="Dependent", body="## Blocked by\n\n- #10\n"),
            }
        )

        selected = IssueSelector(client).select_next()

        self.assertIsNone(selected)

    def test_skips_candidate_whose_blocked_by_dependency_is_ready_for_agent(self) -> None:
        # #10 is itself ready (and selectable), but its dependent #11 must not be
        # picked while #10 has not yet landed.
        client = FakeGitHubClient(
            issues={
                10: _issue(10, title="Dependency", labels=[LABEL_READY_FOR_AGENT]),
                11: _issue(11, title="Dependent", body="## Blocked by\n\n- #10\n"),
            }
        )

        selected = IssueSelector(client).select_next()

        self.assertIsNotNone(selected)
        self.assertNotEqual(selected.number, 11)

    def test_agent_blocked_dependency_halts_dependent(self) -> None:
        client = FakeGitHubClient(
            issues={
                10: _issue(10, title="Dependency", labels=[LABEL_AGENT_BLOCKED]),
                11: _issue(11, title="Dependent", body="## Blocked by\n\n- #10\n"),
            }
        )

        selected = IssueSelector(client).select_next()

        self.assertIsNone(selected)

    def test_agent_blocked_middle_link_halts_transitive_dependent(self) -> None:
        # Depth-2 chain 20 -> 21 -> 22 with a BLOCKED middle link (#21).
        # #21 is agent-blocked and #20 is agent-implemented, so a naive immediate
        # -parent check on #22 (whose only ## Blocked by is #21) must still leave
        # #22 ineligible: the halt propagates down the whole transitive chain.
        client = FakeGitHubClient(
            issues={
                20: _issue(20, title="Root", labels=[LABEL_AGENT_IMPLEMENTED]),
                21: _issue(
                    21,
                    title="Blocked middle",
                    body="## Blocked by\n\n- #20\n",
                    labels=[LABEL_AGENT_BLOCKED],
                ),
                22: _issue(22, title="Transitive dependent", body="## Blocked by\n\n- #21\n"),
            }
        )

        selected = IssueSelector(client).select_next()

        self.assertIsNone(selected)


class RalphLogTests(unittest.TestCase):
    def test_formats_local_timestamp_before_ralph_message(self) -> None:
        now = datetime(2026, 6, 5, 14, 31, 8, tzinfo=timezone(timedelta(hours=-4)))

        line = _format_ralph_log_line("issue #190 ui-verify started", now=now)

        self.assertEqual(
            line,
            "2026-06-05T14:31:08-04:00 | Ralph: issue #190 ui-verify started",
        )


class RalphGateSpecTests(unittest.TestCase):
    def test_full_gate_runs_visual_regression_between_unit_and_ui_tests(self) -> None:
        specs = _gate_specs("iPhone 17 Pro")

        self.assertEqual(
            [spec.name for spec in specs],
            [
                GATE_SWIFT_TEST,
                GATE_XCODEGEN,
                GATE_UNIT_COMPONENT,
                GATE_VISUAL_REGRESSION,
                GATE_UI_INTEGRATION,
                GATE_SWIFTLINT,
            ],
        )
        visual = specs[3]
        self.assertIn("-only-testing:WorkoutTrackerSnapshotTests", visual.command)
        self.assertIn("platform=iOS Simulator,name=iPhone 17 Pro", visual.command)
        self.assertEqual(_gate_name_for_command(visual.command), GATE_VISUAL_REGRESSION)

    def test_gate_specs_can_target_a_specific_simulator_id(self) -> None:
        specs = _gate_specs("iPhone 17 Pro", simulator_id="ABC-123")

        for spec in specs:
            if spec.command and spec.command[0] == "xcodebuild":
                self.assertIn("platform=iOS Simulator,id=ABC-123", spec.command)
                self.assertNotIn(
                    "platform=iOS Simulator,name=iPhone 17 Pro",
                    spec.command,
                )
                self.assertIn("-clonedSourcePackagesDirPath", spec.command)
                self.assertIn(".ralph-spm", spec.command)

        ui = next(spec for spec in specs if spec.name == GATE_UI_INTEGRATION)
        self.assertIn("-test-timeouts-enabled", ui.command)
        self.assertIn("NO", ui.command)
        self.assertIn("-parallel-testing-enabled", ui.command)

    def test_ui_gate_runs_only_smoke_class_selectors(self) -> None:
        specs = _gate_specs("iPhone 17 Pro")

        ui = next(spec for spec in specs if spec.name == GATE_UI_INTEGRATION)

        self.assertEqual(
            UI_INTEGRATION_SMOKE_SELECTORS,
            (
                "-only-testing:WorkoutTrackerUITests/WorkoutTrackerUISmokeTests",
                "-only-testing:WorkoutTrackerUITests/PartiallyUploadedBlockUISmokeTests",
            ),
        )
        self.assertNotIn("-only-testing:WorkoutTrackerUITests", ui.command)
        for selector in UI_INTEGRATION_SMOKE_SELECTORS:
            self.assertIn(selector, ui.command)
        self.assertEqual(_gate_name_for_command(ui.command), GATE_UI_INTEGRATION)

    def test_full_ui_target_selector_is_not_a_ui_gate(self) -> None:
        command = ("xcodebuild", "test", "-only-testing:WorkoutTrackerUITests")

        self.assertEqual(_gate_name_for_command(command), "xcodebuild")


class _VisualGateRunnerFactory:
    """Gate runner factory that fails the visual gate, then scripts the rerun.

    ``rerun_passes`` decides whether the single allowed rerun of the visual gate
    passes (repair ships) or fails again (escalate to blocked). Every command is
    recorded so a test can assert the gate was rerun exactly once.
    """

    def __init__(self, *, rerun_passes: bool) -> None:
        self._rerun_passes = rerun_passes
        self.visual_runs = 0

    def factory(self, _workdir: Path, _iteration: int, _issue: int) -> GateRunner:
        def run(command) -> CommandResult:
            if _gate_name_for_command(command) != GATE_VISUAL_REGRESSION:
                return CommandResult(exit_status=0)
            self.visual_runs += 1
            if self.visual_runs == 1:
                return CommandResult(exit_status=65, output="snapshot mismatch")
            return CommandResult(exit_status=0 if self._rerun_passes else 65)

        return GateRunner(run)


class RalphRepairWiringTests(unittest.TestCase):
    def setUp(self) -> None:
        self.tmp = tempfile.TemporaryDirectory()
        self.repo = Path(self.tmp.name) / "repo"
        self.repo.mkdir()
        _init_repo(self.repo)

    def tearDown(self) -> None:
        self.tmp.cleanup()

    def _loop(self, *, client, engine, gates, publish):
        return RalphLoop(
            config=RunConfig(engine="fake", max_iterations=1),
            repo_root=self.repo,
            client=client,
            engine=engine,
            origin_main=_OriginMain(),
            worktrees=WorktreeManager(self.repo, runner=default_git_runner),
            gate_runner_factory=gates.factory,
            publish_runner_factory=publish.factory,
        )

    def test_ui_owned_gate_failure_repairs_and_ships_when_rerun_passes(self) -> None:
        client = FakeGitHubClient(issues={7: _issue(7, title="Visual change")})
        engine = FakeEngine()
        gates = _VisualGateRunnerFactory(rerun_passes=True)
        publish = _RecordingPublishRunner()
        loop = self._loop(client=client, engine=engine, gates=gates, publish=publish)

        summary = loop.run()

        self.assertEqual(summary.issues_completed, (7,))
        self.assertEqual(gates.visual_runs, 2)
        repair_calls = [c for c in engine.calls if c.phase == PHASE_REPAIR_UI_GATE]
        self.assertEqual(len(repair_calls), 1)
        self.assertIn(LABEL_AGENT_IMPLEMENTED, client.issue_labels(7))
        self.assertEqual([call[0] for call in publish.calls], ["commit", "push"])

    def test_ui_owned_gate_failure_escalates_blocked_when_rerun_fails(self) -> None:
        client = FakeGitHubClient(issues={7: _issue(7, title="Visual change")})
        engine = FakeEngine()
        gates = _VisualGateRunnerFactory(rerun_passes=False)
        publish = _RecordingPublishRunner()
        loop = self._loop(client=client, engine=engine, gates=gates, publish=publish)

        summary = loop.run()

        self.assertEqual(summary.issues_blocked, (7,))
        self.assertEqual(gates.visual_runs, 2)
        repair_calls = [c for c in engine.calls if c.phase == PHASE_REPAIR_UI_GATE]
        self.assertEqual(len(repair_calls), 1)
        self.assertIn(LABEL_READY_FOR_HUMAN, client.issue_labels(7))
        blocked_pr = client.find_pr_by_head_branch("ralph/issue-7-blocked")
        self.assertIsNotNone(blocked_pr)
        comments = [c[2] for c in client.calls if c[0] == "comment_issue" and c[1] == 7]
        self.assertTrue(any("Repair attempted: yes" in body for body in comments))


class RalphLoopTests(unittest.TestCase):
    def setUp(self) -> None:
        self.tmp = tempfile.TemporaryDirectory()
        self.repo = Path(self.tmp.name) / "repo"
        self.repo.mkdir()
        _init_repo(self.repo)

    def tearDown(self) -> None:
        self.tmp.cleanup()

    def test_blocked_by_chain_stacks_both_issues_onto_one_root_pr(self) -> None:
        # End-to-end fake-engine run over a two-issue chain: root #100 lands first
        # on ralph/issue-100, then dependent #101 (## Blocked by #100, now
        # agent-implemented) is selected, bases on the root branch, and squashes
        # onto the same branch/PR — one root PR with both Closes lines.
        remote = Path(self.tmp.name) / "remote.git"
        _git(remote.parent, "init", "--bare", "-b", "main", str(remote))
        _git(self.repo, "remote", "add", "origin", str(remote))
        _git(self.repo, "push", "origin", "main")

        client = FakeGitHubClient(
            issues={
                100: _issue(100, title="Chain root"),
                101: _issue(101, title="Chain dependent", body="## Blocked by\n\n- #100\n"),
            }
        )
        loop = RalphLoop(
            config=RunConfig(engine="fake", max_iterations=2),
            repo_root=self.repo,
            client=client,
            engine=FakeEngine(),
            worktrees=WorktreeManager(self.repo, runner=default_git_runner),
            gate_runner_factory=lambda _w, _i, _n: GateRunner(
                lambda _c: CommandResult(exit_status=0)
            ),
        )

        summary = loop.run()

        self.assertEqual(summary.issues_selected, (100, 101))
        self.assertEqual(summary.issues_completed, (100, 101))
        self.assertIn(LABEL_AGENT_IMPLEMENTED, client.issue_labels(100))
        self.assertIn(LABEL_AGENT_IMPLEMENTED, client.issue_labels(101))

        root_pr = client.find_pr_by_head_branch("ralph/issue-100")
        self.assertIsNotNone(root_pr)
        self.assertIsNone(client.find_pr_by_head_branch("ralph/issue-101"))
        self.assertIn("Closes #100", root_pr["body"])
        self.assertIn("Closes #101", root_pr["body"])

        commits = subprocess.run(
            ["git", "-C", str(self.repo), "log", "--format=%s", "origin/ralph/issue-100"],
            check=True,
            capture_output=True,
            text=True,
        ).stdout
        self.assertEqual(commits.count("via Ralph"), 2)

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


class SimulatorPoolLoopWiringTests(unittest.TestCase):
    """RalphLoop correctly acquires a pool lease and threads the UDID to gate commands."""

    def setUp(self) -> None:
        self.tmp = tempfile.TemporaryDirectory()
        self.repo = Path(self.tmp.name) / "repo"
        self.repo.mkdir()
        _init_repo(self.repo)
        self.lease_dir = Path(self.tmp.name) / "leases"
        self.recorded_destinations: list[str] = []

    def tearDown(self) -> None:
        self.tmp.cleanup()

    def _recording_gate_factory(self, destinations: list[str]):
        """Gate runner that records the -destination arg of each xcodebuild call."""

        def factory(_workdir: Path, _iteration: int, _issue: int) -> GateRunner:
            def run(command) -> CommandResult:
                if command and command[0] == "xcodebuild":
                    try:
                        idx = list(command).index("-destination")
                        destinations.append(command[idx + 1])
                    except (ValueError, IndexError):
                        pass
                return CommandResult(exit_status=0)

            return GateRunner(run)

        return factory

    def _loop(self, *, config: RunConfig, client, engine, publish) -> RalphLoop:
        return RalphLoop(
            config=config,
            repo_root=self.repo,
            client=client,
            engine=engine,
            origin_main=_OriginMain(),
            worktrees=WorktreeManager(self.repo, runner=default_git_runner),
            gate_runner_factory=self._recording_gate_factory(self.recorded_destinations),
            publish_runner_factory=publish.factory,
            simulator_lease_dir=self.lease_dir,
        )

    def test_pool_udid_reaches_xcodebuild_destination_arg(self) -> None:
        client = FakeGitHubClient(issues={50: _issue(50, title="Pool test")})
        publish = _RecordingPublishRunner()
        config = RunConfig(
            engine="fake",
            max_iterations=1,
            simulator_pool=("POOL-UDID-50",),
        )
        loop = self._loop(client=client, engine=FakeEngine(), publish=publish, config=config)

        summary = loop.run()

        self.assertEqual(summary.issues_completed, (50,))
        self.assertTrue(
            all("id=POOL-UDID-50" in dest for dest in self.recorded_destinations),
            f"Expected all destinations to use POOL-UDID-50; got {self.recorded_destinations}",
        )

    def test_explicit_simulator_id_bypasses_pool(self) -> None:
        client = FakeGitHubClient(issues={51: _issue(51, title="Explicit sim")})
        publish = _RecordingPublishRunner()
        config = RunConfig(
            engine="fake",
            max_iterations=1,
            simulator_id="EXPLICIT-UDID",
            simulator_pool=("POOL-UDID-IGNORED",),
        )
        loop = self._loop(client=client, engine=FakeEngine(), publish=publish, config=config)

        summary = loop.run()

        self.assertEqual(summary.issues_completed, (51,))
        self.assertTrue(
            all("id=EXPLICIT-UDID" in dest for dest in self.recorded_destinations),
            f"Expected explicit UDID; got {self.recorded_destinations}",
        )
        # The pool lease dir should not have any active lease files.
        if self.lease_dir.exists():
            self.assertEqual(list(self.lease_dir.glob("*.lease")), [])

    def test_pool_lease_file_is_released_after_run_completes(self) -> None:
        client = FakeGitHubClient(issues={52: _issue(52, title="Release test")})
        publish = _RecordingPublishRunner()
        config = RunConfig(
            engine="fake",
            max_iterations=1,
            simulator_pool=("POOL-UDID-52",),
        )
        loop = self._loop(client=client, engine=FakeEngine(), publish=publish, config=config)
        loop.run()

        # After run, lease file must be gone.
        if self.lease_dir.exists():
            self.assertEqual(list(self.lease_dir.glob("*.lease")), [])

    def test_pool_with_no_eligible_issues_does_not_create_lease(self) -> None:
        # No issues → no lease should be acquired.
        client = FakeGitHubClient(issues={})
        publish = _RecordingPublishRunner()
        config = RunConfig(
            engine="fake",
            max_iterations=1,
            simulator_pool=("POOL-UDID-99",),
        )
        loop = self._loop(client=client, engine=FakeEngine(), publish=publish, config=config)
        loop.run()

        # Lease dir either does not exist or has no lease files.
        if self.lease_dir.exists():
            self.assertEqual(list(self.lease_dir.glob("*.lease")), [])


if __name__ == "__main__":
    unittest.main()
