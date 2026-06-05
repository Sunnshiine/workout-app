from __future__ import annotations

import unittest

from ralph.orchestrator.authority import (
    UI_REVIEW_PASS_LINE,
    VISUAL_BASELINE_DIR,
    AuthorityGate,
    NameStatusEntry,
)
from ralph.orchestrator.contracts import IssueContract


def _contract(*, authorized: bool) -> IssueContract:
    return IssueContract(
        number=1,
        title="t",
        body="",
        ui_test_edits_authorized=authorized,
    )


class _FakeDiff:
    """Diff seam fake: maps (base, tip) range keys to name-status entries."""

    def __init__(self, ranges: dict[tuple[str, str | None], list[NameStatusEntry]]) -> None:
        self._ranges = ranges

    def __call__(self, base, tip, pathspecs):
        entries = self._ranges.get((base, tip), [])
        # Honor the pathspec filter the way git would.
        return tuple(e for e in entries if any(e.path.startswith(p) for p in pathspecs))


# ---- UI integration test edit authority ---------------------------------


class UiTestAuthorityTests(unittest.TestCase):
    def _gate(self, ranges):
        return AuthorityGate(_FakeDiff(ranges))

    def test_unauthorized_issue_range_ui_test_change_blocks(self) -> None:
        gate = self._gate({("base", "tip"): [NameStatusEntry("M", "Tests/UI/LoginUITests.swift")]})
        decision = gate.check_ui_test_authority(
            _contract(authorized=False),
            issue_base="base",
            issue_tip="tip",
            ui_phase_base="uib",
            ui_phase_tip="uit",
        )
        self.assertTrue(decision.blocked)
        self.assertTrue(decision.gate.ui_owned)

    def test_authorized_implementation_phase_ui_test_edit_passes(self) -> None:
        gate = self._gate({("base", "tip"): [NameStatusEntry("M", "Tests/UI/LoginUITests.swift")]})
        decision = gate.check_ui_test_authority(
            _contract(authorized=True),
            issue_base="base",
            issue_tip="tip",
            ui_phase_base="uib",
            ui_phase_tip="uit",
        )
        self.assertTrue(decision.allowed)

    def test_ui_verify_phase_ui_test_edit_blocks_unconditionally(self) -> None:
        # Even with authorization granted, a UI-verify-phase edit must block.
        gate = self._gate({("uib", "uit"): [NameStatusEntry("M", "Tests/UI/LoginUITests.swift")]})
        decision = gate.check_ui_test_authority(
            _contract(authorized=True),
            issue_base="base",
            issue_tip="tip",
            ui_phase_base="uib",
            ui_phase_tip="uit",
        )
        self.assertTrue(decision.blocked)
        self.assertIn("UI verification phase", decision.gate.failure_excerpt)

    def test_unauthorized_project_wiring_change_blocks(self) -> None:
        gate = self._gate({("base", "tip"): [NameStatusEntry("M", "project.yml")]})
        decision = gate.check_ui_test_authority(
            _contract(authorized=False),
            issue_base="base",
            issue_tip="tip",
            ui_phase_base="uib",
            ui_phase_tip="uit",
        )
        self.assertTrue(decision.blocked)

    def test_no_ui_changes_passes(self) -> None:
        gate = self._gate({})
        decision = gate.check_ui_test_authority(
            _contract(authorized=False),
            issue_base="base",
            issue_tip="tip",
            ui_phase_base="uib",
            ui_phase_tip="uit",
        )
        self.assertTrue(decision.allowed)


# ---- Visual Baseline authority (ADR 0007) -------------------------------


class VisualBaselineAuthorityTests(unittest.TestCase):
    def _gate(self, entries, *, review=None):
        ranges = {("HEAD", None): list(entries)}
        reader = (lambda _p: review) if review is not None else None
        return AuthorityGate(_FakeDiff(ranges), review_reader=reader)

    def _entry(self, status: str) -> NameStatusEntry:
        return NameStatusEntry(status, f"{VISUAL_BASELINE_DIR}/SessionView.png")

    def test_added_baseline_is_allowed(self) -> None:
        gate = self._gate([self._entry("A")])
        self.assertTrue(gate.check_visual_baseline().allowed)

    def test_modified_baseline_with_pass_review_is_allowed(self) -> None:
        review = f"some findings\n{UI_REVIEW_PASS_LINE}"
        gate = self._gate([self._entry("M")], review=review)
        self.assertTrue(gate.check_visual_baseline().allowed)

    def test_modified_baseline_without_pass_review_blocks(self) -> None:
        gate = self._gate([self._entry("M")], review="findings\nNEEDS WORK")
        self.assertTrue(gate.check_visual_baseline().blocked)

    def test_modified_baseline_without_artifact_blocks(self) -> None:
        # review_reader returns None -> no saved artifact.
        gate = AuthorityGate(
            _FakeDiff({("HEAD", None): [self._entry("M")]}),
            review_reader=lambda _p: None,
        )
        self.assertTrue(gate.check_visual_baseline().blocked)

    def test_deleted_baseline_blocks(self) -> None:
        gate = self._gate([self._entry("D")])
        decision = gate.check_visual_baseline()
        self.assertTrue(decision.blocked)
        self.assertIn("Deleted Visual Baseline", decision.gate.failure_excerpt)

    def test_unsupported_status_blocks(self) -> None:
        gate = self._gate([self._entry("R")])
        self.assertTrue(gate.check_visual_baseline().blocked)

    def test_no_baseline_changes_allowed(self) -> None:
        gate = self._gate([])
        self.assertTrue(gate.check_visual_baseline().allowed)


if __name__ == "__main__":
    unittest.main()
