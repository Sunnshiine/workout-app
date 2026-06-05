from __future__ import annotations

import tempfile
import unittest
from pathlib import Path

from ralph.orchestrator.blocked import BlockedReport
from ralph.orchestrator.contracts import IssueComment, IssueContract
from ralph.orchestrator.gates import GATE_UI_INTEGRATION, GateResult, GateStatus
from ralph.orchestrator.prompt_context import (
    BLOCKED_REPORT_FILE,
    GATE_FAILURE_SUMMARY_FILE,
    ISSUE_CONTRACT_FILE,
    PHASE_CONTEXT_FILE,
    REPAIR_BRIEF_FILE,
    PhaseContext,
    PromptContextWriter,
    render_gate_failure_summary,
    render_issue_contract,
    render_phase_context,
)


def _contract(**overrides) -> IssueContract:
    base = dict(
        number=212,
        title="Add prompt artifacts",
        body="## What to build\n\nWrite compact context files.",
        labels=frozenset({"ready-for-agent"}),
        prd_number=200,
        ui_test_edits_authorized=False,
    )
    base.update(overrides)
    return IssueContract(**base)


def _failed_gate(*, excerpt: str = "AssertionError: header missing") -> GateResult:
    return GateResult(
        name=GATE_UI_INTEGRATION,
        status=GateStatus.FAILED,
        command=("xcodebuild", "test", "-only-testing:WorkoutTrackerUITests"),
        exit_status=65,
        log_path=Path("ralph/.artifacts/logs/issue-212-ui.log"),
        failure_excerpt=excerpt,
        ui_owned=True,
    )


def _phase_context(**overrides) -> PhaseContext:
    base = dict(
        role="You are the implementation agent for one issue.",
        phase="implement",
        target_branch="ralph/issue-212",
        complete_promise_line='<promise phase="implement">COMPLETE</promise>',
        blocked_promise_prefix='<promise phase="implement">BLOCKED:',
        allowed_actions=("Edit Swift sources", "Run swift test"),
        existing_pr_number=None,
        reference_paths=(
            "ralph/.artifacts/logs/issue-212-ui.log",
            "ralph/.artifacts/issue-212-ui-review.png",
        ),
    )
    base.update(overrides)
    return PhaseContext(**base)


class RenderIssueContractTests(unittest.TestCase):
    def test_includes_authority_and_body(self) -> None:
        out = render_issue_contract(_contract())
        self.assertIn("# Issue contract: #212", out)
        self.assertIn("- PRD: #200", out)
        self.assertIn("- UI integration test edits: not authorized", out)
        self.assertIn("ready-for-agent", out)
        self.assertIn("Write compact context files.", out)

    def test_ui_authorization_reflected(self) -> None:
        out = render_issue_contract(_contract(ui_test_edits_authorized=True))
        self.assertIn("- UI integration test edits: authorized", out)

    def test_comments_section_only_when_present(self) -> None:
        self.assertNotIn("## Comments for context", render_issue_contract(_contract()))
        with_comments = _contract(
            comments_for_context=(IssueComment(author="kevin", body="Try the new layout."),)
        )
        out = render_issue_contract(with_comments)
        self.assertIn("## Comments for context", out)
        self.assertIn("@kevin", out)


class RenderPhaseContextTests(unittest.TestCase):
    def test_carries_role_issue_target_actions_and_contract(self) -> None:
        out = render_phase_context(_contract(), _phase_context())
        self.assertIn("# Phase: implement", out)
        self.assertIn("You are the implementation agent", out)
        self.assertIn("- Number: #212", out)
        self.assertIn("- Branch: `ralph/issue-212`", out)
        self.assertIn("- Edit Swift sources", out)
        self.assertIn('<promise phase="implement">COMPLETE</promise>', out)
        self.assertIn('<promise phase="implement">BLOCKED:', out)

    def test_references_fuller_context_by_path_not_inline(self) -> None:
        out = render_phase_context(_contract(), _phase_context())
        # Points at the full contract artifact and the reference paths by path.
        self.assertIn(f"`{ISSUE_CONTRACT_FILE}`", out)
        self.assertIn("`ralph/.artifacts/logs/issue-212-ui.log`", out)
        self.assertIn("Open only what you need", out)
        # The full issue body must NOT be embedded in the phase context.
        self.assertNotIn("Write compact context files.", out)

    def test_existing_pr_number_rendered(self) -> None:
        out = render_phase_context(_contract(), _phase_context(existing_pr_number=99))
        self.assertIn("- Open PR: #99", out)


class RenderGateFailureSummaryTests(unittest.TestCase):
    def test_compact_summary_points_at_full_log(self) -> None:
        out = render_gate_failure_summary(_failed_gate())
        self.assertIn(f"# Gate failure: {GATE_UI_INTEGRATION}", out)
        self.assertIn("- Exit status: 65", out)
        self.assertIn("- Ownership: UI-owned repair cycle", out)
        self.assertIn("AssertionError: header missing", out)
        self.assertIn("`ralph/.artifacts/logs/issue-212-ui.log`", out)

    def test_excerpt_is_redacted(self) -> None:
        out = render_gate_failure_summary(
            _failed_gate(excerpt="GH_TOKEN=ghp_supersecretvalue\nboom")
        )
        self.assertNotIn("ghp_supersecretvalue", out)
        self.assertIn("[REDACTED]", out)


class PromptContextWriterTests(unittest.TestCase):
    def test_writes_all_five_artifacts(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            run_dir = Path(tmp) / "context" / "issue-212"
            writer = PromptContextWriter(run_dir)
            contract = _contract()
            gate = _failed_gate()
            report = BlockedReport(
                issue=212,
                title="Add prompt artifacts",
                prd_number=200,
                intended_branch="ralph/issue-212",
                failed_phase_or_gate=GATE_UI_INTEGRATION,
                failing_command="xcodebuild test",
                exit_status=65,
                repair_attempted=True,
                repair_result="failed",
            )

            issue_path = writer.write_issue_contract(contract)
            phase_path = writer.write_phase_context(contract, _phase_context())
            gate_path = writer.write_gate_failure_summary(gate)
            repair_path = writer.write_repair_brief(contract, gate, target_branch="ralph/issue-212")
            blocked_path = writer.write_blocked_report(report)

            self.assertEqual(issue_path.name, ISSUE_CONTRACT_FILE)
            self.assertEqual(phase_path.name, PHASE_CONTEXT_FILE)
            self.assertEqual(gate_path.name, GATE_FAILURE_SUMMARY_FILE)
            self.assertEqual(repair_path.name, REPAIR_BRIEF_FILE)
            self.assertEqual(blocked_path.name, BLOCKED_REPORT_FILE)

            for path in (issue_path, phase_path, gate_path, repair_path, blocked_path):
                self.assertTrue(path.exists())
                self.assertTrue(path.read_text(encoding="utf-8").strip())

    def test_creates_run_dir_on_first_write(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            run_dir = Path(tmp) / "deep" / "context"
            self.assertFalse(run_dir.exists())
            PromptContextWriter(run_dir).write_issue_contract(_contract())
            self.assertTrue((run_dir / ISSUE_CONTRACT_FILE).exists())

    def test_repair_brief_matches_render_repair_brief(self) -> None:
        from ralph.orchestrator.repair import render_repair_brief

        with tempfile.TemporaryDirectory() as tmp:
            writer = PromptContextWriter(Path(tmp))
            contract = _contract()
            gate = _failed_gate()
            written = writer.write_repair_brief(
                contract, gate, target_branch="ralph/issue-212"
            ).read_text(encoding="utf-8")
            expected = render_repair_brief(
                contract,
                gate,
                target_branch="ralph/issue-212",
                existing_pr_number=None,
                artifact_paths=(),
            )
            self.assertEqual(written, expected)


if __name__ == "__main__":
    unittest.main()
