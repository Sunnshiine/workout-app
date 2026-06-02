#!/usr/bin/env python3
"""Summarize Ralph loop execution telemetry.

The report joins Ralph's gitignored activity/log artifacts with Codex JSONL
session telemetry. It is read-only: no GitHub, git, or artifact writes.
"""

from __future__ import annotations

import argparse
import csv
import json
import re
import sys
from dataclasses import dataclass, field
from datetime import datetime, timedelta, timezone
from pathlib import Path
from typing import Any
from zoneinfo import ZoneInfo


ACTIVITY_LINE_RE = re.compile(r"^- \*\*(?P<ts>[^*]+)\*\* — (?P<message>.*)$")
SELECTED_RE = re.compile(r"iteration (?P<iter>\d+): selected issue #(?P<issue>\d+)")
PHASE_START_RE = re.compile(
    r"issue #(?P<issue>\d+) (?P<phase>[A-Za-z0-9_-]+) started"
)
PHASE_COMPLETE_RE = re.compile(
    r"issue #(?P<issue>\d+) (?P<phase>[A-Za-z0-9_-]+) complete"
)
RESOLVED_RE = re.compile(r"issue #(?P<issue>\d+) resolved & merged")
HUMAN_RE = re.compile(r"issue #(?P<issue>\d+) -> ready-for-human: (?P<reason>.*)")
UNICODE_HUMAN_RE = re.compile(r"issue #(?P<issue>\d+) → ready-for-human: (?P<reason>.*)")
LOG_RE = re.compile(r"iter-(?P<iter>\d+)-issue-(?P<issue>\d+)-(?P<name>.+)\.log$")
ISSUE_CWD_RE = re.compile(r"/\.claude/worktrees/issue-(?P<issue>\d+)(?:$|/)")


TOKEN_FIELDS = (
    "input_tokens",
    "cached_input_tokens",
    "output_tokens",
    "reasoning_output_tokens",
    "total_tokens",
)


@dataclass
class Phase:
    name: str
    start: datetime | None = None
    end: datetime | None = None
    status: str = "unknown"
    sessions: list[str] = field(default_factory=list)


@dataclass
class Attempt:
    run_index: int
    iteration: int
    issue: int
    selected_at: datetime
    run_started_at: datetime | None
    terminal_at: datetime | None = None
    outcome: str = "incomplete"
    reason: str = ""
    phases: dict[str, Phase] = field(default_factory=dict)
    log_files: list[str] = field(default_factory=list)
    sessions: list[str] = field(default_factory=list)

    @property
    def started_at(self) -> datetime:
        phase_starts = [
            phase.start
            for phase in self.phases.values()
            if phase.start and phase.name != "select"
        ]
        if phase_starts:
            return min(phase_starts)
        return self.selected_at

    @property
    def ended_at(self) -> datetime | None:
        if self.terminal_at:
            return self.terminal_at
        phase_ends = [phase.end for phase in self.phases.values() if phase.end]
        if phase_ends:
            return max(phase_ends)
        return None


@dataclass
class SessionTelemetry:
    path: Path
    session_id: str
    started_at: datetime
    cwd: str
    thread_source: str
    agent_role: str | None
    parent_thread_id: str | None
    issue: int | None
    token_events: int
    compactions: int
    compaction_timestamps: list[datetime]
    token_totals: dict[str, int]
    max_last_input_tokens: int
    model_context_window: int | None


def parse_local_timestamp(raw: str, zone: ZoneInfo) -> datetime:
    return datetime.strptime(raw, "%Y-%m-%d %H:%M:%S").replace(tzinfo=zone)


def parse_iso_timestamp(raw: str, zone: ZoneInfo) -> datetime:
    if raw.endswith("Z"):
        raw = f"{raw[:-1]}+00:00"
    return datetime.fromisoformat(raw).astimezone(zone)


def format_duration(start: datetime | None, end: datetime | None) -> str:
    if not start or not end:
        return ""
    seconds = int((end - start).total_seconds())
    if seconds < 0:
        return ""
    minutes, secs = divmod(seconds, 60)
    hours, minutes = divmod(minutes, 60)
    if hours:
        return f"{hours}h {minutes}m {secs}s"
    if minutes:
        return f"{minutes}m {secs}s"
    return f"{secs}s"


def parse_activity(activity_path: Path, zone: ZoneInfo) -> list[Attempt]:
    attempts: list[Attempt] = []
    current_run_index = 0
    current_run_started_at: datetime | None = None
    current_select_started_at: datetime | None = None
    active_by_issue: dict[int, Attempt] = {}

    if not activity_path.exists():
        return attempts

    for line in activity_path.read_text(encoding="utf-8").splitlines():
        match = ACTIVITY_LINE_RE.match(line)
        if not match:
            continue

        ts = parse_local_timestamp(match.group("ts"), zone)
        message = normalize_arrow(match.group("message"))

        if message.startswith("run start"):
            current_run_index += 1
            current_run_started_at = ts
            current_select_started_at = ts
            active_by_issue = {}
            continue

        selected = SELECTED_RE.search(message)
        if selected:
            issue = int(selected.group("issue"))
            attempt = Attempt(
                run_index=current_run_index,
                iteration=int(selected.group("iter")),
                issue=issue,
                selected_at=ts,
                run_started_at=current_run_started_at,
            )
            if current_select_started_at:
                attempt.phases["select"] = Phase(
                    name="select",
                    start=current_select_started_at,
                    end=ts,
                    status="complete",
                )
            attempts.append(attempt)
            active_by_issue[issue] = attempt
            continue

        started = PHASE_START_RE.search(message)
        if started:
            attempt = active_by_issue.get(int(started.group("issue")))
            if attempt:
                phase_name = started.group("phase")
                attempt.phases[phase_name] = Phase(name=phase_name, start=ts, status="started")
            continue

        completed = PHASE_COMPLETE_RE.search(message)
        if completed:
            attempt = active_by_issue.get(int(completed.group("issue")))
            if attempt:
                phase_name = completed.group("phase")
                phase = attempt.phases.setdefault(phase_name, Phase(name=phase_name))
                phase.end = ts
                phase.status = "complete"
            continue

        resolved = RESOLVED_RE.search(message)
        if resolved:
            issue = int(resolved.group("issue"))
            attempt = active_by_issue.get(issue)
            if attempt:
                attempt.terminal_at = ts
                attempt.outcome = "resolved"
                current_select_started_at = ts
                active_by_issue.pop(issue, None)
            continue

        human = HUMAN_RE.search(message) or UNICODE_HUMAN_RE.search(message)
        if human:
            issue = int(human.group("issue"))
            attempt = active_by_issue.get(issue)
            if attempt:
                attempt.terminal_at = ts
                attempt.outcome = "ready-for-human"
                attempt.reason = human.group("reason")
                current_select_started_at = ts
                active_by_issue.pop(issue, None)

    return attempts


def normalize_arrow(value: str) -> str:
    return value.replace("→", "->")


def attach_log_files(attempts: list[Attempt], logs_dir: Path) -> None:
    by_key = {(attempt.iteration, attempt.issue): attempt for attempt in attempts}
    if not logs_dir.exists():
        return

    for path in sorted(logs_dir.glob("iter-*-issue-*.log")):
        match = LOG_RE.match(path.name)
        if not match:
            continue
        key = (int(match.group("iter")), int(match.group("issue")))
        attempt = by_key.get(key)
        if attempt:
            attempt.log_files.append(str(path))


def session_candidate_paths(
    sessions_dir: Path, attempts: list[Attempt], since: datetime | None, until: datetime | None
) -> list[Path]:
    if not sessions_dir.exists():
        return []

    if attempts and not since:
        since = min(attempt.selected_at for attempt in attempts) - timedelta(hours=2)
    if attempts and not until:
        ends = [attempt.ended_at or attempt.selected_at for attempt in attempts]
        until = max(ends) + timedelta(hours=2)

    if since and until:
        paths: list[Path] = []
        current = since.date()
        last = until.date()
        while current <= last:
            day_dir = sessions_dir / f"{current.year:04d}" / f"{current.month:02d}" / f"{current.day:02d}"
            paths.extend(day_dir.glob("rollout-*.jsonl"))
            current += timedelta(days=1)
        return sorted(paths)

    return sorted(sessions_dir.glob("**/rollout-*.jsonl"))


def parse_session(path: Path, zone: ZoneInfo) -> SessionTelemetry | None:
    session_meta: dict[str, Any] | None = None
    token_totals = {field: 0 for field in TOKEN_FIELDS}
    token_events = 0
    compactions = 0
    compaction_timestamps: list[datetime] = []
    max_last_input_tokens = 0
    model_context_window: int | None = None

    try:
        lines = path.read_text(encoding="utf-8").splitlines()
    except UnicodeDecodeError:
        return None

    for line in lines:
        try:
            event = json.loads(line)
        except json.JSONDecodeError:
            continue

        event_type = event.get("type")
        payload = event.get("payload") or {}
        if event_type == "session_meta":
            session_meta = payload
            continue

        if event_type != "event_msg":
            continue

        payload_type = payload.get("type")
        if payload_type == "context_compacted":
            compactions += 1
            timestamp = event.get("timestamp")
            if timestamp:
                compaction_timestamps.append(parse_iso_timestamp(timestamp, zone))
            continue

        if payload_type != "token_count":
            continue

        token_events += 1
        info = payload.get("info") or {}
        totals = info.get("total_token_usage") or {}
        token_totals = {field: int(totals.get(field) or 0) for field in TOKEN_FIELDS}
        last = info.get("last_token_usage") or {}
        max_last_input_tokens = max(max_last_input_tokens, int(last.get("input_tokens") or 0))
        if info.get("model_context_window"):
            model_context_window = int(info["model_context_window"])

    if not session_meta:
        return None

    session_id = str(session_meta.get("id") or path.stem)
    started_raw = str(session_meta.get("timestamp") or "")
    if not started_raw:
        return None

    cwd = str(session_meta.get("cwd") or "")
    source = session_meta.get("source") or {}
    subagent = source.get("subagent") if isinstance(source, dict) else None
    thread_spawn = subagent.get("thread_spawn") if isinstance(subagent, dict) else None
    parent_thread_id = None
    if isinstance(thread_spawn, dict):
        parent_thread_id = thread_spawn.get("parent_thread_id")

    agent_role = session_meta.get("agent_role")
    if not agent_role and isinstance(thread_spawn, dict):
        agent_role = thread_spawn.get("agent_role")

    issue_match = ISSUE_CWD_RE.search(cwd)
    issue = int(issue_match.group("issue")) if issue_match else None

    return SessionTelemetry(
        path=path,
        session_id=session_id,
        started_at=parse_iso_timestamp(started_raw, zone),
        cwd=cwd,
        thread_source=str(session_meta.get("thread_source") or ""),
        agent_role=str(agent_role) if agent_role else None,
        parent_thread_id=str(parent_thread_id) if parent_thread_id else None,
        issue=issue,
        token_events=token_events,
        compactions=compactions,
        compaction_timestamps=compaction_timestamps,
        token_totals=token_totals,
        max_last_input_tokens=max_last_input_tokens,
        model_context_window=model_context_window,
    )


def parse_sessions(
    sessions_dir: Path,
    attempts: list[Attempt],
    zone: ZoneInfo,
    since: datetime | None,
    until: datetime | None,
) -> dict[str, SessionTelemetry]:
    sessions: dict[str, SessionTelemetry] = {}
    for path in session_candidate_paths(sessions_dir, attempts, since, until):
        telemetry = parse_session(path, zone)
        if not telemetry:
            continue
        if since and telemetry.started_at < since:
            continue
        if until and telemetry.started_at > until:
            continue
        sessions[telemetry.session_id] = telemetry
    return sessions


def assign_sessions(attempts: list[Attempt], sessions: dict[str, SessionTelemetry]) -> None:
    attempts_by_issue: dict[int, list[Attempt]] = {}
    for attempt in attempts:
        attempts_by_issue.setdefault(attempt.issue, []).append(attempt)

    parent_phase_by_session: dict[str, tuple[Attempt, str | None]] = {}
    for session in sorted(sessions.values(), key=lambda value: value.started_at):
        attempt = find_attempt_for_session(session, attempts, attempts_by_issue)
        if not attempt:
            continue

        attempt.sessions.append(session.session_id)
        phase_name = find_phase_for_time(attempt, session.started_at)
        if phase_name:
            attempt.phases[phase_name].sessions.append(session.session_id)
        parent_phase_by_session[session.session_id] = (attempt, phase_name)

    for session in sessions.values():
        if not session.parent_thread_id:
            continue
        parent = parent_phase_by_session.get(session.parent_thread_id)
        if not parent:
            continue
        attempt, phase_name = parent
        if session.session_id not in attempt.sessions:
            attempt.sessions.append(session.session_id)
        if phase_name and session.session_id not in attempt.phases[phase_name].sessions:
            attempt.phases[phase_name].sessions.append(session.session_id)


def find_attempt_for_session(
    session: SessionTelemetry,
    attempts: list[Attempt],
    attempts_by_issue: dict[int, list[Attempt]],
) -> Attempt | None:
    if session.issue is not None:
        for attempt in attempts_by_issue.get(session.issue, []):
            if attempt_contains_time(attempt, session.started_at):
                return attempt
        return None

    # SELECT runs happen in the repo root, so assign the session to the selected
    # issue when it falls between run start and selection.
    for attempt in attempts:
        select_phase = attempt.phases.get("select")
        if not select_phase or not select_phase.start:
            continue
        window_end = (select_phase.end or attempt.selected_at) + timedelta(minutes=1)
        if select_phase.start <= session.started_at <= window_end:
            return attempt
    return None


def attempt_contains_time(attempt: Attempt, timestamp: datetime) -> bool:
    start = attempt.selected_at - timedelta(minutes=1)
    end = (attempt.ended_at or attempt.selected_at) + timedelta(minutes=5)
    return start <= timestamp <= end


def find_phase_for_time(attempt: Attempt, timestamp: datetime) -> str | None:
    phases = sorted(
        ((name, phase) for name, phase in attempt.phases.items() if phase.start),
        key=lambda item: item[1].start or datetime.min.replace(tzinfo=timezone.utc),
    )
    for index, (phase_name, phase) in enumerate(phases):
        if not phase.start:
            continue
        next_start = phases[index + 1][1].start if index + 1 < len(phases) else None
        end = next_start or (phase.end or attempt.ended_at or phase.start) + timedelta(minutes=5)
        if next_start:
            if phase.start <= timestamp < end:
                return phase_name
            continue
        if phase.start <= timestamp <= end:
            return phase_name
    if attempt.run_started_at and attempt.run_started_at <= timestamp <= attempt.selected_at + timedelta(minutes=1):
        return "select"
    return None


def summarize_tokens(session_ids: list[str], sessions: dict[str, SessionTelemetry]) -> dict[str, Any]:
    totals = {field: 0 for field in TOKEN_FIELDS}
    compactions = 0
    token_events = 0
    max_last_input_tokens = 0
    max_context_window = 0
    roles: set[str] = set()
    subagents = 0
    compaction_timestamps: list[str] = []

    for session_id in sorted(set(session_ids)):
        session = sessions.get(session_id)
        if not session:
            continue
        for field in TOKEN_FIELDS:
            totals[field] += session.token_totals.get(field, 0)
        compactions += session.compactions
        token_events += session.token_events
        max_last_input_tokens = max(max_last_input_tokens, session.max_last_input_tokens)
        if session.model_context_window:
            max_context_window = max(max_context_window, session.model_context_window)
        if session.thread_source == "subagent":
            subagents += 1
        if session.agent_role:
            roles.add(session.agent_role)
        compaction_timestamps.extend(
            timestamp.isoformat() for timestamp in session.compaction_timestamps
        )

    uncached_input_tokens = totals["input_tokens"] - totals["cached_input_tokens"]
    context_pct = None
    if max_context_window:
        context_pct = round((max_last_input_tokens / max_context_window) * 100, 1)

    return {
        **totals,
        "uncached_input_tokens": uncached_input_tokens,
        "compactions": compactions,
        "compaction_timestamps": compaction_timestamps,
        "token_events": token_events,
        "session_count": len(set(session_ids)),
        "subagent_session_count": subagents,
        "agent_roles": sorted(roles),
        "max_last_input_tokens": max_last_input_tokens,
        "model_context_window": max_context_window or None,
        "max_context_percent": context_pct,
    }


def attempt_to_dict(attempt: Attempt, sessions: dict[str, SessionTelemetry]) -> dict[str, Any]:
    token_summary = summarize_tokens(attempt.sessions, sessions)
    phase_rows = []
    for phase in attempt.phases.values():
        phase_end = phase.end or attempt.ended_at
        phase_rows.append(
            {
                "name": phase.name,
                "started_at": phase.start.isoformat() if phase.start else None,
                "ended_at": phase_end.isoformat() if phase_end else None,
                "duration_seconds": duration_seconds(phase.start, phase_end),
                "status": phase.status,
                "sessions": sorted(set(phase.sessions)),
                "tokens": summarize_tokens(phase.sessions, sessions),
            }
        )

    started_at = attempt.started_at
    ended_at = attempt.ended_at
    tokens_per_minute = None
    duration = duration_seconds(started_at, ended_at)
    if duration and duration > 0:
        tokens_per_minute = round(token_summary["total_tokens"] / (duration / 60), 1)

    return {
        "run_index": attempt.run_index,
        "iteration": attempt.iteration,
        "issue": attempt.issue,
        "selected_at": attempt.selected_at.isoformat(),
        "started_at": started_at.isoformat(),
        "ended_at": ended_at.isoformat() if ended_at else None,
        "duration_seconds": duration,
        "duration": format_duration(started_at, ended_at),
        "outcome": attempt.outcome,
        "reason": attempt.reason,
        "tokens_per_minute": tokens_per_minute,
        "sessions": sorted(set(attempt.sessions)),
        "tokens": token_summary,
        "phases": phase_rows,
        "log_files": attempt.log_files,
    }


def duration_seconds(start: datetime | None, end: datetime | None) -> int | None:
    if not start or not end:
        return None
    seconds = int((end - start).total_seconds())
    return seconds if seconds >= 0 else None


def build_report(
    artifacts_dir: Path,
    sessions_dir: Path,
    zone: ZoneInfo,
    since: datetime | None,
    until: datetime | None,
    issue_filter: int | None,
) -> dict[str, Any]:
    attempts = parse_activity(artifacts_dir / "activity.md", zone)
    if issue_filter:
        attempts = [attempt for attempt in attempts if attempt.issue == issue_filter]

    attach_log_files(attempts, artifacts_dir / "logs")
    sessions = parse_sessions(sessions_dir, attempts, zone, since, until)
    assign_sessions(attempts, sessions)

    attempt_rows = [attempt_to_dict(attempt, sessions) for attempt in attempts]
    issues: dict[str, Any] = {}
    for issue in sorted({attempt.issue for attempt in attempts}):
        issue_attempts = [attempt for attempt in attempts if attempt.issue == issue]
        session_ids = [session_id for attempt in issue_attempts for session_id in attempt.sessions]
        issues[str(issue)] = {
            "issue": issue,
            "attempt_count": len(issue_attempts),
            "last_outcome": issue_attempts[-1].outcome,
            "duration_seconds": sum(
                duration_seconds(attempt.started_at, attempt.ended_at) or 0
                for attempt in issue_attempts
            ),
            "tokens": summarize_tokens(session_ids, sessions),
            "attempts": [
                f"run {attempt.run_index} iter {attempt.iteration}" for attempt in issue_attempts
            ],
        }

    return {
        "artifacts_dir": str(artifacts_dir),
        "sessions_dir": str(sessions_dir),
        "generated_at": datetime.now(tz=zone).isoformat(),
        "activity_timezone": str(zone),
        "attempt_count": len(attempts),
        "issue_count": len(issues),
        "issues": issues,
        "attempts": attempt_rows,
        "unassigned_session_count": len(sessions)
        - len({session_id for attempt in attempts for session_id in attempt.sessions}),
    }


def render_text(report: dict[str, Any]) -> str:
    lines = [
        "Ralph Execution Report",
        f"artifacts: {report['artifacts_dir']}",
        f"sessions:  {report['sessions_dir']}",
        f"issues:    {report['issue_count']}",
        f"attempts:  {report['attempt_count']}",
        "",
        "Per issue",
        (
            "issue  attempts  outcome          duration  total_tokens  uncached_input  "
            "output  compactions  sessions  max_context"
        ),
    ]

    for issue_key, issue in sorted(report["issues"].items(), key=lambda item: int(item[0])):
        tokens = issue["tokens"]
        lines.append(
            f"#{issue_key:<5} "
            f"{issue['attempt_count']:<8} "
            f"{issue['last_outcome']:<16} "
            f"{format_seconds(issue['duration_seconds']):<9} "
            f"{tokens['total_tokens']:<13} "
            f"{tokens['uncached_input_tokens']:<14} "
            f"{tokens['output_tokens']:<7} "
            f"{tokens['compactions']:<11} "
            f"{tokens['session_count']:<8} "
            f"{tokens['max_context_percent'] or ''}"
        )

    lines.extend(["", "Attempts"])
    for attempt in report["attempts"]:
        tokens = attempt["tokens"]
        lines.append(
            f"run {attempt['run_index']} iter {attempt['iteration']} #"
            f"{attempt['issue']} {attempt['outcome']} {attempt['duration'] or ''} "
            f"tokens={tokens['total_tokens']} compactions={tokens['compactions']} "
            f"sessions={tokens['session_count']} roles={','.join(tokens['agent_roles']) or '-'}"
        )
        if attempt["reason"]:
            lines.append(f"  reason: {attempt['reason']}")
        for phase in attempt["phases"]:
            phase_tokens = phase["tokens"]
            lines.append(
                f"  {phase['name']}: {format_seconds(phase['duration_seconds'])} "
                f"tokens={phase_tokens['total_tokens']} "
                f"sessions={phase_tokens['session_count']}"
            )

    return "\n".join(lines)


def render_csv(report: dict[str, Any], output: Any) -> None:
    writer = csv.DictWriter(
        output,
        fieldnames=[
            "issue",
            "run_index",
            "iteration",
            "outcome",
            "started_at",
            "ended_at",
            "duration_seconds",
            "total_tokens",
            "input_tokens",
            "cached_input_tokens",
            "uncached_input_tokens",
            "output_tokens",
            "reasoning_output_tokens",
            "compactions",
            "session_count",
            "subagent_session_count",
            "max_last_input_tokens",
            "model_context_window",
            "max_context_percent",
            "tokens_per_minute",
            "agent_roles",
            "reason",
        ],
    )
    writer.writeheader()
    for attempt in report["attempts"]:
        tokens = attempt["tokens"]
        writer.writerow(
            {
                "issue": attempt["issue"],
                "run_index": attempt["run_index"],
                "iteration": attempt["iteration"],
                "outcome": attempt["outcome"],
                "started_at": attempt["started_at"],
                "ended_at": attempt["ended_at"],
                "duration_seconds": attempt["duration_seconds"],
                "total_tokens": tokens["total_tokens"],
                "input_tokens": tokens["input_tokens"],
                "cached_input_tokens": tokens["cached_input_tokens"],
                "uncached_input_tokens": tokens["uncached_input_tokens"],
                "output_tokens": tokens["output_tokens"],
                "reasoning_output_tokens": tokens["reasoning_output_tokens"],
                "compactions": tokens["compactions"],
                "session_count": tokens["session_count"],
                "subagent_session_count": tokens["subagent_session_count"],
                "max_last_input_tokens": tokens["max_last_input_tokens"],
                "model_context_window": tokens["model_context_window"],
                "max_context_percent": tokens["max_context_percent"],
                "tokens_per_minute": attempt["tokens_per_minute"],
                "agent_roles": ",".join(tokens["agent_roles"]),
                "reason": attempt["reason"],
            }
        )


def format_seconds(seconds: int | None) -> str:
    if seconds is None:
        return ""
    minutes, secs = divmod(seconds, 60)
    hours, minutes = divmod(minutes, 60)
    if hours:
        return f"{hours}h{minutes:02d}m"
    if minutes:
        return f"{minutes}m{secs:02d}s"
    return f"{secs}s"


def parse_optional_local_time(raw: str | None, zone: ZoneInfo) -> datetime | None:
    if not raw:
        return None
    try:
        return parse_iso_timestamp(raw, zone)
    except ValueError:
        return parse_local_timestamp(raw, zone)


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--artifacts-dir",
        type=Path,
        default=Path(__file__).resolve().parent / ".artifacts",
        help="Ralph artifacts directory. Default: ralph/.artifacts",
    )
    parser.add_argument(
        "--sessions-dir",
        type=Path,
        default=Path.home() / ".codex" / "sessions",
        help="Codex sessions directory. Default: ~/.codex/sessions",
    )
    parser.add_argument("--issue", type=int, help="Only report one issue number.")
    parser.add_argument(
        "--format",
        choices=("text", "json", "csv"),
        default="text",
        help="Output format. JSON includes raw per-attempt/session IDs.",
    )
    parser.add_argument(
        "--activity-timezone",
        default="America/New_York",
        help="Timezone for Ralph activity.md timestamps. Default: America/New_York",
    )
    parser.add_argument(
        "--since",
        help="Only inspect Codex sessions at or after this time. Accepts ISO or activity timestamp.",
    )
    parser.add_argument(
        "--until",
        help="Only inspect Codex sessions at or before this time. Accepts ISO or activity timestamp.",
    )
    args = parser.parse_args(argv)

    zone = ZoneInfo(args.activity_timezone)
    since = parse_optional_local_time(args.since, zone)
    until = parse_optional_local_time(args.until, zone)
    report = build_report(
        artifacts_dir=args.artifacts_dir,
        sessions_dir=args.sessions_dir,
        zone=zone,
        since=since,
        until=until,
        issue_filter=args.issue,
    )

    if args.format == "json":
        json.dump(report, sys.stdout, indent=2, sort_keys=True)
        sys.stdout.write("\n")
    elif args.format == "csv":
        render_csv(report, sys.stdout)
    else:
        sys.stdout.write(render_text(report))
        sys.stdout.write("\n")

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
