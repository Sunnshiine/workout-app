from __future__ import annotations

import unittest

from ralph.orchestrator.authority import (
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
        )
        self.assertTrue(decision.blocked)
        self.assertTrue(decision.gate.ui_owned)

    def test_authorized_issue_range_ui_test_edit_passes(self) -> None:
        gate = self._gate({("base", "tip"): [NameStatusEntry("M", "Tests/UI/LoginUITests.swift")]})
        decision = gate.check_ui_test_authority(
            _contract(authorized=True),
            issue_base="base",
            issue_tip="tip",
        )
        self.assertTrue(decision.allowed)

    def test_unauthorized_project_wiring_change_blocks(self) -> None:
        gate = self._gate({("base", "tip"): [NameStatusEntry("M", "project.yml")]})
        decision = gate.check_ui_test_authority(
            _contract(authorized=False),
            issue_base="base",
            issue_tip="tip",
        )
        self.assertTrue(decision.blocked)

    def test_no_ui_changes_passes(self) -> None:
        gate = self._gate({})
        decision = gate.check_ui_test_authority(
            _contract(authorized=False),
            issue_base="base",
            issue_tip="tip",
        )
        self.assertTrue(decision.allowed)


if __name__ == "__main__":
    unittest.main()
