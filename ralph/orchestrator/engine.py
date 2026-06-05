"""Engine adapters.

An engine runs ONE phase prompt in ONE worktree and returns a structured
``PhaseResult``. Engines never select targets, decide lifecycle state, mutate
labels, create PRs, run gates, or decide whether code is safe to publish — the
Python orchestrator owns all of that.

This module ships the ``FakeEngine`` used by tests and the no-publish dry-run.
SDK and CLI adapters arrive in issue #212; ``build_engine`` raises a clear error
for them until then so the migration stays side-by-side.
"""

from __future__ import annotations

from abc import ABC, abstractmethod
from collections.abc import Mapping
from dataclasses import dataclass
from pathlib import Path

from .phase import PhaseResult, PhaseStatus

FAKE_ENGINE = "fake"


@dataclass(frozen=True)
class PhaseRequest:
    """Everything an engine needs to run one phase turn."""

    phase: str
    prompt: str
    workdir: Path
    issue_number: int
    timeout_seconds: int
    log_path: Path | None = None


class Engine(ABC):
    """Runs a single phase prompt and returns a structured result."""

    name: str

    @abstractmethod
    def run_phase(self, request: PhaseRequest) -> PhaseResult:
        """Run one phase turn for ``request`` and return its ``PhaseResult``."""


class FakeEngine(Engine):
    """Deterministic engine for tests and dry-runs.

    ``results_by_phase`` maps a phase name to either a ``PhaseStatus`` or a fully
    formed ``PhaseResult``. Phases without an explicit entry resolve to
    ``default_status``. Every call is recorded on ``calls`` for assertions.
    """

    name = FAKE_ENGINE

    def __init__(
        self,
        *,
        results_by_phase: Mapping[str, PhaseStatus | PhaseResult] | None = None,
        default_status: PhaseStatus = PhaseStatus.COMPLETE,
        final_response: str = "",
    ) -> None:
        self._results_by_phase: dict[str, PhaseStatus | PhaseResult] = dict(results_by_phase or {})
        self._default_status = default_status
        self._final_response = final_response
        self.calls: list[PhaseRequest] = []

    def run_phase(self, request: PhaseRequest) -> PhaseResult:
        self.calls.append(request)
        scripted = self._results_by_phase.get(request.phase)
        if isinstance(scripted, PhaseResult):
            return scripted
        status = scripted if isinstance(scripted, PhaseStatus) else self._default_status
        blocked_reason = None
        if status is not PhaseStatus.COMPLETE:
            blocked_reason = f"fake engine scripted {status} for {request.phase}"
        return PhaseResult(
            phase=request.phase,
            status=status,
            final_response=self._final_response,
            log_path=request.log_path,
            blocked_reason=blocked_reason,
        )


def build_engine(engine_name: str) -> Engine:
    """Resolve an engine name to a concrete adapter.

    Only the fake engine is available in the skeleton. SDK/CLI adapters arrive in
    issue #212; requesting one now fails clearly rather than silently degrading.
    """

    if engine_name == FAKE_ENGINE:
        return FakeEngine()
    raise NotImplementedError(
        f"engine {engine_name!r} is not available yet "
        f"(SDK/CLI adapters arrive in #212); "
        f"use the {FAKE_ENGINE!r} engine for dry-runs and tests"
    )
