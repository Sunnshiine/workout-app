from __future__ import annotations

import contextlib
import io
import unittest
from unittest.mock import patch

from ralph.orchestrator.cli import format_config_summary, format_run_summary, main
from ralph.orchestrator.config import parse_args
from ralph.orchestrator.loop import RunSummary


class CliMainTests(unittest.TestCase):
    def test_main_runs_normal_loop(self) -> None:
        out = io.StringIO()
        summary = RunSummary(
            iterations_started=1,
            issues_selected=(42,),
            issues_completed=(42,),
            issues_blocked=(),
            stopped_reason="max-iterations reached",
        )
        with (
            patch("ralph.orchestrator.cli.build_engine", return_value=object()),
            patch("ralph.orchestrator.cli.GhCliClient", return_value=object()),
            patch("ralph.orchestrator.cli.RalphLoop") as loop_class,
            contextlib.redirect_stdout(out),
        ):
            loop_class.return_value.run.return_value = summary
            code = main([])
        self.assertEqual(code, 0)
        self.assertIn("PR-only", out.getvalue())
        self.assertIn("Ralph run summary", out.getvalue())
        loop_class.return_value.run.assert_called_once_with()

    def test_help_prints_usage_and_exits_zero(self) -> None:
        out = io.StringIO()
        with contextlib.redirect_stdout(out), self.assertRaises(SystemExit) as ctx:
            main(["--help"])
        self.assertEqual(ctx.exception.code, 0)

    def test_removed_publish_target_returns_two_with_clear_error(self) -> None:
        err = io.StringIO()
        with contextlib.redirect_stderr(err):
            code = main(["--publish-target", "main"])
        self.assertEqual(code, 2)
        self.assertIn("pull requests", err.getvalue())

    def test_dry_run_announces_no_side_effects(self) -> None:
        out = io.StringIO()
        with contextlib.redirect_stdout(out):
            code = main(["--dry-run"])
        self.assertEqual(code, 0)
        self.assertIn("no GitHub", out.getvalue())

    def test_live_github_dry_run_is_shown_in_summary(self) -> None:
        summary = format_config_summary(parse_args(["--live-github-dry-run", "213"]))
        self.assertIn("live-github-dry-run", summary)
        self.assertIn("213", summary)

    def test_simulator_id_is_shown_in_summary(self) -> None:
        summary = format_config_summary(parse_args(["--simulator-id", "ABC-123"]))

        self.assertIn("simulator-id", summary)
        self.assertIn("ABC-123", summary)

    def test_loop_error_returns_one(self) -> None:
        from ralph.orchestrator.loop import RalphLoopError

        err = io.StringIO()
        with (
            patch("ralph.orchestrator.cli.build_engine", return_value=object()),
            patch("ralph.orchestrator.cli.GhCliClient", return_value=object()),
            patch("ralph.orchestrator.cli.RalphLoop") as loop_class,
            contextlib.redirect_stderr(err),
        ):
            loop_class.return_value.run.side_effect = RalphLoopError("boom")
            code = main([])
        self.assertEqual(code, 1)
        self.assertIn("boom", err.getvalue())


class FormatSummaryTests(unittest.TestCase):
    def test_summary_describes_engine_and_pr_only(self) -> None:
        summary = format_config_summary(parse_args([]))
        self.assertIn("engine", summary)
        self.assertIn("pr", summary)

    def test_run_summary_lists_issue_numbers(self) -> None:
        summary = format_run_summary(
            RunSummary(
                iterations_started=2,
                issues_selected=(10, 11),
                issues_completed=(10,),
                issues_blocked=(11,),
                stopped_reason="no eligible ready-for-agent issues",
            )
        )
        self.assertIn("#10, #11", summary)
        self.assertIn("no eligible", summary)


if __name__ == "__main__":
    unittest.main()
