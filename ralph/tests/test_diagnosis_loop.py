from __future__ import annotations

import json
import subprocess
import tempfile
import unittest
from pathlib import Path

from ralph.orchestrator.config import RunConfig
from ralph.orchestrator.contracts import parse_ui_test_authorization
from ralph.orchestrator.engine import FakeEngine
from ralph.orchestrator.gates import CommandResult, GateRunner
from ralph.orchestrator.github import FakeGitHubClient
from ralph.orchestrator.loop import OriginMain, RalphLoop
from ralph.orchestrator.phase import PhaseResult, PhaseStatus
from ralph.orchestrator.publish import LABEL_READY_FOR_AGENT, GitOutcome
from ralph.orchestrator.worktree import WorktreeManager, default_git_runner

_PROMPT_FILES = (
    "implement.md",
    "review.md",
    "diagnose.md",
    "diagnose-extract.md",
)

# Every well-formed artifact carries the handoff fields the parser now requires.
_HANDOFF = {
    "root_cause": "Tap never reaches the visible writable row.",
    "fix_plan": "Route the gesture through the real control.",
    "test_seam": "Tests/UI integration proves the visible state.",
}


def _block(payload: dict) -> str:
    return f"<diagnosis-result>\n{json.dumps(payload, indent=2)}\n</diagnosis-result>"


_REQUIRED_BLOCK = _block(
    {
        **_HANDOFF,
        "ui_integration_test_edits_required": True,
        "scope": ["Tests/UI/WorkoutTrackerUITests.swift"],
        "reason": "Only the UI route proves the tap reaches the visible state.",
    }
)
_NOT_REQUIRED_BLOCK = _block({**_HANDOFF, "ui_integration_test_edits_required": False})
_OUT_OF_SCOPE_BLOCK = _block(
    {
        **_HANDOFF,
        "ui_integration_test_edits_required": True,
        "scope": ["Tests/UI/WorkoutTrackerUITests.swift", "project.yml"],
        "reason": "also needs test-target wiring",
    }
)
_REASONING_TEXT = "Findings: reproduced the crash; root cause and fix plan documented."


def _git(repo: Path, *args: str) -> None:
    subprocess.run(["git", "-C", str(repo), *args], check=True, capture_output=True, text=True)


def _init_repo(repo: Path) -> None:
    _git(repo, "init", "-b", "main")
    _git(repo, "config", "user.email", "ralph@example.com")
    _git(repo, "config", "user.name", "Ralph")
    (repo / "README.md").write_text("seed\n", encoding="utf-8")
    prompts = repo / "ralph" / "prompts"
    prompts.mkdir(parents=True)
    for name in _PROMPT_FILES:
        (prompts / name).write_text(f"{name}\n", encoding="utf-8")
    _git(repo, "add", "README.md", "ralph/prompts")
    _git(repo, "commit", "-m", "seed")


def _bug_issue(number: int, *, body: str = "Crash on tap", labels=None) -> dict:
    names = labels if labels is not None else [LABEL_READY_FOR_AGENT, "bug"]
    return {
        "number": number,
        "title": "Logging tap does nothing",
        "body": body,
        "labels": [{"name": name} for name in names],
        "comments": [],
    }


def _complete(phase: str, response: str) -> PhaseResult:
    return PhaseResult(phase=phase, status=PhaseStatus.COMPLETE, final_response=response)


class _EditingEngine(FakeEngine):
    """FakeEngine that commits one file edit during a chosen phase.

    Lets loop tests exercise the mechanical authority gate, which diffs the real
    worktree rather than trusting phase output.
    """

    def __init__(self, *, edit_phase: str, rel_path: str, **kwargs) -> None:
        super().__init__(**kwargs)
        self._edit_phase = edit_phase
        self._rel_path = rel_path

    def run_phase(self, request):
        if request.phase == self._edit_phase:
            target = request.workdir / self._rel_path
            target.parent.mkdir(parents=True, exist_ok=True)
            target.write_text("// authority gate test edit\n", encoding="utf-8")
            _git(request.workdir, "add", "-A")
            _git(request.workdir, "commit", "-m", f"edit {self._rel_path}")
        return super().run_phase(request)


class _SequencedEngine(FakeEngine):
    """FakeEngine that returns a different scripted result on each call to a phase.

    Lets a test drive the extraction retry: the first ``diagnose-extract`` turn
    emits a malformed artifact and a later one emits a well-formed one, while
    ``diagnose`` reasoning runs only once.
    """

    def __init__(self, *, sequences, **kwargs) -> None:
        super().__init__(**kwargs)
        self._sequences = {phase: list(results) for phase, results in sequences.items()}

    def run_phase(self, request):
        sequence = self._sequences.get(request.phase)
        if sequence:
            self.calls.append(request)
            return sequence.pop(0)
        return super().run_phase(request)


class _OriginMain(OriginMain):
    def __init__(self) -> None:
        self.polls = 0

    def poll(self) -> None:
        self.polls += 1

    def base_ref_for(self, _target) -> str:
        self.poll()
        return "main"


class _RecordingPublishRunner:
    def __init__(self) -> None:
        self.calls: list[list[str]] = []

    def factory(self, _workdir: Path):
        def run(args) -> GitOutcome:
            self.calls.append(list(args))
            return GitOutcome(returncode=0)

        return run


class DiagnosisGateLoopTests(unittest.TestCase):
    def setUp(self) -> None:
        self.tmp = tempfile.TemporaryDirectory()
        self.repo = Path(self.tmp.name) / "repo"
        self.repo.mkdir()
        _init_repo(self.repo)
        self.publish = _RecordingPublishRunner()

    def tearDown(self) -> None:
        self.tmp.cleanup()

    def _loop(self, client: FakeGitHubClient, engine: FakeEngine) -> RalphLoop:
        return RalphLoop(
            config=RunConfig(engine="fake", max_iterations=1),
            repo_root=self.repo,
            client=client,
            engine=engine,
            origin_main=_OriginMain(),
            worktrees=WorktreeManager(self.repo, runner=default_git_runner),
            gate_runner_factory=lambda _w, _i, _n: GateRunner(
                lambda _c: CommandResult(exit_status=0)
            ),
            publish_runner_factory=self.publish.factory,
        )

    def _context_dir(self, number: int) -> Path:
        return self.repo / "ralph" / ".artifacts" / "context" / f"issue-{number}"

    def _phases(self, engine: FakeEngine) -> list[str]:
        return [call.phase for call in engine.calls]

    def test_bug_issue_diagnoses_before_implement(self) -> None:
        client = FakeGitHubClient(issues={11: _bug_issue(11)})
        engine = FakeEngine(
            results_by_phase={
                "diagnose": _complete("diagnose", _REASONING_TEXT),
                "diagnose-extract": _complete("diagnose-extract", _NOT_REQUIRED_BLOCK),
            }
        )

        summary = self._loop(client, engine).run()

        self.assertEqual(summary.issues_completed, (11,))
        self.assertEqual(
            self._phases(engine),
            ["diagnose", "diagnose-extract", "implement-tdd", "review"],
        )

    def test_non_bug_issue_skips_diagnosis(self) -> None:
        client = FakeGitHubClient(
            issues={12: _bug_issue(12, labels=[LABEL_READY_FOR_AGENT])}
        )
        engine = FakeEngine()

        summary = self._loop(client, engine).run()

        self.assertEqual(summary.issues_completed, (12,))
        self.assertEqual(
            self._phases(engine), ["implement-tdd", "review"]
        )
        self.assertNotIn("diagnose", self._phases(engine))

    def test_malformed_artifact_triggers_extract_only_retry_then_proceeds(self) -> None:
        client = FakeGitHubClient(issues={13: _bug_issue(13)})
        engine = _SequencedEngine(
            sequences={
                "diagnose": [_complete("diagnose", _REASONING_TEXT)],
                "diagnose-extract": [
                    _complete("diagnose-extract", "Findings but no result artifact."),
                    _complete("diagnose-extract", _NOT_REQUIRED_BLOCK),
                ],
            }
        )

        summary = self._loop(client, engine).run()

        self.assertEqual(summary.issues_completed, (13,))
        # Only the cheap extraction turn reruns; reasoning runs exactly once.
        self.assertEqual(
            self._phases(engine),
            ["diagnose", "diagnose-extract", "diagnose-extract", "implement-tdd", "review"],
        )
        # The retry prompt carries the parser error so the model can correct it.
        retry_calls = [call for call in engine.calls if call.phase == "diagnose-extract"]
        retry_prompt = retry_calls[1].prompt
        self.assertIn("<retry_context>", retry_prompt)
        self.assertIn("could not be parsed", retry_prompt)
        # The handoff written for implementation is the diagnose reasoning output.
        handoff = (self._context_dir(13) / "diagnosis.md").read_text(encoding="utf-8")
        self.assertIn(_REASONING_TEXT, handoff)

    def test_still_malformed_after_retries_escalates_without_rerunning_diagnose(self) -> None:
        client = FakeGitHubClient(issues={14: _bug_issue(14)})
        engine = _SequencedEngine(
            sequences={
                "diagnose": [_complete("diagnose", _REASONING_TEXT)],
                "diagnose-extract": [
                    _complete("diagnose-extract", "no artifact"),
                    _complete("diagnose-extract", "still no artifact"),
                    _complete("diagnose-extract", "still no artifact again"),
                ],
            }
        )

        summary = self._loop(client, engine).run()

        self.assertEqual(summary.issues_blocked, (14,))
        self.assertEqual(summary.issues_completed, ())
        # diagnose runs exactly once; diagnose-extract gets two retries (three
        # attempts total), then escalates — never advanced to implementation.
        self.assertEqual(
            self._phases(engine),
            ["diagnose", "diagnose-extract", "diagnose-extract", "diagnose-extract"],
        )

    def test_grant_appends_authority_section_comments_and_recaptures(self) -> None:
        client = FakeGitHubClient(issues={15: _bug_issue(15)})
        engine = FakeEngine(
            results_by_phase={
                "diagnose": _complete("diagnose", _REASONING_TEXT),
                "diagnose-extract": _complete("diagnose-extract", _REQUIRED_BLOCK),
            }
        )

        summary = self._loop(client, engine).run()

        self.assertEqual(summary.issues_completed, (15,))
        call_kinds = [call[0] for call in client.calls]
        self.assertIn("edit_issue_body", call_kinds)
        self.assertIn("comment_issue", call_kinds)
        # Issue body now carries the durable authority marker and section.
        body = client.view_issue(15)["body"]
        self.assertTrue(parse_ui_test_authorization(body))
        self.assertIn("## Test authority", body)
        self.assertIn("Tests/UI/WorkoutTrackerUITests.swift", body)
        # Recaptured contract reached implementation: the refreshed contract
        # artifact's *derived* Authority line shows authorized. This line only
        # renders when contract.ui_test_edits_authorized is True, which only
        # happens after a real recapture (the raw body marker is not enough).
        contract_md = (self._context_dir(15) / "issue-contract.md").read_text(encoding="utf-8")
        self.assertIn("- UI integration test edits: authorized", contract_md)

    def test_grant_reuses_existing_test_authority_section(self) -> None:
        body = "Crash on tap.\n\n## Test authority\n\nPrior note.\n"
        client = FakeGitHubClient(issues={16: _bug_issue(16, body=body)})
        engine = FakeEngine(
            results_by_phase={
                "diagnose": _complete("diagnose", _REASONING_TEXT),
                "diagnose-extract": _complete("diagnose-extract", _REQUIRED_BLOCK),
            }
        )

        self._loop(client, engine).run()

        updated = client.view_issue(16)["body"]
        self.assertEqual(updated.count("## Test authority"), 1)
        self.assertIn("Prior note.", updated)
        self.assertTrue(parse_ui_test_authorization(updated))

    def test_already_authorized_body_is_not_edited(self) -> None:
        body = "Crash.\n\n## Test authority\n\nUI integration test edits: authorized\n"
        client = FakeGitHubClient(issues={17: _bug_issue(17, body=body)})
        engine = FakeEngine(
            results_by_phase={
                "diagnose": _complete("diagnose", _REASONING_TEXT),
                "diagnose-extract": _complete("diagnose-extract", _REQUIRED_BLOCK),
            }
        )

        summary = self._loop(client, engine).run()

        self.assertEqual(summary.issues_completed, (17,))
        call_kinds = [call[0] for call in client.calls]
        self.assertNotIn("edit_issue_body", call_kinds)

    def test_authority_beyond_ui_tests_escalates_without_body_edit(self) -> None:
        client = FakeGitHubClient(issues={18: _bug_issue(18)})
        engine = FakeEngine(
            results_by_phase={
                "diagnose": _complete("diagnose", _REASONING_TEXT),
                "diagnose-extract": _complete("diagnose-extract", _OUT_OF_SCOPE_BLOCK),
            }
        )

        summary = self._loop(client, engine).run()

        self.assertEqual(summary.issues_blocked, (18,))
        call_kinds = [call[0] for call in client.calls]
        self.assertNotIn("edit_issue_body", call_kinds)
        # Escalated before implementation.
        self.assertEqual(self._phases(engine), ["diagnose", "diagnose-extract"])

    def test_diagnosis_handoff_is_written_and_referenced_by_later_phases(self) -> None:
        client = FakeGitHubClient(issues={19: _bug_issue(19)})
        engine = FakeEngine(
            results_by_phase={
                "diagnose": _complete("diagnose", _REASONING_TEXT),
                "diagnose-extract": _complete("diagnose-extract", _NOT_REQUIRED_BLOCK),
            }
        )

        self._loop(client, engine).run()

        diagnosis_md = self._context_dir(19) / "diagnosis.md"
        self.assertTrue(diagnosis_md.exists())
        handoff = diagnosis_md.read_text(encoding="utf-8")
        # The handoff is the diagnose reasoning turn's output, not the JSON artifact.
        self.assertIn(_REASONING_TEXT, handoff)

        by_phase = {call.phase: call for call in engine.calls}
        # Mandatory for implementation: the XML envelope surfaces diagnosis_path.
        self.assertIn("<diagnosis_path>", by_phase["implement-tdd"].prompt)
        self.assertIn("diagnosis.md", by_phase["implement-tdd"].prompt)
        self.assertIn("diagnosis.md", by_phase["review"].prompt)
        # The diagnose phase itself has no prior handoff: element is self-closing.
        self.assertIn("<diagnosis_path/>", by_phase["diagnose"].prompt)
        # The extraction turn receives the reasoning output inline.
        self.assertIn("<extraction_input>", by_phase["diagnose-extract"].prompt)
        self.assertIn(_REASONING_TEXT, by_phase["diagnose-extract"].prompt)

    def test_unauthorized_ui_test_edit_is_blocked_by_authority_gate(self) -> None:
        # Non-bug issue: no diagnosis grant, so a Tests/UI edit is unauthorized.
        client = FakeGitHubClient(
            issues={21: _bug_issue(21, labels=[LABEL_READY_FOR_AGENT])}
        )
        engine = _EditingEngine(
            edit_phase="implement-tdd", rel_path="Tests/UI/FooUITests.swift"
        )

        summary = self._loop(client, engine).run()

        self.assertEqual(summary.issues_blocked, (21,))
        self.assertEqual(summary.issues_completed, ())

    def test_diagnosis_grant_authorizes_issue_range_ui_test_edit(self) -> None:
        # The grant flows body-edit -> recapture -> contract snapshot, so the
        # mechanical gate now allows the same Tests/UI edit it would otherwise block.
        client = FakeGitHubClient(issues={22: _bug_issue(22)})
        engine = _EditingEngine(
            edit_phase="implement-tdd",
            rel_path="Tests/UI/FooUITests.swift",
            results_by_phase={
                "diagnose": _complete("diagnose", _REASONING_TEXT),
                "diagnose-extract": _complete("diagnose-extract", _REQUIRED_BLOCK),
            },
        )

        summary = self._loop(client, engine).run()

        self.assertEqual(summary.issues_completed, (22,))
        self.assertEqual(summary.issues_blocked, ())

    def test_blocked_diagnose_phase_escalates_before_implement(self) -> None:
        client = FakeGitHubClient(issues={20: _bug_issue(20)})
        engine = FakeEngine(
            results_by_phase={
                "diagnose": PhaseResult(
                    phase="diagnose",
                    status=PhaseStatus.BLOCKED,
                    blocked_reason="cannot reproduce",
                )
            }
        )

        summary = self._loop(client, engine).run()

        self.assertEqual(summary.issues_blocked, (20,))
        self.assertEqual(self._phases(engine), ["diagnose"])


if __name__ == "__main__":
    unittest.main()
