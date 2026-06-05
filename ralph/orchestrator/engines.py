"""SDK-forward engine adapters, with temporary CLI fallbacks.

Each adapter satisfies the :class:`Engine` contract from ``engine.py`` and returns
a NORMALIZED :class:`PhaseResult` regardless of how the underlying provider reports
its turn. Two transports are supported during the side-by-side migration, but the
strategic/default direction is SDK-first:

- SDK adapters (:class:`CodexSdkEngine`, :class:`ClaudeSdkEngine`) drive a provider
  client that yields a stream of events and normalize the final event shape to the
  same :class:`PhaseResult`.
- CLI adapters (:class:`CodexCliEngine`, :class:`ClaudeCliEngine`) run the existing
  command-line agent and parse the shell promise lines
  (``<promise phase="...">COMPLETE</promise>`` /
  ``<promise phase="...">BLOCKED:reason</promise>``) out of captured output. This
  keeps a migration/diagnostic fallback available until SDK auth, permissions,
  structured logs, and timeout behavior are proven locally.

Every transport is behind an injectable seam: the CLI adapters take a
``CliRunner`` and the SDK adapters take an ``SdkClient``. Tests inject fakes so no
adapter ever shells out to a real binary or hits a real network. Production should
wire SDK clients for ``codex`` and ``claude``; without those clients, resolution
degrades to the matching CLI fallback during the migration. The fake engine stays
the dry-run/test default.
"""

from __future__ import annotations

import subprocess
from collections.abc import Callable, Iterable
from dataclasses import dataclass, field

from .engine import FAKE_ENGINE, Engine, FakeEngine, PhaseRequest
from .phase import PhaseResult, PhaseStatus

# Engine names (shared with ``config.ENGINE_CHOICES``).
CODEX_SDK_ENGINE = "codex"
CLAUDE_SDK_ENGINE = "claude"
CODEX_CLI_ENGINE = "codex-cli"
CLAUDE_CLI_ENGINE = "claude-cli"

# Exit status the timeout wrapper returns (mirrors ``coreutils timeout`` and the
# ``run_agent_to_file_with_timeout`` contract in ``ralph/ralph.sh``).
TIMEOUT_EXIT_STATUS = 124

_COMPLETE_TOKEN = "COMPLETE</promise>"
_BLOCKED_CLOSE = "</promise>"


# --------------------------------------------------------------------------- #
# Promise-line parsing (CLI compatibility)
# --------------------------------------------------------------------------- #
def complete_promise_line(phase: str) -> str:
    """Exact COMPLETE line the agent must emit for ``phase``."""

    return f'<promise phase="{phase}">COMPLETE</promise>'


def blocked_promise_prefix(phase: str) -> str:
    """Prefix that opens a BLOCKED promise for ``phase``."""

    return f'<promise phase="{phase}">BLOCKED:'


def parse_promise(phase: str, output: str) -> tuple[PhaseStatus, str | None]:
    """Parse promise lines for ``phase`` out of agent ``output``.

    Mirrors ``ralph.sh``: a COMPLETE promise is matched as a whole stripped line
    and wins; otherwise a BLOCKED promise's reason is extracted from the first
    matching line. With neither present the phase is treated as failed (the agent
    ended without the exact completion promise).
    """

    complete = complete_promise_line(phase)
    blocked_prefix = blocked_promise_prefix(phase)
    blocked_reason: str | None = None
    for raw in output.splitlines():
        line = raw.strip()
        if line == complete:
            return PhaseStatus.COMPLETE, None
        if blocked_reason is None and blocked_prefix in line:
            blocked_reason = _extract_blocked_reason(line, blocked_prefix)
    if blocked_reason is not None:
        return PhaseStatus.BLOCKED, blocked_reason
    return (
        PhaseStatus.FAILED,
        f"{phase} did not report the exact completion promise. Expected: {complete}",
    )


def _extract_blocked_reason(line: str, prefix: str) -> str:
    start = line.index(prefix) + len(prefix)
    reason = line[start:]
    close = reason.find(_BLOCKED_CLOSE)
    if close != -1:
        reason = reason[:close]
    return reason.strip()


# --------------------------------------------------------------------------- #
# CLI transport seam
# --------------------------------------------------------------------------- #
@dataclass(frozen=True)
class CliResult:
    """Outcome of running a CLI agent turn through the seam."""

    returncode: int
    output: str = ""

    @property
    def timed_out(self) -> bool:
        return self.returncode == TIMEOUT_EXIT_STATUS


# Runs one agent turn for a request and returns captured output + exit status.
# Real use wraps a subprocess with a timeout; tests inject a fake.
CliRunner = Callable[["CliInvocation"], CliResult]


@dataclass(frozen=True)
class CliInvocation:
    """Everything a CLI runner needs to launch one agent turn."""

    argv: tuple[str, ...]
    prompt: str
    workdir: object
    timeout_seconds: int


def default_cli_runner(invocation: CliInvocation) -> CliResult:
    """Run a CLI agent turn, capturing combined output (never raises on exit).

    The prompt is fed on stdin and the process is bounded by
    ``timeout_seconds``; a timeout normalizes to :data:`TIMEOUT_EXIT_STATUS` so
    the adapter reports a ``TIMEOUT`` phase result rather than crashing.
    """

    try:
        completed = subprocess.run(  # noqa: S603 - argv is adapter-controlled, never shell.
            list(invocation.argv),
            input=invocation.prompt,
            cwd=str(invocation.workdir),
            capture_output=True,
            text=True,
            check=False,
            timeout=invocation.timeout_seconds,
        )
    except subprocess.TimeoutExpired as expired:
        return CliResult(returncode=TIMEOUT_EXIT_STATUS, output=_decode(expired.output))
    return CliResult(
        returncode=completed.returncode,
        output=(completed.stdout or "") + (completed.stderr or ""),
    )


def _decode(value: object) -> str:
    if isinstance(value, bytes):
        return value.decode("utf-8", errors="ignore")
    return value if isinstance(value, str) else ""


class _CliEngine(Engine):
    """Shared CLI adapter: launch the agent binary and parse promise lines."""

    binary: tuple[str, ...]

    def __init__(self, *, runner: CliRunner | None = None) -> None:
        self._runner = runner or default_cli_runner

    def run_phase(self, request: PhaseRequest) -> PhaseResult:
        result = self._runner(
            CliInvocation(
                argv=self.binary,
                prompt=request.prompt,
                workdir=request.workdir,
                timeout_seconds=request.timeout_seconds,
            )
        )
        if result.timed_out:
            return PhaseResult(
                phase=request.phase,
                status=PhaseStatus.TIMEOUT,
                final_response=result.output,
                log_path=request.log_path,
                blocked_reason=(
                    f"{request.phase} timed out after "
                    f"{request.timeout_seconds}s without reporting completion."
                ),
            )
        status, reason = parse_promise(request.phase, result.output)
        return PhaseResult(
            phase=request.phase,
            status=status,
            final_response=result.output,
            log_path=request.log_path,
            blocked_reason=reason,
        )


class CodexCliEngine(_CliEngine):
    """Codex CLI fallback adapter."""

    name = CODEX_CLI_ENGINE
    binary = ("codex", "exec")


class ClaudeCliEngine(_CliEngine):
    """Claude CLI fallback adapter."""

    name = CLAUDE_CLI_ENGINE
    binary = ("claude", "-p")


# --------------------------------------------------------------------------- #
# SDK transport seam
# --------------------------------------------------------------------------- #
@dataclass(frozen=True)
class SdkEvent:
    """One normalized event from a provider SDK stream.

    Providers emit different event shapes; the adapter maps each provider event
    onto this neutral shape before deciding the phase result. ``kind`` is one of
    ``"text"`` (assistant output chunk), ``"result"`` (terminal turn outcome), or
    ``"error"`` (provider/transport failure).
    """

    kind: str
    text: str = ""
    is_error: bool = False
    timed_out: bool = False


# A provider client runs one turn and yields its event stream. Real use wraps the
# provider SDK; tests inject a fake that replays a scripted event list.
SdkClient = Callable[["SdkInvocation"], Iterable[SdkEvent]]


@dataclass(frozen=True)
class SdkInvocation:
    """Everything an SDK client needs to run one turn."""

    phase: str
    prompt: str
    workdir: object
    issue_number: int
    timeout_seconds: int
    model: str | None = None
    extra: dict[str, object] = field(default_factory=dict)


class _SdkEngine(Engine):
    """Shared SDK adapter: drive a provider client and normalize its events."""

    def __init__(self, client: SdkClient, *, model: str | None = None) -> None:
        self._client = client
        self._model = model

    def run_phase(self, request: PhaseRequest) -> PhaseResult:
        events = self._client(
            SdkInvocation(
                phase=request.phase,
                prompt=request.prompt,
                workdir=request.workdir,
                issue_number=request.issue_number,
                timeout_seconds=request.timeout_seconds,
                model=self._model,
            )
        )
        return normalize_sdk_events(request, events)


def normalize_sdk_events(request: PhaseRequest, events: Iterable[SdkEvent]) -> PhaseResult:
    """Collapse a provider SDK event stream into one normalized ``PhaseResult``.

    Text chunks accumulate into ``final_response``; the same promise-line contract
    as the CLI adapters decides COMPLETE vs BLOCKED. A timed-out or errored stream
    short-circuits to TIMEOUT / FAILED so SDK and CLI transports agree on outcome.
    """

    chunks: list[str] = []
    timed_out = False
    errored = False
    for event in events:
        if event.text:
            chunks.append(event.text)
        if event.timed_out:
            timed_out = True
        if event.is_error or event.kind == "error":
            errored = True
    transcript = "".join(chunks)

    if timed_out:
        return PhaseResult(
            phase=request.phase,
            status=PhaseStatus.TIMEOUT,
            final_response=transcript,
            log_path=request.log_path,
            blocked_reason=(
                f"{request.phase} timed out after "
                f"{request.timeout_seconds}s without reporting completion."
            ),
        )
    status, reason = parse_promise(request.phase, transcript)
    if errored and status is not PhaseStatus.COMPLETE:
        return PhaseResult(
            phase=request.phase,
            status=PhaseStatus.FAILED,
            final_response=transcript,
            log_path=request.log_path,
            blocked_reason=reason or f"{request.phase} provider stream reported an error.",
        )
    return PhaseResult(
        phase=request.phase,
        status=status,
        final_response=transcript,
        log_path=request.log_path,
        blocked_reason=reason,
    )


class CodexSdkEngine(_SdkEngine):
    """Codex SDK adapter."""

    name = CODEX_SDK_ENGINE


class ClaudeSdkEngine(_SdkEngine):
    """Claude SDK adapter."""

    name = CLAUDE_SDK_ENGINE


# --------------------------------------------------------------------------- #
# Resolution
# --------------------------------------------------------------------------- #
def resolve_engine(
    engine_name: str,
    *,
    model: str | None = None,
    sdk_client: SdkClient | None = None,
    cli_runner: CliRunner | None = None,
    use_default_sdk_client: bool = True,
) -> Engine:
    """Resolve an engine name to a concrete adapter.

    The fake engine is always available. ``codex`` and ``claude`` are SDK-forward
    names: production should pass a provider ``sdk_client`` for them. During the
    migration, a missing client degrades to the matching CLI fallback so existing
    local agent tooling remains available for diagnostics and rollback.
    """

    if engine_name == FAKE_ENGINE:
        return FakeEngine()
    if engine_name == CODEX_CLI_ENGINE:
        return CodexCliEngine(runner=cli_runner)
    if engine_name == CLAUDE_CLI_ENGINE:
        return ClaudeCliEngine(runner=cli_runner)
    if engine_name == CODEX_SDK_ENGINE:
        client = sdk_client or _default_sdk_client(engine_name, use_default_sdk_client)
        if client is None:
            return CodexCliEngine(runner=cli_runner)
        return CodexSdkEngine(client, model=model)
    if engine_name == CLAUDE_SDK_ENGINE:
        client = sdk_client or _default_sdk_client(engine_name, use_default_sdk_client)
        if client is None:
            return ClaudeCliEngine(runner=cli_runner)
        return ClaudeSdkEngine(client, model=model)
    raise ValueError(
        f"unknown engine {engine_name!r}; expected one of: "
        f"{FAKE_ENGINE}, {CLAUDE_SDK_ENGINE}, {CODEX_SDK_ENGINE}, "
        f"{CLAUDE_CLI_ENGINE}, {CODEX_CLI_ENGINE}"
    )


def _default_sdk_client(engine_name: str, enabled: bool) -> SdkClient | None:
    if not enabled:
        return None
    from .sdk_clients import default_sdk_client_for_engine

    return default_sdk_client_for_engine(engine_name)


__all__ = [
    "CLAUDE_CLI_ENGINE",
    "CLAUDE_SDK_ENGINE",
    "CODEX_CLI_ENGINE",
    "CODEX_SDK_ENGINE",
    "TIMEOUT_EXIT_STATUS",
    "ClaudeCliEngine",
    "ClaudeSdkEngine",
    "CliInvocation",
    "CliResult",
    "CliRunner",
    "CodexCliEngine",
    "CodexSdkEngine",
    "SdkClient",
    "SdkEvent",
    "SdkInvocation",
    "blocked_promise_prefix",
    "complete_promise_line",
    "default_cli_runner",
    "normalize_sdk_events",
    "parse_promise",
    "resolve_engine",
]
