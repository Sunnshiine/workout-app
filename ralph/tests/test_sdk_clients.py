from __future__ import annotations

import asyncio
import unittest
from dataclasses import dataclass
from pathlib import Path
from types import SimpleNamespace

from ralph.orchestrator.engines import SdkEvent, SdkInvocation, complete_promise_line
from ralph.orchestrator.sdk_clients import ClaudeProviderSdkClient, CodexProviderSdkClient


def _invocation(timeout_seconds: int = 30) -> SdkInvocation:
    return SdkInvocation(
        phase="implement",
        prompt="do the work",
        workdir=Path("/tmp/worktree"),
        issue_number=212,
        timeout_seconds=timeout_seconds,
        model="agent-model",
        reasoning_effort="medium",
    )


class _CodexSandbox:
    workspace_write = "workspace-write"


class _CodexApprovalMode:
    auto_review = "auto-review"


class _CodexReasoningEffort:
    high = "high-effort"
    medium = "medium-effort"


@dataclass(frozen=True)
class _CodexResult:
    final_response: str | None = None
    status: str = "completed"
    error: object | None = None


class _CodexThread:
    def __init__(self, module) -> None:
        self._module = module

    def run(self, prompt: str, **kwargs):
        self._module.run_prompt = prompt
        self._module.run_kwargs = kwargs
        return self._module.result


class _Codex:
    def __init__(self) -> None:
        self._module = _CODEX_MODULE

    def __enter__(self):
        return self

    def __exit__(self, *_args) -> None:
        return None

    def thread_start(self, **kwargs):
        self._module.start_kwargs = kwargs
        return _CodexThread(self._module)


_CODEX_MODULE = SimpleNamespace(
    Codex=_Codex,
    Sandbox=_CodexSandbox,
    ApprovalMode=_CodexApprovalMode,
    ReasoningEffort=_CodexReasoningEffort,
    result=_CodexResult(final_response=complete_promise_line("implement")),
)


class CodexProviderSdkClientTests(unittest.TestCase):
    def test_runs_codex_thread_in_phase_worktree(self) -> None:
        _CODEX_MODULE.result = _CodexResult(final_response=complete_promise_line("implement"))
        events = list(CodexProviderSdkClient(module=_CODEX_MODULE)(_invocation()))

        self.assertEqual(events[0], SdkEvent(kind="text", text=complete_promise_line("implement")))
        self.assertEqual(events[1], SdkEvent(kind="result"))
        self.assertEqual(_CODEX_MODULE.start_kwargs["cwd"], "/tmp/worktree")
        self.assertEqual(_CODEX_MODULE.start_kwargs["sandbox"], "workspace-write")
        self.assertEqual(_CODEX_MODULE.start_kwargs["approval_mode"], "auto-review")
        self.assertEqual(_CODEX_MODULE.start_kwargs["model"], "agent-model")
        self.assertNotIn("effort", _CODEX_MODULE.start_kwargs)
        self.assertEqual(_CODEX_MODULE.run_prompt, "do the work")
        self.assertEqual(_CODEX_MODULE.run_kwargs["effort"], "medium-effort")

    def test_codex_reasoning_effort_is_passed_to_run(self) -> None:
        _CODEX_MODULE.result = _CodexResult(final_response=complete_promise_line("implement"))
        events = list(
            CodexProviderSdkClient(module=_CODEX_MODULE)(
                SdkInvocation(
                    phase="implement",
                    prompt="do the work",
                    workdir=Path("/tmp/worktree"),
                    issue_number=212,
                    timeout_seconds=30,
                    model="agent-model",
                    reasoning_effort="high",
                )
            )
        )

        self.assertEqual(events[0], SdkEvent(kind="text", text=complete_promise_line("implement")))
        self.assertEqual(_CODEX_MODULE.run_kwargs["effort"], "high-effort")

    def test_codex_error_result_becomes_error_event(self) -> None:
        _CODEX_MODULE.result = _CodexResult(
            final_response="partial",
            status="failed",
            error="auth failed",
        )
        events = list(CodexProviderSdkClient(module=_CODEX_MODULE)(_invocation()))

        self.assertEqual(events[0], SdkEvent(kind="text", text="partial"))
        self.assertTrue(events[1].is_error)
        self.assertIn("auth failed", events[1].text)


@dataclass(frozen=True)
class _TextBlock:
    text: str


@dataclass(frozen=True)
class _AssistantMessage:
    content: list[_TextBlock]


@dataclass(frozen=True)
class _ResultMessage:
    result: str | None = None
    is_error: bool = False
    errors: list[str] | None = None
    subtype: str | None = None


class _ClaudeAgentOptions:
    def __init__(self, **kwargs) -> None:
        _CLAUDE_MODULE.options_kwargs = kwargs


async def _claude_query(*, prompt: str, options):
    _CLAUDE_MODULE.prompt = prompt
    _CLAUDE_MODULE.options = options
    for message in _CLAUDE_MODULE.messages:
        yield message


async def _slow_claude_query(*, prompt: str, options):
    await asyncio.sleep(1)
    yield _AssistantMessage([_TextBlock(complete_promise_line("implement"))])


_CLAUDE_MODULE = SimpleNamespace(
    ClaudeAgentOptions=_ClaudeAgentOptions,
    AssistantMessage=_AssistantMessage,
    TextBlock=_TextBlock,
    ResultMessage=_ResultMessage,
    query=_claude_query,
    messages=[],
)


class ClaudeProviderSdkClientTests(unittest.TestCase):
    def test_streams_claude_text_blocks_with_phase_options(self) -> None:
        _CLAUDE_MODULE.query = _claude_query
        _CLAUDE_MODULE.messages = [
            _AssistantMessage([_TextBlock("working\n")]),
            _AssistantMessage([_TextBlock(complete_promise_line("implement"))]),
            _ResultMessage(),
        ]

        events = list(ClaudeProviderSdkClient(module=_CLAUDE_MODULE)(_invocation()))

        self.assertEqual(
            events,
            [
                SdkEvent(kind="text", text="working\n"),
                SdkEvent(kind="text", text=complete_promise_line("implement")),
                SdkEvent(kind="result"),
            ],
        )
        self.assertEqual(_CLAUDE_MODULE.prompt, "do the work")
        self.assertEqual(_CLAUDE_MODULE.options_kwargs["cwd"], "/tmp/worktree")
        self.assertEqual(_CLAUDE_MODULE.options_kwargs["model"], "agent-model")
        self.assertEqual(_CLAUDE_MODULE.options_kwargs["max_turns"], 1)
        self.assertIn("Edit", _CLAUDE_MODULE.options_kwargs["allowed_tools"])

    def test_claude_error_result_becomes_error_event(self) -> None:
        _CLAUDE_MODULE.query = _claude_query
        _CLAUDE_MODULE.messages = [_ResultMessage(is_error=True, errors=["rate limited"])]

        events = list(ClaudeProviderSdkClient(module=_CLAUDE_MODULE)(_invocation()))

        self.assertEqual(events, [SdkEvent(kind="error", text="rate limited", is_error=True)])

    def test_claude_timeout_becomes_timeout_event(self) -> None:
        _CLAUDE_MODULE.query = _slow_claude_query

        events = list(
            ClaudeProviderSdkClient(module=_CLAUDE_MODULE)(_invocation(timeout_seconds=0))
        )

        self.assertEqual(events, [SdkEvent(kind="result", timed_out=True)])


if __name__ == "__main__":
    unittest.main()
