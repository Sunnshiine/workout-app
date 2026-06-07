"""Tests for the XML ralph_phase prompt envelope produced by _phase_prompt.

Decision #5: wrap the whole phase prompt in <ralph_phase> with ordered child
sections: <runtime>, <authority>, <allowed_actions>, <forbidden_actions>,
<reference_paths>, <completion_contract>, <phase_instructions>.

Decision #3: PhaseContext gains forbidden_actions field.
Decision #4: _forbidden_actions_for_phase wired into _run_phase.
"""

from __future__ import annotations

import subprocess
import tempfile
import unittest
from pathlib import Path

from ralph.orchestrator.config import RunConfig
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
from ralph.orchestrator.prompt_context import PhaseContext
from ralph.orchestrator.publish import LABEL_READY_FOR_AGENT, GitOutcome
from ralph.orchestrator.worktree import WorktreeManager, default_git_runner


def _git(repo: Path, *args: str) -> None:
    subprocess.run(
        ["git", "-C", str(repo), *args],
        check=True,
        capture_output=True,
        text=True,
    )


def _init_repo(repo: Path) -> None:
    _git(repo, "init", "-b", "main")
    _git(repo, "config", "user.email", "ralph@example.com")
    _git(repo, "config", "user.name", "Ralph")
    (repo / "README.md").write_text("seed\n", encoding="utf-8")
    prompts = repo / "ralph" / "prompts"
    prompts.mkdir(parents=True)
    for name in ("implement.md", "review.md", "diagnose.md"):
        (prompts / name).write_text(f"{name}\n", encoding="utf-8")
    _git(repo, "add", "README.md", "ralph/prompts")
    _git(repo, "commit", "-m", "seed")


def _issue(number: int, *, title: str = "T", body: str = "Do it") -> dict:
    return {
        "number": number,
        "title": title,
        "body": body,
        "labels": [{"name": LABEL_READY_FOR_AGENT}],
        "comments": [],
    }


class _RecordingPublishRunner:
    def __init__(self) -> None:
        self.calls: list[list[str]] = []

    def factory(self, _workdir: Path):
        def run(args) -> GitOutcome:
            self.calls.append(list(args))
            return GitOutcome(returncode=0)

        return run


class _CapturingEngine:
    """Engine that records the prompt from each PhaseRequest."""

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


def _build_loop_and_capture_prompt(repo: Path, client: FakeGitHubClient) -> str:
    """Run one issue through the loop and return the first captured prompt."""
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


class ForbiddenActionsForPhaseTests(unittest.TestCase):
    """_forbidden_actions_for_phase returns a non-empty tuple for every normal phase."""

    def test_implement_tdd_forbidden_actions_non_empty(self) -> None:
        result = _forbidden_actions_for_phase(PHASE_IMPLEMENT)
        self.assertIsInstance(result, tuple)
        self.assertGreater(len(result), 0)

    def test_review_forbidden_actions_non_empty(self) -> None:
        result = _forbidden_actions_for_phase(PHASE_REVIEW)
        self.assertIsInstance(result, tuple)
        self.assertGreater(len(result), 0)

    def test_diagnose_forbidden_actions_non_empty(self) -> None:
        result = _forbidden_actions_for_phase(PHASE_DIAGNOSE)
        self.assertIsInstance(result, tuple)
        self.assertGreater(len(result), 0)

    def test_implement_tdd_forbids_full_ui_test_bundle(self) -> None:
        result = _forbidden_actions_for_phase(PHASE_IMPLEMENT)
        combined = " ".join(result).lower()
        self.assertIn("workouttrackeruitests", combined)

    def test_implement_tdd_forbids_spawning_review_subagents(self) -> None:
        result = _forbidden_actions_for_phase(PHASE_IMPLEMENT)
        combined = " ".join(result).lower()
        self.assertIn("review subagent", combined)

    def test_unknown_phase_returns_empty_tuple(self) -> None:
        result = _forbidden_actions_for_phase("unknown-phase")
        self.assertEqual(result, ())


class PhaseContextForbiddenActionsFieldTests(unittest.TestCase):
    """PhaseContext carries a forbidden_actions field."""

    def test_default_forbidden_actions_is_empty_tuple(self) -> None:
        ctx = PhaseContext(
            role="test",
            phase="implement",
            target_branch="ralph/issue-1",
            complete_promise_line="<promise>COMPLETE</promise>",
            blocked_promise_prefix="<promise>BLOCKED:",
        )
        self.assertEqual(ctx.forbidden_actions, ())

    def test_forbidden_actions_set_on_construction(self) -> None:
        ctx = PhaseContext(
            role="test",
            phase="implement",
            target_branch="ralph/issue-1",
            complete_promise_line="<promise>COMPLETE</promise>",
            blocked_promise_prefix="<promise>BLOCKED:",
            forbidden_actions=("do not push", "do not merge"),
        )
        self.assertEqual(ctx.forbidden_actions, ("do not push", "do not merge"))

    def test_frozen_dataclass_cannot_be_mutated(self) -> None:
        ctx = PhaseContext(
            role="test",
            phase="implement",
            target_branch="ralph/issue-1",
            complete_promise_line="<promise>COMPLETE</promise>",
            blocked_promise_prefix="<promise>BLOCKED:",
        )
        with self.assertRaises((AttributeError, TypeError)):
            ctx.forbidden_actions = ("push",)  # type: ignore[misc]


class PhaseEnvelopeShapeTests(unittest.TestCase):
    """_phase_prompt wraps the whole prompt in a <ralph_phase> XML envelope."""

    def setUp(self) -> None:
        self.tmp = tempfile.TemporaryDirectory()
        self.repo = Path(self.tmp.name) / "repo"
        self.repo.mkdir()
        _init_repo(self.repo)
        self.client = FakeGitHubClient(issues={7: _issue(7)})
        self._prompt = _build_loop_and_capture_prompt(self.repo, self.client)

    def tearDown(self) -> None:
        self.tmp.cleanup()

    def test_prompt_wrapped_in_ralph_phase(self) -> None:
        self.assertTrue(
            self._prompt.strip().startswith("<ralph_phase>"),
            f"Expected prompt to start with <ralph_phase>, got: {self._prompt[:200]}",
        )
        self.assertIn("</ralph_phase>", self._prompt)

    def test_prompt_contains_runtime_section(self) -> None:
        self.assertIn("<runtime>", self._prompt)
        self.assertIn("</runtime>", self._prompt)

    def test_prompt_contains_authority_section(self) -> None:
        self.assertIn("<authority>", self._prompt)
        self.assertIn("</authority>", self._prompt)

    def test_prompt_contains_allowed_actions_section(self) -> None:
        self.assertIn("<allowed_actions>", self._prompt)
        self.assertIn("</allowed_actions>", self._prompt)

    def test_prompt_contains_forbidden_actions_section(self) -> None:
        self.assertIn("<forbidden_actions>", self._prompt)
        self.assertIn("</forbidden_actions>", self._prompt)

    def test_prompt_contains_reference_paths_section(self) -> None:
        self.assertIn("<reference_paths>", self._prompt)
        self.assertIn("</reference_paths>", self._prompt)

    def test_prompt_contains_completion_contract_section(self) -> None:
        self.assertIn("<completion_contract>", self._prompt)
        self.assertIn("</completion_contract>", self._prompt)

    def test_prompt_contains_phase_instructions_section(self) -> None:
        self.assertIn("<phase_instructions>", self._prompt)
        self.assertIn("</phase_instructions>", self._prompt)

    def test_section_order_runtime_before_authority(self) -> None:
        self.assertLess(self._prompt.index("<runtime>"), self._prompt.index("<authority>"))

    def test_section_order_authority_before_allowed_actions(self) -> None:
        self.assertLess(self._prompt.index("<authority>"), self._prompt.index("<allowed_actions>"))

    def test_section_order_allowed_before_forbidden(self) -> None:
        self.assertLess(
            self._prompt.index("<allowed_actions>"), self._prompt.index("<forbidden_actions>")
        )

    def test_section_order_forbidden_before_reference_paths(self) -> None:
        self.assertLess(
            self._prompt.index("<forbidden_actions>"), self._prompt.index("<reference_paths>")
        )

    def test_section_order_reference_paths_before_completion_contract(self) -> None:
        self.assertLess(
            self._prompt.index("<reference_paths>"), self._prompt.index("<completion_contract>")
        )

    def test_section_order_completion_contract_before_phase_instructions(self) -> None:
        self.assertLess(
            self._prompt.index("<completion_contract>"),
            self._prompt.index("<phase_instructions>"),
        )

    def test_phase_instructions_contains_original_prompt_body(self) -> None:
        # The implement.md content is "implement.md\n" (from _init_repo)
        self.assertIn("implement.md", self._prompt)

    def test_no_blank_diagnosis_path_key_when_absent(self) -> None:
        # Must not produce a "DIAGNOSIS_PATH: " blank key line
        self.assertNotIn("DIAGNOSIS_PATH: \n", self._prompt)
        self.assertNotIn("DIAGNOSIS_PATH:", self._prompt)

    def test_runtime_contains_engine_and_phase(self) -> None:
        start = self._prompt.index("<runtime>")
        end = self._prompt.index("</runtime>")
        runtime_block = self._prompt[start:end]
        self.assertIn("fake", runtime_block)
        self.assertIn(PHASE_IMPLEMENT, runtime_block)

    def test_runtime_contains_issue_number(self) -> None:
        start = self._prompt.index("<runtime>")
        end = self._prompt.index("</runtime>")
        runtime_block = self._prompt[start:end]
        self.assertIn("7", runtime_block)

    def test_forbidden_actions_non_empty_in_implement_phase(self) -> None:
        start = self._prompt.index("<forbidden_actions>")
        end = self._prompt.index("</forbidden_actions>")
        section = self._prompt[start:end]
        inner = section.replace("<forbidden_actions>", "").strip()
        self.assertGreater(len(inner), 0)

    def test_no_old_flat_key_value_preamble(self) -> None:
        # Old format keys must be gone
        self.assertNotIn("ENGINE:", self._prompt)
        self.assertNotIn("PUBLISH_TARGET: pr", self._prompt)
        self.assertNotIn("PHASE_NAME:", self._prompt)
        self.assertNotIn("CONTEXT_PATH:", self._prompt)
        self.assertNotIn("COMPLETE_PROMISE_LINE:", self._prompt)
        self.assertNotIn("BLOCKED_PROMISE_PREFIX:", self._prompt)


if __name__ == "__main__":
    unittest.main()
