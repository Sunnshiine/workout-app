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
from .engine import FakeEngine
from .github import GhCliClient, GitHubClientError
from .live_dry_run import LiveDryRunError, format_result, run_live_github_dry_run


def format_config_summary(config: RunConfig) -> str:
    lines = [
        "Ralph (Python) — PR-only orchestrator",
        f"  engine:                 {config.engine}",
        f"  max-iterations:         {config.max_iterations}",
        f"  model:                  {config.model or '(engine default)'}",
        f"  sim-device:             {config.sim_device}",
        f"  implement-timeout (s):  {config.implement_timeout_seconds}",
        f"  dry-run:                {config.dry_run}",
        f"  live-github-dry-run:    {config.live_github_dry_run_issue or '(off)'}",
        f"  select-only:            {config.select_only}",
        f"  repo:                   {config.repo or '(inferred from git)'}",
        "  publish-target:         pr (direct-to-main removed)",
    ]
    return "\n".join(lines)


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

    print(
        "\nerror: the normal Ralph issue-processing loop is not wired in this "
        "Python entrypoint yet. Use --dry-run for a no-side-effect config check "
        "or --live-github-dry-run ISSUE for the controlled GitHub wiring proof.",
        file=sys.stderr,
    )
    return 1


if __name__ == "__main__":
    raise SystemExit(main())
