"""Provider SDK clients for Ralph engine adapters.

These clients translate provider-specific SDK calls into Ralph's neutral
``SdkEvent`` stream. They do not select issues, create worktrees, publish PRs, or
run gates; those decisions stay in the Python orchestrator.
"""

from __future__ import annotations

import asyncio
import importlib
from collections.abc import Iterable
from dataclasses import dataclass
from types import ModuleType
from typing import Any

from .engines import (
    CLAUDE_SDK_ENGINE,
    CODEX_SDK_ENGINE,
    SdkEvent,
    SdkInvocation,
)

_CLAUDE_ALLOWED_TOOLS = (
    "Read",
    "Write",
    "Edit",
    "MultiEdit",
    "Bash",
    "Grep",
    "Glob",
    "LS",
)


@dataclass(frozen=True)
class CodexProviderSdkClient:
    """Run one Ralph phase through the official ``openai-codex`` Python SDK."""

    module: ModuleType | Any | None = None

    def __call__(self, invocation: SdkInvocation) -> Iterable[SdkEvent]:
        try:
            module = self._module()
            Codex = module.Codex
            Sandbox = module.Sandbox
            approval_mode = _approval_mode(module)
            start_kwargs = _codex_turn_kwargs(
                invocation, module, Sandbox, approval_mode, include_effort=False
            )
            run_kwargs = _codex_turn_kwargs(
                invocation, module, Sandbox, approval_mode, include_effort=True
            )
            with Codex() as codex:
                thread = codex.thread_start(**start_kwargs)
                result = thread.run(invocation.prompt, **run_kwargs)
            return _codex_result_events(result)
        except Exception as error:  # noqa: BLE001 - provider errors normalize to SDK events.
            return [_provider_error_event("codex", error)]

    def _module(self) -> ModuleType | Any:
        if self.module is not None:
            return self.module
        return importlib.import_module("openai_codex")


@dataclass(frozen=True)
class ClaudeProviderSdkClient:
    """Run one Ralph phase through the official ``claude-agent-sdk`` package."""

    module: ModuleType | Any | None = None
    allowed_tools: tuple[str, ...] = _CLAUDE_ALLOWED_TOOLS
    permission_mode: str = "acceptEdits"
    # No turn cap: a phase (implement-tdd, diagnose, review, repair) needs many
    # iterative read/edit/test/fix turns. The wall-clock ``timeout_seconds`` bound
    # in ``_collect`` is the only limit, matching the Codex client. A finite cap
    # here makes the agent exit with ``error_max_turns`` before it can emit the
    # completion promise, which the orchestrator reports as a FAILED phase.
    max_turns: int | None = None

    def __call__(self, invocation: SdkInvocation) -> Iterable[SdkEvent]:
        try:
            return asyncio.run(self._collect(invocation))
        except Exception as error:  # noqa: BLE001 - provider errors normalize to SDK events.
            return [_provider_error_event("claude", error)]

    async def _collect(self, invocation: SdkInvocation) -> list[SdkEvent]:
        module = self._module()
        options = module.ClaudeAgentOptions(
            cwd=str(invocation.workdir),
            allowed_tools=list(self.allowed_tools),
            permission_mode=self.permission_mode,
            max_turns=self.max_turns,
            model=invocation.model,
        )
        events: list[SdkEvent] = []
        try:
            async with asyncio.timeout(invocation.timeout_seconds):
                async for message in module.query(prompt=invocation.prompt, options=options):
                    events.extend(_claude_message_events(module, message))
        except TimeoutError:
            events.append(SdkEvent(kind="result", timed_out=True))
        return events

    def _module(self) -> ModuleType | Any:
        if self.module is not None:
            return self.module
        return importlib.import_module("claude_agent_sdk")


def default_sdk_client_for_engine(engine_name: str):
    """Return the default provider SDK client when its package can be imported."""

    if engine_name == CODEX_SDK_ENGINE:
        return _client_if_importable("openai_codex", CodexProviderSdkClient)
    if engine_name == CLAUDE_SDK_ENGINE:
        return _client_if_importable("claude_agent_sdk", ClaudeProviderSdkClient)
    return None


def _client_if_importable(module_name: str, factory):
    try:
        module = importlib.import_module(module_name)
    except ImportError:
        return None
    return factory(module=module)


def _codex_turn_kwargs(
    invocation: SdkInvocation,
    module,
    Sandbox,
    approval_mode,
    *,
    include_effort: bool,
) -> dict[str, object]:
    kwargs: dict[str, object] = {
        "cwd": str(invocation.workdir),
        "sandbox": Sandbox.workspace_write,
    }
    if approval_mode is not None:
        kwargs["approval_mode"] = approval_mode
    if invocation.model is not None:
        kwargs["model"] = invocation.model
    if include_effort and invocation.reasoning_effort is not None:
        kwargs["effort"] = _codex_reasoning_effort(module, invocation.reasoning_effort)
    return kwargs


def _codex_reasoning_effort(module, effort: str) -> object:
    enum = getattr(module, "ReasoningEffort", None)
    if enum is None:
        enum = importlib.import_module("openai_codex.api").ReasoningEffort
    return getattr(enum, effort)


def _approval_mode(module) -> object | None:
    mode = getattr(module, "ApprovalMode", None)
    if mode is None:
        return None
    return getattr(mode, "auto_review", None)


def _codex_result_events(result) -> list[SdkEvent]:
    events: list[SdkEvent] = []
    final_response = getattr(result, "final_response", None)
    if final_response:
        events.append(SdkEvent(kind="text", text=str(final_response)))

    error = getattr(result, "error", None)
    status = _provider_status(getattr(result, "status", None))
    if error is not None or status in {"failed", "interrupted"}:
        reason = str(error) if error is not None else f"Codex turn ended with status {status}."
        events.append(SdkEvent(kind="error", text=reason, is_error=True))
    else:
        events.append(SdkEvent(kind="result"))
    return events


def _claude_message_events(module, message) -> list[SdkEvent]:
    AssistantMessage = getattr(module, "AssistantMessage", None)
    TextBlock = getattr(module, "TextBlock", None)
    ResultMessage = getattr(module, "ResultMessage", None)

    if AssistantMessage is not None and isinstance(message, AssistantMessage):
        return _claude_content_events(TextBlock, getattr(message, "content", ()))
    if ResultMessage is not None and isinstance(message, ResultMessage):
        return _claude_result_events(message)
    if hasattr(message, "content"):
        return _claude_content_events(TextBlock, message.content)
    if hasattr(message, "result") or hasattr(message, "is_error"):
        return _claude_result_events(message)
    return []


def _claude_content_events(TextBlock, content) -> list[SdkEvent]:
    events: list[SdkEvent] = []
    for block in content or ():
        if TextBlock is not None and not isinstance(block, TextBlock):
            continue
        text = getattr(block, "text", None)
        if text:
            events.append(SdkEvent(kind="text", text=str(text)))
    return events


def _claude_result_events(message) -> list[SdkEvent]:
    events: list[SdkEvent] = []
    result = getattr(message, "result", None)
    if result:
        events.append(SdkEvent(kind="text", text=str(result)))
    if getattr(message, "is_error", False):
        error_text = _claude_error_text(message)
        events.append(SdkEvent(kind="error", text=error_text, is_error=True))
    else:
        events.append(SdkEvent(kind="result"))
    return events


def _claude_error_text(message) -> str:
    errors = getattr(message, "errors", None)
    if errors:
        return "\n".join(str(error) for error in errors)
    status = getattr(message, "subtype", None)
    return f"Claude turn ended with error subtype {status}."


def _provider_status(value: object) -> str:
    raw = getattr(value, "value", value)
    return str(raw) if raw is not None else ""


def _provider_error_event(provider: str, error: Exception) -> SdkEvent:
    return SdkEvent(
        kind="error",
        text=f"{provider} SDK client failed: {type(error).__name__}: {error}",
        is_error=True,
    )


__all__ = [
    "ClaudeProviderSdkClient",
    "CodexProviderSdkClient",
    "default_sdk_client_for_engine",
]
