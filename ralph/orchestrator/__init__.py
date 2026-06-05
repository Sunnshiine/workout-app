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
from .contracts import (
    IssueComment,
    IssueContract,
    capture_issue_contract,
    parse_prd_number,
    parse_ui_test_authorization,
)
from .engine import Engine, FakeEngine, PhaseRequest, build_engine
from .github import (
    FakeGitHubClient,
    GhCliClient,
    GitHubClient,
    GitHubClientError,
)
from .phase import PhaseResult, PhaseStatus
from .targets import PrTarget, TargetResolutionError, TargetResolver, branch_for_contract

__all__ = [
    "ConfigError",
    "Engine",
    "FakeEngine",
    "FakeGitHubClient",
    "GhCliClient",
    "GitHubClient",
    "GitHubClientError",
    "IssueComment",
    "IssueContract",
    "PhaseRequest",
    "PhaseResult",
    "PhaseStatus",
    "PrTarget",
    "RunConfig",
    "TargetResolutionError",
    "TargetResolver",
    "branch_for_contract",
    "build_engine",
    "capture_issue_contract",
    "parse_args",
    "parse_prd_number",
    "parse_ui_test_authorization",
]
