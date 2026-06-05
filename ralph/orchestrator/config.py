"""Run configuration and CLI parsing.

The Python runner is PR-only: it has no direct-to-main publish path. The legacy
``--publish-target main`` option is invalid and fails clearly here.
"""

from __future__ import annotations

import argparse
from collections.abc import Sequence
from dataclasses import dataclass

FAKE_ENGINE = "fake"
ENGINE_CHOICES = ("fake", "claude", "codex", "claude-cli", "codex-cli")
REASONING_EFFORT_CHOICES = ("low", "medium", "high", "xhigh")

DEFAULT_MAX_ITERATIONS = 5
DEFAULT_SIM_DEVICE = "iPhone 17 Pro"
DEFAULT_IMPLEMENT_TIMEOUT_SECONDS = 2700
DEFAULT_LABEL = "ready-for-agent"
DEFAULT_HUMAN_LABEL = "ready-for-human"
DEFAULT_CODEX_MODEL = "gpt-5.5"
DEFAULT_CODEX_REASONING_EFFORT = "medium"
CODEX_HIGH_REASONING_PHASES = frozenset(
    {"swift-review", "repair-ui-gate", "swift-review-after-repair"}
)

PR_PUBLISH_TARGET = "pr"


class ConfigError(ValueError):
    """Raised when CLI arguments cannot form a valid run configuration."""


@dataclass(frozen=True)
class RunConfig:
    """Immutable, fully resolved configuration for one Ralph run."""

    engine: str = FAKE_ENGINE
    max_iterations: int = DEFAULT_MAX_ITERATIONS
    model: str | None = None
    reasoning_effort: str | None = None
    sim_device: str = DEFAULT_SIM_DEVICE
    implement_timeout_seconds: int = DEFAULT_IMPLEMENT_TIMEOUT_SECONDS
    dry_run: bool = False
    select_only: bool = False
    label: str = DEFAULT_LABEL
    human_label: str = DEFAULT_HUMAN_LABEL
    repo: str | None = None
    live_github_dry_run_issue: int | None = None

    @property
    def uses_real_engine(self) -> bool:
        return self.engine != FAKE_ENGINE


def resolve_codex_model(model: str | None) -> str:
    """Return the model Ralph should pass to Codex for deterministic runs."""

    return model or DEFAULT_CODEX_MODEL


def resolve_codex_reasoning_effort(phase: str, override: str | None) -> str:
    """Return the Codex reasoning effort for ``phase`` under Ralph's policy."""

    if override is not None:
        return override
    if phase in CODEX_HIGH_REASONING_PHASES:
        return "high"
    return DEFAULT_CODEX_REASONING_EFFORT


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        prog="ralph-py",
        description=(
            "Side-by-side Python Ralph orchestrator. Publishes autonomous work "
            "only through pull requests; never directly to main."
        ),
    )
    parser.add_argument(
        "--engine",
        choices=ENGINE_CHOICES,
        default=FAKE_ENGINE,
        help="Engine adapter that runs agent turns (default: fake).",
    )
    parser.add_argument(
        "--max-iterations",
        "--max-iter",
        type=int,
        default=DEFAULT_MAX_ITERATIONS,
        dest="max_iterations",
        help="Maximum issues to process this run.",
    )
    parser.add_argument("--model", default=None, help="Model alias passed to the engine.")
    parser.add_argument(
        "--reasoning-effort",
        choices=REASONING_EFFORT_CHOICES,
        default=None,
        dest="reasoning_effort",
        help=(
            "Optional whole-run reasoning effort override. Codex defaults to "
            "medium, with review/repair phases using high."
        ),
    )
    parser.add_argument(
        "--device",
        dest="sim_device",
        default=DEFAULT_SIM_DEVICE,
        help="Simulator device for Xcode gates.",
    )
    parser.add_argument(
        "--implement-timeout-seconds",
        type=int,
        default=DEFAULT_IMPLEMENT_TIMEOUT_SECONDS,
        dest="implement_timeout_seconds",
        help="Per-phase agent timeout in seconds.",
    )
    parser.add_argument(
        "--dry-run",
        action="store_true",
        help="No-publish dry-run; forces the fake engine and touches no real agent.",
    )
    parser.add_argument(
        "--live-github-dry-run",
        type=int,
        metavar="ISSUE",
        dest="live_github_dry_run_issue",
        help=(
            "Run the controlled GitHub dry-run against ISSUE. This forces the "
            "fake engine and may mutate the authorized dry-run issue/PR."
        ),
    )
    parser.add_argument(
        "--select-only",
        action="store_true",
        help="Resolve selection/targets without creating worktrees or running agents.",
    )
    parser.add_argument(
        "--repo",
        default=None,
        help="owner/name override; inferred from git when omitted.",
    )
    parser.add_argument(
        "--publish-target",
        "--ship-target",
        default=PR_PUBLISH_TARGET,
        dest="publish_target",
        help="Publication target. Only 'pr' is valid; 'main'/'branch'/'auto' were removed.",
    )
    parser.add_argument(
        "--no-push",
        action="store_true",
        dest="removed_no_push",
        help=argparse.SUPPRESS,
    )
    parser.add_argument(
        "--target-branch",
        "--pr-branch",
        dest="removed_target_branch",
        help=argparse.SUPPRESS,
    )
    parser.add_argument(
        "--target-pr",
        dest="removed_target_pr",
        help=argparse.SUPPRESS,
    )
    return parser


def _resolve(namespace: argparse.Namespace) -> RunConfig:
    if namespace.removed_no_push:
        raise ConfigError(
            "--no-push is not supported by the Python runner. It publishes only "
            "through pull requests; use --dry-run for a no-side-effect config check."
        )
    if namespace.removed_target_branch or namespace.removed_target_pr:
        raise ConfigError(
            "--target-branch/--target-pr are not supported by the Python runner. "
            "PR branches are deterministic: ralph/issue-<n> or ralph/prd-<n>."
        )

    publish_target = namespace.publish_target
    if publish_target != PR_PUBLISH_TARGET:
        raise ConfigError(
            f"--publish-target {publish_target!r} is not supported: the Python "
            "runner publishes only through pull requests. Direct-to-main and "
            "direct-branch publishing were removed; omit --publish-target."
        )
    if namespace.max_iterations < 1:
        raise ConfigError("--max-iterations must be at least 1.")
    if namespace.implement_timeout_seconds < 1:
        raise ConfigError("--implement-timeout-seconds must be at least 1.")
    if namespace.live_github_dry_run_issue is not None and namespace.dry_run:
        raise ConfigError(
            "--live-github-dry-run already performs the controlled live dry-run; "
            "do not combine it with the no-side-effect --dry-run config check."
        )
    if namespace.live_github_dry_run_issue is not None and namespace.live_github_dry_run_issue < 1:
        raise ConfigError("--live-github-dry-run ISSUE must be a positive issue number.")

    # Dry-run modes must never reach a real agent, so they always use the fake engine.
    is_dry_run = namespace.dry_run or namespace.live_github_dry_run_issue
    engine = FAKE_ENGINE if is_dry_run else namespace.engine

    return RunConfig(
        engine=engine,
        max_iterations=namespace.max_iterations,
        model=namespace.model,
        reasoning_effort=namespace.reasoning_effort,
        sim_device=namespace.sim_device,
        implement_timeout_seconds=namespace.implement_timeout_seconds,
        dry_run=namespace.dry_run,
        select_only=namespace.select_only,
        repo=namespace.repo,
        live_github_dry_run_issue=namespace.live_github_dry_run_issue,
    )


def parse_args(argv: Sequence[str] | None = None) -> RunConfig:
    """Parse ``argv`` into a validated :class:`RunConfig`.

    Raises :class:`ConfigError` for semantically invalid combinations (such as a
    removed direct-main target). ``argparse`` itself handles ``--help`` and
    unknown flags by printing usage and exiting.
    """

    namespace = build_parser().parse_args(argv)
    return _resolve(namespace)
