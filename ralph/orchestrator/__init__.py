"""Side-by-side Python orchestrator for Ralph.

This package owns the deterministic workflow state described in
``docs/specs/2026-06-05-ralph-python-pr-orchestrator.md``. Agent engines only
own individual phase turns; Python owns selection, routing, gates, authority
policies, and PR-only publication.

The shell runner ``ralph/ralph.sh`` remains the production path until the
replacement gate in issue #214 is approved.
"""

from __future__ import annotations

from .authority import (
    UI_REVIEW_PASS_LINE,
    VISUAL_BASELINE_DIR,
    AuthorityDecision,
    AuthorityGate,
    NameStatusEntry,
)
from .blocked import (
    MAX_EXCERPT_BYTES,
    MAX_EXCERPT_LINES,
    REDACTION_PLACEHOLDER,
    BlockedReport,
    BlockedReportWriter,
    BlockedRescuePlan,
    BlockedRescuePublisher,
    blocked_branch,
    blocked_commit_message,
    blocked_pr_title,
    cap_excerpt,
    redact_secrets,
)
from .config import ConfigError, RunConfig, parse_args
from .contracts import (
    IssueComment,
    IssueContract,
    capture_issue_contract,
    parse_prd_number,
    parse_ui_test_authorization,
)
from .engine import Engine, FakeEngine, PhaseRequest, build_engine
from .gates import (
    CommandResult,
    GateResult,
    GateRunner,
    GateSpec,
    GateStatus,
    is_ui_owned_gate,
)
from .github import (
    FakeGitHubClient,
    GhCliClient,
    GitHubClient,
    GitHubClientError,
)
from .phase import PhaseResult, PhaseStatus
from .publish import (
    LABEL_AGENT_BLOCKED,
    LABEL_AGENT_IMPLEMENTED,
    LABEL_AGENT_READY_FOR_REVIEW,
    LABEL_READY_FOR_AGENT,
    LABEL_READY_FOR_HUMAN,
    GitOutcome,
    IssuePublisher,
    PublishError,
    PullRequestPublisher,
    integration_commit_message,
)
from .repair import (
    DEFAULT_PHASE_TIMEOUT_SECONDS,
    PHASE_REPAIR_UI_GATE,
    PHASE_SWIFT_REVIEW_AFTER_REPAIR,
    RepairCoordinator,
    RepairError,
    RepairOutcome,
    render_repair_brief,
    repair_brief_relpath,
    requires_swift_review,
)
from .targets import PrTarget, TargetResolutionError, TargetResolver, branch_for_contract
from .worktree import (
    GitResult,
    Worktree,
    WorktreeError,
    WorktreeManager,
    default_git_runner,
)

__all__ = [
    "LABEL_AGENT_BLOCKED",
    "LABEL_AGENT_IMPLEMENTED",
    "LABEL_AGENT_READY_FOR_REVIEW",
    "LABEL_READY_FOR_AGENT",
    "LABEL_READY_FOR_HUMAN",
    "MAX_EXCERPT_BYTES",
    "MAX_EXCERPT_LINES",
    "REDACTION_PLACEHOLDER",
    "UI_REVIEW_PASS_LINE",
    "VISUAL_BASELINE_DIR",
    "AuthorityDecision",
    "AuthorityGate",
    "DEFAULT_PHASE_TIMEOUT_SECONDS",
    "PHASE_REPAIR_UI_GATE",
    "PHASE_SWIFT_REVIEW_AFTER_REPAIR",
    "BlockedReport",
    "BlockedReportWriter",
    "BlockedRescuePlan",
    "BlockedRescuePublisher",
    "CommandResult",
    "ConfigError",
    "Engine",
    "FakeEngine",
    "FakeGitHubClient",
    "GateResult",
    "GateRunner",
    "GateSpec",
    "GateStatus",
    "GhCliClient",
    "GitHubClient",
    "GitHubClientError",
    "GitOutcome",
    "GitResult",
    "IssueComment",
    "IssueContract",
    "IssuePublisher",
    "NameStatusEntry",
    "PhaseRequest",
    "PhaseResult",
    "PhaseStatus",
    "PrTarget",
    "PublishError",
    "PullRequestPublisher",
    "RepairCoordinator",
    "RepairError",
    "RepairOutcome",
    "RunConfig",
    "TargetResolutionError",
    "TargetResolver",
    "Worktree",
    "WorktreeError",
    "WorktreeManager",
    "blocked_branch",
    "blocked_commit_message",
    "blocked_pr_title",
    "branch_for_contract",
    "build_engine",
    "cap_excerpt",
    "capture_issue_contract",
    "default_git_runner",
    "integration_commit_message",
    "is_ui_owned_gate",
    "parse_args",
    "parse_prd_number",
    "parse_ui_test_authorization",
    "redact_secrets",
    "render_repair_brief",
    "repair_brief_relpath",
    "requires_swift_review",
]
