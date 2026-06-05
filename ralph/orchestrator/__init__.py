"""Side-by-side Python orchestrator for Ralph.

This package owns the deterministic workflow state described in
``docs/specs/2026-06-05-ralph-python-pr-orchestrator.md``. Agent engines only
own individual phase turns; Python owns selection, routing, gates, authority
policies, and PR-only publication.

The shell runner ``ralph/ralph.sh`` remains the production path until the
replacement gate in issue #214 is approved.
"""

from __future__ import annotations

from .config import ConfigError, RunConfig, parse_args
from .engine import Engine, FakeEngine, PhaseRequest, build_engine
from .phase import PhaseResult, PhaseStatus

__all__ = [
    "ConfigError",
    "Engine",
    "FakeEngine",
    "PhaseRequest",
    "PhaseResult",
    "PhaseStatus",
    "RunConfig",
    "build_engine",
    "parse_args",
]
