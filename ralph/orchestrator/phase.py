"""Structured phase results.

Replaces the shell runner's promise-line parsing (``<promise phase=...>``) with
a typed result owned by the engine adapter. See the ``PhaseResult`` contract in
the spec.
"""

from __future__ import annotations

import enum
from dataclasses import dataclass
from pathlib import Path


class PhaseStatus(enum.Enum):
    """Outcome of running one phase prompt in one worktree."""

    COMPLETE = "complete"
    BLOCKED = "blocked"
    TIMEOUT = "timeout"
    FAILED = "failed"

    def __str__(self) -> str:
        return self.value


@dataclass(frozen=True)
class PhaseResult:
    """Immutable result of a single agent phase turn."""

    phase: str
    status: PhaseStatus
    final_response: str = ""
    log_path: Path | None = None
    started_at: float | None = None
    finished_at: float | None = None
    blocked_reason: str | None = None

    @property
    def is_complete(self) -> bool:
        return self.status is PhaseStatus.COMPLETE

    @property
    def duration_seconds(self) -> float | None:
        if self.started_at is None or self.finished_at is None:
            return None
        return self.finished_at - self.started_at
