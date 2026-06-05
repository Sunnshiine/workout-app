"""Parent-orchestrator authority gates.

These checks are mechanical and never depend on agent prompt compliance. They
read git diffs through an injectable seam so tests inject ``name-status`` output
directly and never run a real diff.

Two policies live here:

- **Visual Baseline (ADR 0007).** Added (``A``) baselines are allowed; modified
  (``M``) baselines require a saved review artifact whose final line is exactly
  the PASS marker; deleted (``D``) and any other status hard-block. This mirrors
  ``check_visual_baseline_authority`` in ``ralph/ralph.sh``.
- **UI integration test edit authority.** Any ``Tests/UI/**`` or UI-test target
  wiring change in the issue range requires ``ui_test_edits_authorized``; any
  ``Tests/UI/**`` change in the UI-verify phase range blocks unconditionally.
"""

from __future__ import annotations

from collections.abc import Callable, Sequence
from dataclasses import dataclass

from .contracts import IssueContract
from .gates import (
    GATE_UI_INTEGRATION,
    GATE_VISUAL_BASELINE_AUTHORITY,
    GateResult,
    GateStatus,
)

# Matches ralph/ralph.sh: VISUAL_BASELINE_DIR and the required review PASS line.
VISUAL_BASELINE_DIR = "Tests/Visual/__Snapshots__"
UI_REVIEW_PASS_LINE = "PASS: no blocking static visual findings."

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
# ``tip`` is None for a working-tree-vs-base diff (the Visual Baseline case).
DiffSeam = Callable[[str, str | None, Sequence[str]], tuple[NameStatusEntry, ...]]

# A review reader returns the saved baseline-diff review text for a baseline
# path, or None when no artifact exists. Mirrors the digest-addressed artifact
# lookup in ralph.sh; the exact path scheme stays out of the policy.
ReviewReader = Callable[[str], str | None]


@dataclass(frozen=True)
class AuthorityDecision:
    """Outcome of an authority check: allowed plus a structured gate result."""

    allowed: bool
    gate: GateResult

    @property
    def blocked(self) -> bool:
        return not self.allowed


class AuthorityGate:
    """Mechanical Visual Baseline and UI-test edit authority checks."""

    def __init__(self, diff: DiffSeam, *, review_reader: ReviewReader | None = None) -> None:
        self._diff = diff
        self._review_reader = review_reader

    def check_visual_baseline(self, base_ref: str = "HEAD") -> AuthorityDecision:
        """Enforce ADR 0007 Visual Baseline authority against ``base_ref``.

        Compares the working tree to ``base_ref`` (default ``HEAD``) for changes
        under ``VISUAL_BASELINE_DIR``. The first blocking change wins.
        """

        entries = self._diff(base_ref, None, [VISUAL_BASELINE_DIR])
        for entry in entries:
            reason = self._visual_baseline_block_reason(entry)
            if reason is not None:
                return _blocked(GATE_VISUAL_BASELINE_AUTHORITY, reason)
        return _allowed(GATE_VISUAL_BASELINE_AUTHORITY)

    def check_ui_test_authority(
        self,
        contract: IssueContract,
        *,
        issue_base: str,
        issue_tip: str,
        ui_phase_base: str,
        ui_phase_tip: str,
    ) -> AuthorityDecision:
        """Enforce UI integration test edit authority across both ranges.

        UI-verify-phase edits to ``Tests/UI/**`` block unconditionally; this is
        checked first because no authorization can override it. Otherwise an
        issue-range ``Tests/UI/**`` or UI-test target-wiring change requires the
        contract's ``ui_test_edits_authorized`` snapshot to be true.
        """

        ui_phase_ui_changes = self._ui_test_paths(ui_phase_base, ui_phase_tip)
        if ui_phase_ui_changes:
            return _blocked(
                GATE_UI_INTEGRATION,
                "UI verification phase edited UI integration tests, which is never "
                f"allowed: {_join(ui_phase_ui_changes)}.",
            )

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

    def _visual_baseline_block_reason(self, entry: NameStatusEntry) -> str | None:
        status = entry.status.strip().upper()
        if status == "A":
            return None
        if status == "M":
            return self._modified_baseline_block_reason(entry.path)
        if status == "D":
            return f"Deleted Visual Baseline is not allowed without human review: {entry.path}."
        return (
            f"Unsupported Visual Baseline change status {entry.status!r} for "
            f"{entry.path}; human review required."
        )

    def _modified_baseline_block_reason(self, path: str) -> str | None:
        review = self._review_reader(path) if self._review_reader else None
        if not review or not review.strip():
            return (
                "Modified Visual Baseline requires a saved baseline-diff review "
                f"artifact ending with PASS for: {path}."
            )
        if _last_line(review) != UI_REVIEW_PASS_LINE:
            return f"Modified Visual Baseline review did not end with PASS for: {path}."
        return None

    def _ui_test_paths(self, base: str, tip: str) -> tuple[str, ...]:
        entries = self._diff(base, tip, [UI_TEST_PATH_PREFIX])
        return tuple(e.path for e in entries if _under_ui_tests(e.path))

    def _wiring_paths(self, base: str, tip: str) -> tuple[str, ...]:
        entries = self._diff(base, tip, list(_PROJECT_WIRING_PATHS))
        return tuple(e.path for e in entries if e.path in _PROJECT_WIRING_PATHS)


def _under_ui_tests(path: str) -> bool:
    return path.startswith(UI_TEST_PATH_PREFIX)


def _last_line(text: str) -> str:
    lines = text.splitlines()
    return lines[-1].strip() if lines else ""


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
