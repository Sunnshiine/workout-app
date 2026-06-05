from __future__ import annotations

import unittest
from dataclasses import FrozenInstanceError

from ralph.orchestrator.config import (
    DEFAULT_MAX_ITERATIONS,
    FAKE_ENGINE,
    ConfigError,
    RunConfig,
    parse_args,
)


class ParseArgsTests(unittest.TestCase):
    def test_defaults_use_fake_engine(self) -> None:
        config = parse_args([])
        self.assertIsInstance(config, RunConfig)
        self.assertEqual(config.engine, FAKE_ENGINE)
        self.assertEqual(config.max_iterations, DEFAULT_MAX_ITERATIONS)
        self.assertFalse(config.dry_run)
        self.assertFalse(config.uses_real_engine)

    def test_engine_choice_is_carried_through(self) -> None:
        self.assertEqual(parse_args(["--engine", "codex"]).engine, "codex")
        self.assertTrue(parse_args(["--engine", "codex"]).uses_real_engine)

    def test_dry_run_forces_fake_engine(self) -> None:
        config = parse_args(["--engine", "claude", "--dry-run"])
        self.assertTrue(config.dry_run)
        self.assertEqual(config.engine, FAKE_ENGINE)

    def test_publish_target_main_is_rejected(self) -> None:
        with self.assertRaises(ConfigError) as ctx:
            parse_args(["--publish-target", "main"])
        self.assertIn("pull requests", str(ctx.exception))

    def test_publish_target_branch_is_rejected(self) -> None:
        with self.assertRaises(ConfigError):
            parse_args(["--publish-target", "branch"])

    def test_publish_target_auto_is_rejected(self) -> None:
        with self.assertRaises(ConfigError):
            parse_args(["--publish-target", "auto"])

    def test_publish_target_pr_is_accepted(self) -> None:
        self.assertEqual(parse_args(["--publish-target", "pr"]).engine, FAKE_ENGINE)

    def test_max_iterations_must_be_positive(self) -> None:
        with self.assertRaises(ConfigError):
            parse_args(["--max-iterations", "0"])

    def test_implement_timeout_must_be_positive(self) -> None:
        with self.assertRaises(ConfigError):
            parse_args(["--implement-timeout-seconds", "0"])

    def test_repo_override(self) -> None:
        self.assertEqual(parse_args(["--repo", "owner/name"]).repo, "owner/name")

    def test_config_is_immutable(self) -> None:
        config = parse_args([])
        with self.assertRaises(FrozenInstanceError):
            config.engine = "codex"  # type: ignore[misc]


if __name__ == "__main__":
    unittest.main()
