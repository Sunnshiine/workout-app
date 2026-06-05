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

DEFAULT_MAX_ITERATIONS = 5
DEFAULT_SIM_DEVICE = "iPhone 17 Pro"
DEFAULT_IMPLEMENT_TIMEOUT_SECONDS = 2700
DEFAULT_LABEL = "ready-for-agent"
DEFAULT_HUMAN_LABEL = "ready-for-human"

PR_PUBLISH_TARGET = "pr"


class ConfigError(ValueError):
    """Raised when CLI arguments cannot form a valid run configuration."""


@dataclass(frozen=True)
class RunConfig:
    """Immutable, fully resolved configuration for one Ralph run."""

    engine: str = FAKE_ENGINE
    max_iterations: int = DEFAULT_MAX_ITERATIONS
    model: str | None = None
    sim_device: str = DEFAULT_SIM_DEVICE
    implement_timeout_seconds: int = DEFAULT_IMPLEMENT_TIMEOUT_SECONDS
    dry_run: bool = False
    select_only: bool = False
    label: str = DEFAULT_LABEL
    human_label: str = DEFAULT_HUMAN_LABEL
    repo: str | None = None

    @property
    def uses_real_engine(self) -> bool:
        return self.engine != FAKE_ENGINE


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
        default=PR_PUBLISH_TARGET,
        help="Publication target. Only 'pr' is valid; 'main'/'branch'/'auto' were removed.",
    )
    return parser


def _resolve(namespace: argparse.Namespace) -> RunConfig:
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

    # A dry-run must never reach a real agent, so it always uses the fake engine.
    engine = FAKE_ENGINE if namespace.dry_run else namespace.engine

    return RunConfig(
        engine=engine,
        max_iterations=namespace.max_iterations,
        model=namespace.model,
        sim_device=namespace.sim_device,
        implement_timeout_seconds=namespace.implement_timeout_seconds,
        dry_run=namespace.dry_run,
        select_only=namespace.select_only,
        repo=namespace.repo,
    )


def parse_args(argv: Sequence[str] | None = None) -> RunConfig:
    """Parse ``argv`` into a validated :class:`RunConfig`.

    Raises :class:`ConfigError` for semantically invalid combinations (such as a
    removed direct-main target). ``argparse`` itself handles ``--help`` and
    unknown flags by printing usage and exiting.
    """

    namespace = build_parser().parse_args(argv)
    return _resolve(namespace)
