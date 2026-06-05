from __future__ import annotations

import tempfile
import unittest
from pathlib import Path

from ralph.orchestrator.contracts import IssueContract
from ralph.orchestrator.engine import FakeEngine
from ralph.orchestrator.gates import (
    GATE_SWIFT_TEST,
    GATE_UI_INTEGRATION,
    GateResult,
    GateStatus,
)
from ralph.orchestrator.phase import PhaseStatus
from ralph.orchestrator.repair import (
    PHASE_REPAIR_UI_GATE,
    PHASE_REVIEW_AFTER_REPAIR,
    RepairCoordinator,
    RepairError,
    render_repair_brief,
    repair_brief_relpath,
    requires_review,
)


def _contract(number: int = 42, *, body: str = "Make the screen render.", prd: int | None = None):
    return IssueContract(
        number=number,
        title="Fix the session header",
        body=body,
        prd_number=prd,
    )


def _failed_ui_gate(*, command=("xcodebuild", "test"), excerpt="UI test failed", exit_status=65):
    return GateResult(
        name=GATE_UI_INTEGRATION,
        status=GateStatus.FAILED,
        command=command,
        exit_status=exit_status,
        log_path=Path("ralph/.artifacts/logs/issue-42-ui.log"),
        failure_excerpt=excerpt,
        ui_owned=True,
    )


def _passing_ui_gate():
    return GateResult(
        name=GATE_UI_INTEGRATION,
        status=GateStatus.PASSED,
        command=("xcodebuild", "test"),
        exit_status=0,
        ui_owned=True,
    )


class _GateRerunQueue:
    """Scripts the SINGLE rerun the coordinator is allowed to perform.

    Each call pops one queued ``GateResult``; an extra call (which would be an
    infinite-retry bug) raises so the no-loop guarantee is enforced by the test.
    """

    def __init__(self, results):
        self._results = list(results)
        self.calls = 0

    def __call__(self):
        self.calls += 1
        if not self._results:
            raise AssertionError("gate was rerun more than once (no infinite retry allowed)")
        return self._results.pop(0)


class RequiresReviewTests(unittest.TestCase):
    def test_production_swift_requires_review(self):
        self.assertTrue(requires_review(["WorkoutTracker/Views/SessionView.swift"]))

    def test_nested_production_swift_requires_review(self):
        self.assertTrue(requires_review(["WorkoutTracker/Progress/MoveOn.swift"]))

    def test_test_file_requires_review(self):
        self.assertTrue(requires_review(["Tests/UI/SessionUITests.swift"]))

    def test_project_and_package_files_require_review(self):
        for path in (
            "Package.swift",
            "project.yml",
            "WorkoutTracker.xcodeproj/project.pbxproj",
        ):
            with self.subTest(path=path):
                self.assertTrue(requires_review([path]))

    def test_non_reviewable_files_do_not_require_review(self):
        self.assertFalse(
            requires_review(
                [
                    "ralph/.artifacts/screenshots/session.png",
                    "WorkoutTracker/Fixtures/seed.json",
                    "docs/notes.md",
                ]
            )
        )

    def test_empty_changes_do_not_require_review(self):
        self.assertFalse(requires_review([]))


class RepairCoordinatorRunTests(unittest.TestCase):
    def setUp(self):
        self._tmp = tempfile.TemporaryDirectory()
        self.repo_root = Path(self._tmp.name)
        self.workdir = self.repo_root / "worktrees" / "issue-42"
        self.workdir.mkdir(parents=True)

    def tearDown(self):
        self._tmp.cleanup()

    def _coordinator(self, engine):
        return RepairCoordinator(engine, repo_root=self.repo_root, workdir=self.workdir)

    def test_repair_success_ships(self):
        engine = FakeEngine()
        rerun = _GateRerunQueue([_passing_ui_gate()])
        coordinator = self._coordinator(engine)

        outcome = coordinator.run(
            _contract(),
            _failed_ui_gate(),
            rerun_gate=rerun,
            changed_files=lambda: ["WorkoutTracker/Views/SessionView.swift"],
            target_branch="ralph/issue-42",
        )

        self.assertTrue(outcome.shipped)
        self.assertTrue(outcome.repair_attempted)
        self.assertEqual(rerun.calls, 1)

    def test_second_ui_failure_does_not_ship(self):
        engine = FakeEngine()
        rerun = _GateRerunQueue([_failed_ui_gate(excerpt="still failing")])
        coordinator = self._coordinator(engine)

        outcome = coordinator.run(
            _contract(),
            _failed_ui_gate(),
            rerun_gate=rerun,
            changed_files=lambda: ["WorkoutTracker/Views/SessionView.swift"],
            target_branch="ralph/issue-42",
        )

        self.assertFalse(outcome.shipped)
        self.assertTrue(outcome.repair_attempted)
        self.assertEqual(outcome.rerun_gate.status, GateStatus.FAILED)
        self.assertEqual(rerun.calls, 1)

    def test_exactly_one_repair_attempt_no_loop(self):
        # The rerun queue raises if called twice; a single FAILED rerun must not
        # trigger another repair attempt.
        engine = FakeEngine()
        rerun = _GateRerunQueue([_failed_ui_gate()])
        coordinator = self._coordinator(engine)

        coordinator.run(
            _contract(),
            _failed_ui_gate(),
            rerun_gate=rerun,
            changed_files=lambda: [],
            target_branch="ralph/issue-42",
        )

        self.assertEqual(rerun.calls, 1)
        repair_calls = [c for c in engine.calls if c.phase == PHASE_REPAIR_UI_GATE]
        self.assertEqual(len(repair_calls), 1)

    def test_review_runs_when_repair_touches_reviewable_code(self):
        engine = FakeEngine()
        rerun = _GateRerunQueue([_passing_ui_gate()])
        coordinator = self._coordinator(engine)

        outcome = coordinator.run(
            _contract(),
            _failed_ui_gate(),
            rerun_gate=rerun,
            changed_files=lambda: ["WorkoutTracker/Views/SessionView.swift"],
            target_branch="ralph/issue-42",
        )

        self.assertTrue(outcome.review_ran)
        self.assertIsNotNone(outcome.review_phase)
        review_calls = [c for c in engine.calls if c.phase == PHASE_REVIEW_AFTER_REPAIR]
        self.assertEqual(len(review_calls), 1)
        self.assertIn("swift-reviewer", review_calls[0].prompt)
        self.assertIn("spec-conformance-reviewer", review_calls[0].prompt)

    def test_review_skipped_when_repair_touches_only_non_reviewable(self):
        engine = FakeEngine()
        rerun = _GateRerunQueue([_passing_ui_gate()])
        coordinator = self._coordinator(engine)

        outcome = coordinator.run(
            _contract(),
            _failed_ui_gate(),
            rerun_gate=rerun,
            changed_files=lambda: ["ralph/.artifacts/screenshots/session.png"],
            target_branch="ralph/issue-42",
        )

        self.assertFalse(outcome.review_ran)
        self.assertIsNone(outcome.review_phase)
        review_calls = [c for c in engine.calls if c.phase == PHASE_REVIEW_AFTER_REPAIR]
        self.assertEqual(review_calls, [])

    def test_review_skipped_when_repair_changed_nothing(self):
        engine = FakeEngine()
        rerun = _GateRerunQueue([_passing_ui_gate()])
        coordinator = self._coordinator(engine)

        outcome = coordinator.run(
            _contract(),
            _failed_ui_gate(),
            rerun_gate=rerun,
            changed_files=lambda: [],
            target_branch="ralph/issue-42",
        )

        self.assertFalse(outcome.review_ran)
        review_calls = [c for c in engine.calls if c.phase == PHASE_REVIEW_AFTER_REPAIR]
        self.assertEqual(review_calls, [])

    def test_repair_phase_runs_in_failing_worktree(self):
        engine = FakeEngine()
        rerun = _GateRerunQueue([_passing_ui_gate()])
        coordinator = self._coordinator(engine)

        coordinator.run(
            _contract(),
            _failed_ui_gate(),
            rerun_gate=rerun,
            changed_files=lambda: [],
            target_branch="ralph/issue-42",
        )

        repair_call = next(c for c in engine.calls if c.phase == PHASE_REPAIR_UI_GATE)
        self.assertEqual(repair_call.workdir, self.workdir)
        self.assertEqual(repair_call.issue_number, 42)

    def test_brief_is_written_to_expected_path(self):
        engine = FakeEngine()
        rerun = _GateRerunQueue([_passing_ui_gate()])
        coordinator = self._coordinator(engine)

        outcome = coordinator.run(
            _contract(),
            _failed_ui_gate(),
            rerun_gate=rerun,
            changed_files=lambda: [],
            target_branch="ralph/issue-42",
        )

        expected = self.repo_root / repair_brief_relpath(42)
        self.assertEqual(outcome.brief_path, expected)
        self.assertTrue(expected.is_file())
        text = expected.read_text(encoding="utf-8")
        self.assertIn("UI repair brief: issue #42", text)
        self.assertIn(GATE_UI_INTEGRATION, text)
        self.assertIn("ralph/issue-42", text)

    def test_non_ui_owned_gate_is_rejected(self):
        engine = FakeEngine()
        coordinator = self._coordinator(engine)
        non_ui = GateResult(
            name=GATE_SWIFT_TEST,
            status=GateStatus.FAILED,
            command=("swift", "test"),
            ui_owned=False,
        )

        with self.assertRaises(RepairError):
            coordinator.run(
                _contract(),
                non_ui,
                rerun_gate=_GateRerunQueue([_passing_ui_gate()]),
                changed_files=lambda: [],
                target_branch="ralph/issue-42",
            )

    def test_repair_phase_blocked_still_reruns_gate_once(self):
        # Even if the repair agent reports blocked, the coordinator reruns the
        # gate exactly once and lets the gate decide ship vs escalate.
        engine = FakeEngine(default_status=PhaseStatus.BLOCKED)
        rerun = _GateRerunQueue([_failed_ui_gate()])
        coordinator = self._coordinator(engine)

        outcome = coordinator.run(
            _contract(),
            _failed_ui_gate(),
            rerun_gate=rerun,
            changed_files=lambda: [],
            target_branch="ralph/issue-42",
        )

        self.assertFalse(outcome.shipped)
        self.assertEqual(rerun.calls, 1)


class RenderRepairBriefTests(unittest.TestCase):
    def test_brief_redacts_secret_excerpt(self):
        gate = _failed_ui_gate(
            excerpt="GH_TOKEN = ghp_realsecretvalue1234\nUI test failed at line 12",
        )
        brief = render_repair_brief(
            _contract(),
            gate,
            target_branch="ralph/issue-42",
            existing_pr_number=7,
            artifact_paths=["ralph/.artifacts/screenshots/session.png"],
        )

        self.assertNotIn("ghp_realsecretvalue1234", brief)
        self.assertIn("[REDACTED]", brief)
        self.assertIn("UI test failed at line 12", brief)

    def test_brief_includes_target_and_artifact_context(self):
        gate = _failed_ui_gate()
        brief = render_repair_brief(
            _contract(prd=99),
            gate,
            target_branch="ralph/prd-99",
            existing_pr_number=12,
            artifact_paths=["ralph/.artifacts/screenshots/session.png"],
        )

        self.assertIn("ralph/prd-99", brief)
        self.assertIn("#12", brief)
        self.assertIn("#99", brief)
        self.assertIn("ralph/.artifacts/logs/issue-42-ui.log", brief)
        self.assertIn("ralph/.artifacts/screenshots/session.png", brief)
        self.assertIn("Make the screen render.", brief)

    def test_brief_handles_no_open_pr_and_no_artifacts(self):
        gate = GateResult(
            name=GATE_UI_INTEGRATION,
            status=GateStatus.FAILED,
            command=(),
            ui_owned=True,
        )
        brief = render_repair_brief(
            _contract(),
            gate,
            target_branch="ralph/issue-42",
            existing_pr_number=None,
            artifact_paths=(),
        )

        self.assertIn("none", brief)
        self.assertIn("None recorded", brief)


if __name__ == "__main__":
    unittest.main()
