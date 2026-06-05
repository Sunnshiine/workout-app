"""Command-line entrypoint.

The skeleton can validate configuration and describe the planned run without
touching GitHub, git worktrees, or real agent engines.
"""

from __future__ import annotations

import sys
from collections.abc import Sequence

from .config import ConfigError, RunConfig, parse_args


def format_config_summary(config: RunConfig) -> str:
    lines = [
        "Ralph (Python) — PR-only orchestrator",
        f"  engine:                 {config.engine}",
        f"  max-iterations:         {config.max_iterations}",
        f"  model:                  {config.model or '(engine default)'}",
        f"  sim-device:             {config.sim_device}",
        f"  implement-timeout (s):  {config.implement_timeout_seconds}",
        f"  dry-run:                {config.dry_run}",
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

    print(format_config_summary(config))
    if config.dry_run:
        print("\ndry-run: configuration valid; no GitHub, worktree, or agent action taken.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
