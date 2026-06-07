"""Parent-orchestrator authority gates.

These checks are mechanical and never depend on agent prompt compliance. They
read git diffs through an injectable seam so tests inject ``name-status`` output
directly and never run a real diff.

Only one policy lives here: any ``Tests/UI/**`` or UI-test target wiring change
in the issue range requires ``ui_test_edits_authorized``. Visual Baselines are
normal test artifacts and are governed by the Visual Regression test gate, not a
separate authority check.
"""

from __future__ import annotations

from collections.abc import Callable, Sequence
from dataclasses import dataclass

from .contracts import IssueContract
from .gates import (
    GATE_UI_INTEGRATION,
    GateResult,
    GateStatus,
)

# UI integration test edit authority pathspecs (match production_swift_changed
# and the UI-test target-wiring files in ralph/ralph.sh).
UI_TEST_PATH_PREFIX = "Tests/UI/"
_PROJECT_WIRING_PATHS = (
    "project.yml",
    "WorkoutTracker.xcodeproj/project.pbxproj",
)


@dataclass(frozen=True)
class NameStatusEntry:
    """One ``git diff --name-status`` row: a status letter and a path."""

    status: str
    path: str


# A diff seam returns the name-status entries for a range against pathspecs.
DiffSeam = Callable[[str, str | None, Sequence[str]], tuple[NameStatusEntry, ...]]


@dataclass(frozen=True)
class AuthorityDecision:
    """Outcome of an authority check: allowed plus a structured gate result."""

    allowed: bool
    gate: GateResult

    @property
    def blocked(self) -> bool:
        return not self.allowed


class AuthorityGate:
    """Mechanical UI integration test edit authority checks."""

    def __init__(self, diff: DiffSeam) -> None:
        self._diff = diff

    def check_ui_test_authority(
        self,
        contract: IssueContract,
        *,
        issue_base: str,
        issue_tip: str,
    ) -> AuthorityDecision:
        """Enforce UI integration test edit authority over the full issue diff.

        An issue-range ``Tests/UI/**`` or UI-test target-wiring change requires
        the contract's ``ui_test_edits_authorized`` snapshot to be true.
        """

        issue_ui_changes = self._ui_test_paths(issue_base, issue_tip)
        wiring_changes = self._wiring_paths(issue_base, issue_tip)
        requires_authorization = issue_ui_changes or wiring_changes
        if requires_authorization and not contract.ui_test_edits_authorized:
            return _blocked(
                GATE_UI_INTEGRATION,
                "UI integration test edits are not authorized for this issue but "
                f"the implementation changed: {_join(issue_ui_changes + wiring_changes)}.",
            )
        return _allowed(GATE_UI_INTEGRATION)

    def _ui_test_paths(self, base: str, tip: str) -> tuple[str, ...]:
        entries = self._diff(base, tip, [UI_TEST_PATH_PREFIX])
        return tuple(e.path for e in entries if _under_ui_tests(e.path))

    def _wiring_paths(self, base: str, tip: str) -> tuple[str, ...]:
        entries = self._diff(base, tip, list(_PROJECT_WIRING_PATHS))
        return tuple(e.path for e in entries if e.path in _PROJECT_WIRING_PATHS)


def _under_ui_tests(path: str) -> bool:
    return path.startswith(UI_TEST_PATH_PREFIX)


def _join(paths: Sequence[str]) -> str:
    return ", ".join(paths)


def _allowed(name: str) -> AuthorityDecision:
    return AuthorityDecision(
        allowed=True,
        gate=GateResult(
            name=name,
            status=GateStatus.PASSED,
            command=(),
            ui_owned=True,
        ),
    )


def _blocked(name: str, reason: str) -> AuthorityDecision:
    return AuthorityDecision(
        allowed=False,
        gate=GateResult(
            name=name,
            status=GateStatus.FAILED,
            command=(),
            failure_excerpt=reason,
            ui_owned=True,
        ),
    )
