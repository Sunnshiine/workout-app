"""Focused Ralph prompt contract tests (#266).

Proves the six spec contract points from the programmatic issue-context spec,
without broad prompt snapshot tests:

1. The XML <ralph_phase> wrapper shape (section ordering and required children).
2. Required <forbidden_actions> present and non-empty in rendered phase prompts.
3. Comments are rendered as context-only and split out of issue-contract.md.
4. (removed: ui-verify phase no longer exists — see #287)
5. No broad "do not run UI tests" wording in implement-tdd prompt file.
6. No gh issue view contract-discovery instruction outside diagnose.md.
"""

from __future__ import annotations

import subprocess
import tempfile
import unittest
from pathlib import Path

from ralph.orchestrator.config import RunConfig
from ralph.orchestrator.contracts import IssueComment, IssueContract
from ralph.orchestrator.gates import CommandResult, GateRunner
from ralph.orchestrator.github import FakeGitHubClient
from ralph.orchestrator.loop import (
    PHASE_DIAGNOSE,
    PHASE_IMPLEMENT,
    PHASE_REVIEW,
    RalphLoop,
    _forbidden_actions_for_phase,
)
from ralph.orchestrator.phase import PhaseResult, PhaseStatus
from ralph.orchestrator.prompt_context import (
    ISSUE_COMMENTS_FILE,
    ISSUE_CONTRACT_FILE,
    render_issue_comments,
    render_issue_contract,
)
from ralph.orchestrator.publish import LABEL_READY_FOR_AGENT, GitOutcome
from ralph.orchestrator.worktree import WorktreeManager, default_git_runner

_PROMPTS = Path(__file__).resolve().parents[1] / "prompts"
_IMPLEMENT_MD = _PROMPTS / "implement.md"
_REVIEW_MD = _PROMPTS / "review.md"
_DIAGNOSE_MD = _PROMPTS / "diagnose.md"


# ---------------------------------------------------------------------------
# Helpers for integration-style envelope tests
# ---------------------------------------------------------------------------


def _git(repo: Path, *args: str) -> None:
    subprocess.run(["git", "-C", str(repo), *args], check=True, capture_output=True, text=True)


def _init_repo(repo: Path) -> None:
    _git(repo, "init", "-b", "main")
    _git(repo, "config", "user.email", "ralph@example.com")
    _git(repo, "config", "user.name", "Ralph")
    (repo / "README.md").write_text("seed\n", encoding="utf-8")
    prompts = repo / "ralph" / "prompts"
    prompts.mkdir(parents=True)
    for name in ("implement.md", "review.md", "diagnose.md"):
        (prompts / name).write_text(f"{name} body\n", encoding="utf-8")
    _git(repo, "add", "README.md", "ralph/prompts")
    _git(repo, "commit", "-m", "seed")


def _issue(number: int) -> dict:
    return {
        "number": number,
        "title": "Contract test",
        "body": "Do the thing.",
        "labels": [{"name": LABEL_READY_FOR_AGENT}],
        "comments": [],
    }


class _CapturingEngine:
    def __init__(self) -> None:
        self.prompts: list[str] = []

    def run_phase(self, request) -> PhaseResult:
        self.prompts.append(request.prompt)
        return PhaseResult(
            phase=request.phase,
            status=PhaseStatus.COMPLETE,
            final_response=f'<promise phase="{request.phase}">COMPLETE</promise>',
            blocked_reason=None,
        )


class _OriginMain:
    def poll(self) -> None:
        pass

    def base_ref_for(self, _target) -> str:
        return "main"


class _RecordingPublishRunner:
    def __init__(self) -> None:
        self.calls: list[list[str]] = []

    def factory(self, _workdir: Path):
        def run(args) -> GitOutcome:
            self.calls.append(list(args))
            return GitOutcome(returncode=0)

        return run


def _capture_first_prompt(repo: Path, client: FakeGitHubClient) -> str:
    engine = _CapturingEngine()
    publish = _RecordingPublishRunner()
    loop = RalphLoop(
        config=RunConfig(engine="fake", max_iterations=1),
        repo_root=repo,
        client=client,
        engine=engine,
        origin_main=_OriginMain(),
        worktrees=WorktreeManager(repo, runner=default_git_runner),
        gate_runner_factory=lambda _w, _i, _n: GateRunner(
            lambda _c: CommandResult(exit_status=0)
        ),
        publish_runner_factory=publish.factory,
    )
    loop.run()
    return engine.prompts[0] if engine.prompts else ""


# ---------------------------------------------------------------------------
# 1. XML <ralph_phase> wrapper shape
# ---------------------------------------------------------------------------


class XmlEnvelopeShapeTests(unittest.TestCase):
    """The phase prompt is wrapped in <ralph_phase> with required child sections."""

    def setUp(self) -> None:
        self.tmp = tempfile.TemporaryDirectory()
        repo = Path(self.tmp.name) / "repo"
        repo.mkdir()
        _init_repo(repo)
        client = FakeGitHubClient(issues={42: _issue(42)})
        self._prompt = _capture_first_prompt(repo, client)

    def tearDown(self) -> None:
        self.tmp.cleanup()

    def test_outermost_element_is_ralph_phase(self) -> None:
        self.assertTrue(
            self._prompt.strip().startswith("<ralph_phase>"),
            f"Prompt must start with <ralph_phase>, got: {self._prompt[:120]}",
        )
        self.assertTrue(
            self._prompt.strip().endswith("</ralph_phase>"),
            "Prompt must end with </ralph_phase>",
        )

    def _index(self, tag: str) -> int:
        return self._prompt.index(tag)

    def test_required_sections_present(self) -> None:
        for tag in (
            "<runtime>",
            "<authority>",
            "<allowed_actions>",
            "<forbidden_actions>",
            "<reference_paths>",
            "<completion_contract>",
            "<phase_instructions>",
        ):
            with self.subTest(tag=tag):
                self.assertIn(tag, self._prompt)

    def test_section_order_matches_spec(self) -> None:
        order = [
            "<runtime>",
            "<authority>",
            "<allowed_actions>",
            "<forbidden_actions>",
            "<reference_paths>",
            "<completion_contract>",
            "<phase_instructions>",
        ]
        for earlier, later in zip(order, order[1:]):
            with self.subTest(earlier=earlier, later=later):
                self.assertLess(self._index(earlier), self._index(later))


# ---------------------------------------------------------------------------
# 2. <forbidden_actions> non-empty in rendered phase prompts
# ---------------------------------------------------------------------------


class ForbiddenActionsInEnvelopeTests(unittest.TestCase):
    """<forbidden_actions> section is non-empty for each normal phase."""

    def setUp(self) -> None:
        self.tmp = tempfile.TemporaryDirectory()
        repo = Path(self.tmp.name) / "repo"
        repo.mkdir()
        _init_repo(repo)
        client = FakeGitHubClient(issues={42: _issue(42)})
        self._prompt = _capture_first_prompt(repo, client)

    def tearDown(self) -> None:
        self.tmp.cleanup()

    def test_forbidden_actions_section_non_empty_in_implement_phase(self) -> None:
        start = self._prompt.index("<forbidden_actions>") + len("<forbidden_actions>")
        end = self._prompt.index("</forbidden_actions>")
        inner = self._prompt[start:end].strip()
        self.assertGreater(len(inner), 0, "<forbidden_actions> must not be empty in implement phase")

    def test_forbidden_actions_contains_action_elements(self) -> None:
        self.assertIn("<action>", self._prompt)

    def test_all_normal_phases_have_non_empty_forbidden_actions(self) -> None:
        for phase in (PHASE_IMPLEMENT, PHASE_REVIEW, PHASE_DIAGNOSE):
            with self.subTest(phase=phase):
                result = _forbidden_actions_for_phase(phase)
                self.assertGreater(len(result), 0, f"Phase {phase} must have forbidden_actions")


# ---------------------------------------------------------------------------
# 3. Comments as context-only, split out of issue-contract.md
# ---------------------------------------------------------------------------


def _contract_with_comments() -> IssueContract:
    return IssueContract(
        number=100,
        title="Split comments test",
        body="Implement the feature.",
        labels=frozenset({"ready-for-agent"}),
        comments_for_context=(
            IssueComment(author="kevin", body="Agent Brief\n\nFocus on the header layout."),
            IssueComment(author="alice", body="Looks good in general."),
        ),
    )


def _contract_no_comments() -> IssueContract:
    return IssueContract(
        number=101,
        title="No comments",
        body="Simple issue.",
        labels=frozenset({"ready-for-agent"}),
    )


class CommentsContextOnlyTests(unittest.TestCase):
    """Comments are context-only and split out of issue-contract.md."""

    def test_issue_contract_does_not_embed_comment_bodies(self) -> None:
        out = render_issue_contract(_contract_with_comments())
        self.assertNotIn("Focus on the header layout.", out)
        self.assertNotIn("Looks good in general.", out)

    def test_issue_contract_has_no_comments_section(self) -> None:
        out = render_issue_contract(_contract_with_comments())
        self.assertNotIn("## Comments", out)

    def test_issue_contract_body_labelled_as_authority(self) -> None:
        out = render_issue_contract(_contract_with_comments())
        self.assertIn("implementation authority", out)

    def test_issue_comments_file_renders_comment_bodies(self) -> None:
        out = render_issue_comments(_contract_with_comments())
        self.assertIsNotNone(out)
        self.assertIn("Focus on the header layout.", out)
        self.assertIn("Looks good in general.", out)

    def test_agent_brief_comment_marked_context_only(self) -> None:
        out = render_issue_comments(_contract_with_comments())
        self.assertIsNotNone(out)
        # Must explicitly state context only; must not positively claim authority.
        self.assertIn("context only", out)
        # "no implementation authority" (denial) is fine; "is the implementation authority"
        # (positive claim) must not appear.
        self.assertNotIn("is the implementation authority", out)

    def test_no_comments_returns_none_from_render(self) -> None:
        self.assertIsNone(render_issue_comments(_contract_no_comments()))

    def test_issue_comments_file_name_constant_used(self) -> None:
        self.assertEqual(ISSUE_COMMENTS_FILE, "issue-comments.md")
        self.assertNotEqual(ISSUE_CONTRACT_FILE, ISSUE_COMMENTS_FILE)

# ---------------------------------------------------------------------------
# 5. No broad "do not run UI tests" wording in implement-tdd
# ---------------------------------------------------------------------------


class ImplementTddNobroadUIBanTests(unittest.TestCase):
    """implement.md must not use the broad phrase that bans all UI tests."""

    def setUp(self) -> None:
        self._prompt = _IMPLEMENT_MD.read_text(encoding="utf-8")

    def test_no_broad_do_not_run_ui_tests_phrase(self) -> None:
        lower = self._prompt.lower()
        self.assertNotIn("do not run ui tests", lower)

    def test_no_broad_do_not_run_xcode_ui_integration_tests_phrase(self) -> None:
        self.assertNotIn("Do NOT run Xcode UI integration tests in this phase", self._prompt)

    def test_forbidden_actions_for_implement_do_not_broadly_ban_ui_tests(self) -> None:
        combined = " ".join(_forbidden_actions_for_phase(PHASE_IMPLEMENT)).lower()
        # Must not contain a raw "do not run ui tests" style entry
        self.assertNotIn("do not run ui tests", combined)
        # Must name specific things that are forbidden instead
        self.assertIn("workouttrackeruitests", combined)


# ---------------------------------------------------------------------------
# 6. No gh issue view contract-discovery instruction outside diagnose
# ---------------------------------------------------------------------------


class GhIssueViewOnlyInDiagnoseTests(unittest.TestCase):
    """gh issue view must not appear in non-diagnose prompt files as a contract source."""

    def test_implement_excludes_gh_issue_view(self) -> None:
        self.assertNotIn("gh issue view", _IMPLEMENT_MD.read_text(encoding="utf-8"))

    def test_review_excludes_gh_issue_view(self) -> None:
        self.assertNotIn("gh issue view", _REVIEW_MD.read_text(encoding="utf-8"))

    def test_diagnose_retains_gh_issue_view(self) -> None:
        # diagnose.md is exempt — it is the only phase that fetches live issue state.
        self.assertIn("gh issue view", _DIAGNOSE_MD.read_text(encoding="utf-8"))


if __name__ == "__main__":
    unittest.main()
