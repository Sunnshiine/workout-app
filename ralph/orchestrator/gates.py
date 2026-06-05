"""Deterministic gate execution and structured results.

``GateRunner`` runs the documented app gates (the same commands ``run_full_gate``
drives in ``ralph/ralph.sh``) through an injectable command runner and returns a
``GateResult`` per gate. Tests inject a fake runner; nothing here shells out to a
real ``swift``, ``xcodebuild``, ``xcodegen``, or ``swiftlint``.

``ui_owned`` marks gates a UI-owned repair cycle owns when they fail: UI
integration tests, UI screenshot artifact/review checks, Visual Regression
failures, and Visual Baseline authority failures. ``ui_owned`` gate names are
shared so the authority and artifact layers classify their own ``GateResult``s
consistently (see :func:`is_ui_owned_gate`).
"""

from __future__ import annotations

from collections.abc import Callable, Sequence
from dataclasses import dataclass
from pathlib import Path

# Maximum characters of captured failure output kept on a GateResult so blocked
# reports stay bounded; the full log is referenced by ``log_path`` instead.
FAILURE_EXCERPT_LIMIT = 2000

GATE_SWIFT_TEST = "swift-test"
GATE_XCODEGEN = "xcodegen-generate"
GATE_UNIT_COMPONENT = "xcode-unit-component-tests"
GATE_VISUAL_REGRESSION = "visual-regression-tests"
GATE_UI_INTEGRATION = "ui-integration-tests"
GATE_SWIFTLINT = "swiftlint"

# Authority/artifact gate names produced outside GateRunner but classified here.
GATE_UI_ARTIFACTS = "ui-screenshot-artifacts"
GATE_VISUAL_BASELINE_AUTHORITY = "visual-baseline-authority"

# Gates whose failures a UI-owned repair cycle owns.
_UI_OWNED_GATES = frozenset(
    {
        GATE_UI_INTEGRATION,
        GATE_UI_ARTIFACTS,
        GATE_VISUAL_REGRESSION,
        GATE_VISUAL_BASELINE_AUTHORITY,
    }
)


class GateStatus:
    """String statuses for a gate outcome (matches the spec vocabulary)."""

    PASSED = "passed"
    FAILED = "failed"
    SKIPPED = "skipped"


@dataclass(frozen=True)
class CommandResult:
    """Outcome of one gate command run through the seam."""

    exit_status: int
    output: str = ""


# A command runner takes argv and returns a ``CommandResult``. Real use wraps
# ``subprocess.run`` with output redirected to a log; tests inject a fake.
CommandRunner = Callable[[Sequence[str]], CommandResult]


@dataclass(frozen=True)
class GateResult:
    """Structured result of one gate."""

    name: str
    status: str
    command: tuple[str, ...]
    exit_status: int | None = None
    log_path: Path | None = None
    failure_excerpt: str | None = None
    ui_owned: bool = False

    @property
    def passed(self) -> bool:
        return self.status == GateStatus.PASSED


@dataclass(frozen=True)
class GateSpec:
    """One command-based gate: a stable name and the argv to run."""

    name: str
    command: tuple[str, ...]


def is_ui_owned_gate(name: str) -> bool:
    """True when a gate's failures belong to the UI-owned repair cycle."""

    return name in _UI_OWNED_GATES


def failure_excerpt(output: str, *, limit: int = FAILURE_EXCERPT_LIMIT) -> str | None:
    """Return a bounded tail of ``output`` for a failed gate, or None if empty.

    The tail (not the head) is kept because the actionable error usually sits at
    the end of a build/test log.
    """

    trimmed = output.strip()
    if not trimmed:
        return None
    if len(trimmed) <= limit:
        return trimmed
    return trimmed[-limit:]


class GateRunner:
    """Runs command-based gates through an injectable runner.

    ``log_path_for`` maps a gate name to the log path captured for that gate (so
    the result carries a reference to the full output); it is optional.
    """

    def __init__(
        self,
        runner: CommandRunner,
        *,
        log_path_for: Callable[[str], Path] | None = None,
    ) -> None:
        self._runner = runner
        self._log_path_for = log_path_for

    def run(self, spec: GateSpec) -> GateResult:
        """Run one gate ``spec`` and classify its result."""

        result = self._runner(spec.command)
        log_path = self._log_path_for(spec.name) if self._log_path_for else None
        ui_owned = is_ui_owned_gate(spec.name)
        if result.exit_status == 0:
            return GateResult(
                name=spec.name,
                status=GateStatus.PASSED,
                command=spec.command,
                exit_status=0,
                log_path=log_path,
                ui_owned=ui_owned,
            )
        return GateResult(
            name=spec.name,
            status=GateStatus.FAILED,
            command=spec.command,
            exit_status=result.exit_status,
            log_path=log_path,
            failure_excerpt=failure_excerpt(result.output),
            ui_owned=ui_owned,
        )

    def run_all(self, specs: Sequence[GateSpec]) -> list[GateResult]:
        """Run gates in order, stopping at (and including) the first failure.

        Gates not reached are reported as ``skipped`` so the full set is always
        represented, matching the shell's stop-on-first-failure behavior.
        """

        results: list[GateResult] = []
        failed = False
        for spec in specs:
            if failed:
                results.append(_skipped(spec))
                continue
            result = self.run(spec)
            results.append(result)
            if not result.passed:
                failed = True
        return results


def _skipped(spec: GateSpec) -> GateResult:
    return GateResult(
        name=spec.name,
        status=GateStatus.SKIPPED,
        command=spec.command,
        exit_status=None,
        ui_owned=is_ui_owned_gate(spec.name),
    )
