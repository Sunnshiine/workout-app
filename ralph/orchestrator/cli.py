"""Command-line entrypoint.

The skeleton can validate configuration and describe the planned run without
touching GitHub, git worktrees, or real agent engines.
"""

from __future__ import annotations

import subprocess
import sys
from collections.abc import Sequence
from pathlib import Path

from .config import ConfigError, RunConfig, parse_args
from .engine import FakeEngine, build_engine
from .github import GhCliClient, GitHubClientError
from .live_dry_run import LiveDryRunError, format_result, run_live_github_dry_run
from .loop import RalphLoop, RalphLoopError, RunSummary


def format_config_summary(config: RunConfig) -> str:
    lines = [
        "Ralph (Python) — PR-only orchestrator",
        f"  engine:                 {config.engine}",
        f"  max-iterations:         {config.max_iterations}",
        f"  model:                  {config.model or '(engine default)'}",
        f"  reasoning-effort:       {config.reasoning_effort or '(Ralph Codex policy)'}",
        f"  sim-device:             {config.sim_device}",
        f"  simulator-id:           {config.simulator_id or '(by device name)'}",
        f"  simulator-pool:         {' '.join(config.simulator_pool) or '(none)'}",
        f"  implement-timeout (s):  {config.implement_timeout_seconds}",
        f"  dry-run:                {config.dry_run}",
        f"  live-github-dry-run:    {config.live_github_dry_run_issue or '(off)'}",
        f"  select-only:            {config.select_only}",
        f"  repo:                   {config.repo or '(inferred from git)'}",
        "  publish-target:         pr (direct-to-main removed)",
    ]
    return "\n".join(lines)


def format_run_summary(summary: RunSummary) -> str:
    return "\n".join(
        [
            "Ralph run summary",
            f"  iterations-started: {summary.iterations_started}",
            f"  selected:           {_numbers(summary.issues_selected)}",
            f"  completed:          {_numbers(summary.issues_completed)}",
            f"  blocked:            {_numbers(summary.issues_blocked)}",
            f"  stopped-reason:     {summary.stopped_reason}",
        ]
    )


def main(argv: Sequence[str] | None = None) -> int:
    try:
        config = parse_args(argv)
    except ConfigError as error:
        print(f"error: {error}", file=sys.stderr)
        return 2

    print(format_config_summary(config), flush=True)
    if config.live_github_dry_run_issue is not None:
        try:
            result = run_live_github_dry_run(
                issue_number=config.live_github_dry_run_issue,
                repo_root=Path.cwd(),
                client=GhCliClient(repo=config.repo),
                engine=FakeEngine(),
            )
        except (GitHubClientError, LiveDryRunError, subprocess.CalledProcessError) as error:
            print(f"live-github-dry-run failed: {error}", file=sys.stderr)
            return 1
        print()
        print(format_result(result))
        return 0
    if config.dry_run:
        print("\ndry-run: configuration valid; no GitHub, worktree, or agent action taken.")
        return 0

    try:
        summary = RalphLoop(
            config=config,
            repo_root=Path.cwd(),
            client=GhCliClient(repo=config.repo),
            engine=build_engine(
                config.engine,
                model=config.model,
                reasoning_effort=config.reasoning_effort,
            ),
        ).run()
    except (GitHubClientError, RalphLoopError, subprocess.CalledProcessError) as error:
        print(f"\nralph failed: {error}", file=sys.stderr)
        return 1
    print()
    print(format_run_summary(summary))
    return 0


def _numbers(numbers: Sequence[int]) -> str:
    return ", ".join(f"#{number}" for number in numbers) if numbers else "none"


if __name__ == "__main__":
    raise SystemExit(main())
