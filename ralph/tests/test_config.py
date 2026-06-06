from __future__ import annotations

import unittest
from dataclasses import FrozenInstanceError

from ralph.orchestrator.config import (
    DEFAULT_CODEX_MODEL,
    DEFAULT_CODEX_REASONING_EFFORT,
    DEFAULT_MAX_ITERATIONS,
    FAKE_ENGINE,
    ConfigError,
    RunConfig,
    parse_args,
    resolve_codex_model,
    resolve_codex_reasoning_effort,
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

    def test_defaults_leave_cli_model_and_reasoning_unset(self) -> None:
        config = parse_args(["--engine", "codex"])
        self.assertIsNone(config.model)
        self.assertIsNone(config.reasoning_effort)

    def test_codex_policy_resolves_default_model_and_phase_reasoning(self) -> None:
        self.assertEqual(resolve_codex_model(None), DEFAULT_CODEX_MODEL)
        self.assertEqual(
            resolve_codex_reasoning_effort("implement-tdd", None),
            DEFAULT_CODEX_REASONING_EFFORT,
        )
        self.assertEqual(resolve_codex_reasoning_effort("review", None), "high")
        self.assertEqual(resolve_codex_reasoning_effort("repair-ui-gate", None), "high")
        self.assertEqual(
            resolve_codex_reasoning_effort("review-after-repair", None), "high"
        )

    def test_reasoning_effort_override_wins_for_every_phase(self) -> None:
        config = parse_args(["--engine", "codex", "--reasoning-effort", "low"])
        self.assertEqual(config.reasoning_effort, "low")
        self.assertEqual(resolve_codex_reasoning_effort("review", "low"), "low")
        self.assertEqual(resolve_codex_reasoning_effort("implement-tdd", "low"), "low")

    def test_invalid_reasoning_effort_is_rejected(self) -> None:
        with self.assertRaises(SystemExit):
            parse_args(["--reasoning-effort", "turbo"])

    def test_unsupported_sdk_reasoning_efforts_are_rejected(self) -> None:
        for effort in ("none", "minimal"):
            with self.subTest(effort=effort), self.assertRaises(SystemExit):
                parse_args(["--reasoning-effort", effort])

    def test_dry_run_forces_fake_engine(self) -> None:
        config = parse_args(["--engine", "claude", "--dry-run"])
        self.assertTrue(config.dry_run)
        self.assertEqual(config.engine, FAKE_ENGINE)

    def test_live_github_dry_run_forces_fake_engine(self) -> None:
        config = parse_args(["--engine", "codex", "--live-github-dry-run", "213"])
        self.assertEqual(config.engine, FAKE_ENGINE)
        self.assertEqual(config.live_github_dry_run_issue, 213)
        self.assertFalse(config.uses_real_engine)

    def test_live_github_dry_run_rejects_no_side_effect_dry_run(self) -> None:
        with self.assertRaises(ConfigError):
            parse_args(["--dry-run", "--live-github-dry-run", "213"])

    def test_live_github_dry_run_issue_must_be_positive(self) -> None:
        with self.assertRaises(ConfigError):
            parse_args(["--live-github-dry-run", "0"])

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

    def test_legacy_ship_target_main_is_rejected(self) -> None:
        with self.assertRaises(ConfigError) as ctx:
            parse_args(["--ship-target", "main"])
        self.assertIn("pull requests", str(ctx.exception))

    def test_legacy_no_push_is_rejected_with_clear_message(self) -> None:
        with self.assertRaises(ConfigError) as ctx:
            parse_args(["--no-push"])
        self.assertIn("--dry-run", str(ctx.exception))

    def test_legacy_target_branch_is_rejected_with_clear_message(self) -> None:
        with self.assertRaises(ConfigError) as ctx:
            parse_args(["--target-branch", "some-branch"])
        self.assertIn("deterministic", str(ctx.exception))

    def test_legacy_target_pr_is_rejected_with_clear_message(self) -> None:
        with self.assertRaises(ConfigError) as ctx:
            parse_args(["--target-pr", "177"])
        self.assertIn("deterministic", str(ctx.exception))

    def test_max_iterations_must_be_positive(self) -> None:
        with self.assertRaises(ConfigError):
            parse_args(["--max-iterations", "0"])

    def test_implement_timeout_must_be_positive(self) -> None:
        with self.assertRaises(ConfigError):
            parse_args(["--implement-timeout-seconds", "0"])

    def test_repo_override(self) -> None:
        self.assertEqual(parse_args(["--repo", "owner/name"]).repo, "owner/name")

    def test_simulator_id_override(self) -> None:
        config = parse_args(["--simulator-id", "ABC-123"])

        self.assertEqual(config.simulator_id, "ABC-123")

    def test_simulator_id_must_not_be_blank(self) -> None:
        with self.assertRaises(ConfigError):
            parse_args(["--simulator-id", ""])

    def test_config_is_immutable(self) -> None:
        config = parse_args([])
        with self.assertRaises(FrozenInstanceError):
            config.engine = "codex"  # type: ignore[misc]


if __name__ == "__main__":
    unittest.main()
