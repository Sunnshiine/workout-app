from __future__ import annotations

import contextlib
import io
import unittest

from ralph.orchestrator.cli import format_config_summary, main
from ralph.orchestrator.config import parse_args


class CliMainTests(unittest.TestCase):
    def test_main_validates_config_and_returns_zero(self) -> None:
        out = io.StringIO()
        with contextlib.redirect_stdout(out):
            code = main([])
        self.assertEqual(code, 0)
        self.assertIn("PR-only", out.getvalue())

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
            main(["--dry-run"])
        self.assertIn("no GitHub", out.getvalue())

    def test_live_github_dry_run_is_shown_in_summary(self) -> None:
        summary = format_config_summary(parse_args(["--live-github-dry-run", "213"]))
        self.assertIn("live-github-dry-run", summary)
        self.assertIn("213", summary)


class FormatSummaryTests(unittest.TestCase):
    def test_summary_describes_engine_and_pr_only(self) -> None:
        summary = format_config_summary(parse_args([]))
        self.assertIn("engine", summary)
        self.assertIn("pr", summary)


if __name__ == "__main__":
    unittest.main()
