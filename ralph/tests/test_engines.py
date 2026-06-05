from __future__ import annotations

import shutil
import tempfile
import unittest
from pathlib import Path

from ralph.orchestrator.engine import FakeEngine, PhaseRequest
from ralph.orchestrator.engines import (
    TIMEOUT_EXIT_STATUS,
    ClaudeCliEngine,
    ClaudeSdkEngine,
    CliInvocation,
    CliResult,
    CodexCliEngine,
    CodexSdkEngine,
    SdkEvent,
    SdkInvocation,
    blocked_promise_prefix,
    complete_promise_line,
    normalize_sdk_events,
    parse_promise,
    resolve_engine,
)
from ralph.orchestrator.phase import PhaseStatus


def _request(phase: str = "implement") -> PhaseRequest:
    return PhaseRequest(
        phase=phase,
        prompt="do the work",
        workdir=Path("/tmp/worktree"),
        issue_number=212,
        timeout_seconds=30,
        log_path=Path("ralph/.artifacts/logs/issue-212-implement.log"),
    )


class _ScriptedCli:
    """Records the invocation and returns a scripted CLI result."""

    def __init__(self, result: CliResult) -> None:
        self._result = result
        self.invocations: list[CliInvocation] = []

    def __call__(self, invocation: CliInvocation) -> CliResult:
        self.invocations.append(invocation)
        return self._result


class _ScriptedSdk:
    """Records the invocation and replays a scripted event stream."""

    def __init__(self, events: list[SdkEvent]) -> None:
        self._events = events
        self.invocations: list[SdkInvocation] = []

    def __call__(self, invocation: SdkInvocation) -> list[SdkEvent]:
        self.invocations.append(invocation)
        return self._events


class ParsePromiseTests(unittest.TestCase):
    def test_complete_line_wins(self) -> None:
        out = f"working...\n{complete_promise_line('implement')}\n"
        status, reason = parse_promise("implement", out)
        self.assertIs(status, PhaseStatus.COMPLETE)
        self.assertIsNone(reason)

    def test_blocked_reason_is_extracted(self) -> None:
        line = f"{blocked_promise_prefix('implement')}cannot meet criteria</promise>"
        status, reason = parse_promise("implement", f"notes\n{line}\n")
        self.assertIs(status, PhaseStatus.BLOCKED)
        self.assertEqual(reason, "cannot meet criteria")

    def test_complete_beats_blocked_when_both_present(self) -> None:
        blocked = f"{blocked_promise_prefix('implement')}stuck</promise>"
        out = f"{blocked}\n{complete_promise_line('implement')}\n"
        status, _ = parse_promise("implement", out)
        self.assertIs(status, PhaseStatus.COMPLETE)

    def test_phase_name_must_match(self) -> None:
        # A COMPLETE promise for a different phase does not satisfy this phase.
        out = f"{complete_promise_line('swift-review')}\n"
        status, _ = parse_promise("implement", out)
        self.assertIs(status, PhaseStatus.FAILED)

    def test_no_promise_is_failed(self) -> None:
        status, reason = parse_promise("implement", "I finished, looks good.")
        self.assertIs(status, PhaseStatus.FAILED)
        self.assertIn("did not report the exact completion promise", reason or "")


class CliEngineTests(unittest.TestCase):
    def test_complete_output_normalizes_to_complete(self) -> None:
        runner = _ScriptedCli(CliResult(returncode=0, output=complete_promise_line("implement")))
        result = CodexCliEngine(runner=runner).run_phase(_request())
        self.assertIs(result.status, PhaseStatus.COMPLETE)
        self.assertEqual(result.phase, "implement")
        self.assertEqual(result.log_path, _request().log_path)
        # The runner saw the request's prompt, workdir, and timeout.
        invocation = runner.invocations[0]
        self.assertEqual(invocation.prompt, "do the work")
        self.assertEqual(invocation.timeout_seconds, 30)

    def test_blocked_output_carries_reason(self) -> None:
        line = f"{blocked_promise_prefix('implement')}needs human</promise>"
        runner = _ScriptedCli(CliResult(returncode=1, output=line))
        result = ClaudeCliEngine(runner=runner).run_phase(_request())
        self.assertIs(result.status, PhaseStatus.BLOCKED)
        self.assertEqual(result.blocked_reason, "needs human")

    def test_timeout_exit_status_normalizes_to_timeout(self) -> None:
        runner = _ScriptedCli(CliResult(returncode=TIMEOUT_EXIT_STATUS, output="partial"))
        result = CodexCliEngine(runner=runner).run_phase(_request())
        self.assertIs(result.status, PhaseStatus.TIMEOUT)
        self.assertIn("timed out", result.blocked_reason or "")

    def test_nonzero_without_promise_is_failed(self) -> None:
        runner = _ScriptedCli(CliResult(returncode=1, output="crashed"))
        result = CodexCliEngine(runner=runner).run_phase(_request())
        self.assertIs(result.status, PhaseStatus.FAILED)


class SdkNormalizationTests(unittest.TestCase):
    def test_text_events_accumulate_and_promise_decides(self) -> None:
        events = [
            SdkEvent(kind="text", text="thinking...\n"),
            SdkEvent(kind="text", text=complete_promise_line("implement") + "\n"),
            SdkEvent(kind="result", text=""),
        ]
        result = normalize_sdk_events(_request(), events)
        self.assertIs(result.status, PhaseStatus.COMPLETE)
        self.assertIn("thinking...", result.final_response)

    def test_blocked_event_stream_carries_reason(self) -> None:
        line = f"{blocked_promise_prefix('implement')}auth missing</promise>"
        events = [SdkEvent(kind="text", text=line)]
        result = normalize_sdk_events(_request(), events)
        self.assertIs(result.status, PhaseStatus.BLOCKED)
        self.assertEqual(result.blocked_reason, "auth missing")

    def test_timed_out_event_normalizes_to_timeout(self) -> None:
        events = [SdkEvent(kind="text", text="partial"), SdkEvent(kind="result", timed_out=True)]
        result = normalize_sdk_events(_request(), events)
        self.assertIs(result.status, PhaseStatus.TIMEOUT)

    def test_error_event_without_completion_is_failed(self) -> None:
        events = [SdkEvent(kind="error", is_error=True, text="rate limited")]
        result = normalize_sdk_events(_request(), events)
        self.assertIs(result.status, PhaseStatus.FAILED)

    def test_error_event_does_not_override_a_completion_promise(self) -> None:
        events = [
            SdkEvent(kind="text", text=complete_promise_line("implement") + "\n"),
            SdkEvent(kind="error", is_error=True, text="late warning"),
        ]
        result = normalize_sdk_events(_request(), events)
        self.assertIs(result.status, PhaseStatus.COMPLETE)


class SdkEngineTests(unittest.TestCase):
    def test_sdk_engine_drives_client_and_normalizes(self) -> None:
        sdk = _ScriptedSdk([SdkEvent(kind="text", text=complete_promise_line("implement"))])
        engine = ClaudeSdkEngine(sdk, model="opus")
        result = engine.run_phase(_request())
        self.assertIs(result.status, PhaseStatus.COMPLETE)
        self.assertEqual(sdk.invocations[0].phase, "implement")
        self.assertEqual(sdk.invocations[0].model, "opus")


class ResolveEngineTests(unittest.TestCase):
    def test_fake_is_always_available(self) -> None:
        self.assertIsInstance(resolve_engine("fake"), FakeEngine)

    def test_cli_names_resolve_to_cli_adapters(self) -> None:
        self.assertIsInstance(resolve_engine("codex-cli"), CodexCliEngine)
        self.assertIsInstance(resolve_engine("claude-cli"), ClaudeCliEngine)

    def test_sdk_names_with_client_resolve_to_sdk_adapters(self) -> None:
        sdk = _ScriptedSdk([])
        self.assertIsInstance(resolve_engine("codex", sdk_client=sdk), CodexSdkEngine)
        self.assertIsInstance(resolve_engine("claude", sdk_client=sdk), ClaudeSdkEngine)

    def test_sdk_names_without_client_fall_back_to_cli(self) -> None:
        self.assertIsInstance(resolve_engine("codex"), CodexCliEngine)
        self.assertIsInstance(resolve_engine("claude"), ClaudeCliEngine)

    def test_unknown_name_is_rejected(self) -> None:
        with self.assertRaises(ValueError):
            resolve_engine("gpt")


class CliSmokeTests(unittest.TestCase):
    def test_real_cli_binary_runs_a_harmless_read_only_phase(self) -> None:
        # Smoke test against a real binary only when one is installed; skipped
        # otherwise so the suite never needs a real agent/SDK.
        binary = shutil.which("true")
        if binary is None:
            self.skipTest("no harmless CLI binary available for a smoke test")
        engine = CodexCliEngine()
        engine.binary = (binary,)
        with tempfile.TemporaryDirectory() as workdir:
            request = PhaseRequest(
                phase="implement",
                prompt="do the work",
                workdir=Path(workdir),
                issue_number=212,
                timeout_seconds=30,
            )
            result = engine.run_phase(request)
        # ``true`` exits 0 with no promise line, so the adapter normalizes to a
        # FAILED phase (no completion promise) without raising.
        self.assertIs(result.status, PhaseStatus.FAILED)


if __name__ == "__main__":
    unittest.main()
