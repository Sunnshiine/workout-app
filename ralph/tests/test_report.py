from __future__ import annotations

import importlib.util
import json
import sys
import tempfile
import unittest
from pathlib import Path

REPORT_PATH = Path(__file__).resolve().parents[1] / "report.py"
SPEC = importlib.util.spec_from_file_location("ralph_report", REPORT_PATH)
assert SPEC and SPEC.loader
report = importlib.util.module_from_spec(SPEC)
sys.modules["ralph_report"] = report
SPEC.loader.exec_module(report)


class RalphReportTests(unittest.TestCase):
    def test_joins_activity_attempts_to_parent_and_subagent_sessions(self) -> None:
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            artifacts = root / "artifacts"
            logs = artifacts / "logs"
            sessions = root / "sessions" / "2026" / "06" / "01"
            logs.mkdir(parents=True)
            sessions.mkdir(parents=True)
            (artifacts / "activity.md").write_text(
                "\n".join(
                    [
                        "# Ralph Activity Log",
                        "",
                        "- **2026-06-01 21:10:32** — run start — engine=codex max-iter=20 push=1",
                        "- **2026-06-01 21:11:10** — iteration 1: selected issue #157",
                        (
                            "- **2026-06-01 21:11:10** — issue #157 implement-tdd "
                            "started — timeout 2700s"
                        ),
                        "- **2026-06-01 21:20:11** — issue #157 implement-tdd complete",
                        (
                            "- **2026-06-01 21:20:11** — issue #157 review "
                            "started — timeout 2700s"
                        ),
                        "- **2026-06-01 21:25:12** — issue #157 review complete",
                        "- **2026-06-01 21:46:23** — issue #157 resolved & merged to main, pushed",
                    ]
                ),
                encoding="utf-8",
            )
            (logs / "iter-1-issue-157-implement-tdd.log").write_text("ok", encoding="utf-8")

            write_jsonl(
                sessions / "rollout-parent.jsonl",
                [
                    session_meta(
                        "parent",
                        "2026-06-02T01:20:11.000Z",
                        "/repo/.claude/worktrees/issue-157",
                    ),
                    token_count("2026-06-02T01:20:12.000Z", 100, 60, 10, 3, 110, 90),
                ],
            )
            write_jsonl(
                sessions / "rollout-subagent.jsonl",
                [
                    session_meta(
                        "child",
                        "2026-06-02T01:21:11.000Z",
                        "/repo/.claude/worktrees/issue-157",
                        role="swift-reviewer",
                        parent="parent",
                    ),
                    token_count("2026-06-02T01:21:12.000Z", 200, 120, 20, 6, 220, 180),
                    {
                        "timestamp": "2026-06-02T01:21:13.000Z",
                        "type": "event_msg",
                        "payload": {"type": "context_compacted"},
                    },
                ],
            )
            write_jsonl(
                sessions / "rollout-spec-subagent.jsonl",
                [
                    session_meta(
                        "spec-child",
                        "2026-06-02T01:22:11.000Z",
                        "/repo/.claude/worktrees/issue-157",
                        role="spec-conformance-reviewer",
                        parent="parent",
                    ),
                    token_count("2026-06-02T01:22:12.000Z", 50, 20, 5, 0, 55, 45),
                ],
            )

            data = report.build_report(
                artifacts,
                root / "sessions",
                report.ZoneInfo("America/New_York"),
                None,
                None,
                None,
            )

        attempt = data["attempts"][0]
        self.assertEqual(attempt["issue"], 157)
        self.assertEqual(attempt["tokens"]["total_tokens"], 385)
        self.assertEqual(attempt["tokens"]["uncached_input_tokens"], 150)
        self.assertEqual(attempt["tokens"]["compactions"], 1)
        self.assertEqual(attempt["tokens"]["subagent_session_count"], 2)
        self.assertEqual(
            attempt["tokens"]["agent_roles"],
            ["spec-conformance-reviewer", "swift-reviewer"],
        )
        self.assertEqual(attempt["phases"][2]["name"], "review")
        self.assertIn("child", attempt["phases"][2]["sessions"])
        self.assertIn("spec-child", attempt["phases"][2]["sessions"])

    def test_historical_swift_review_phase_remains_readable(self) -> None:
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            artifacts = root / "artifacts"
            artifacts.mkdir(parents=True)
            (artifacts / "activity.md").write_text(
                "\n".join(
                    [
                        "- **2026-06-01 21:10:00** — iteration 1: selected issue #99",
                        "- **2026-06-01 21:11:00** — issue #99 swift-review started",
                        "- **2026-06-01 21:12:00** — issue #99 swift-review complete",
                    ]
                ),
                encoding="utf-8",
            )

            data = report.build_report(
                artifacts,
                root / "sessions",
                report.ZoneInfo("America/New_York"),
                None,
                None,
                None,
            )

        phase_names = [phase["name"] for phase in data["attempts"][0]["phases"]]
        self.assertIn("swift-review", phase_names)


def write_jsonl(path: Path, rows: list[dict]) -> None:
    path.write_text("\n".join(json.dumps(row) for row in rows), encoding="utf-8")


def session_meta(
    session_id: str,
    timestamp: str,
    cwd: str,
    role: str | None = None,
    parent: str | None = None,
) -> dict:
    payload = {
        "id": session_id,
        "timestamp": timestamp,
        "cwd": cwd,
        "thread_source": "subagent" if parent else "user",
        "source": "exec",
    }
    if parent:
        payload["agent_role"] = role
        payload["source"] = {
            "subagent": {
                "thread_spawn": {
                    "parent_thread_id": parent,
                    "agent_role": role,
                    "depth": 1,
                }
            }
        }
    return {"timestamp": timestamp, "type": "session_meta", "payload": payload}


def token_count(
    timestamp: str,
    input_tokens: int,
    cached_input_tokens: int,
    output_tokens: int,
    reasoning_output_tokens: int,
    total_tokens: int,
    last_input_tokens: int,
) -> dict:
    return {
        "timestamp": timestamp,
        "type": "event_msg",
        "payload": {
            "type": "token_count",
            "info": {
                "total_token_usage": {
                    "input_tokens": input_tokens,
                    "cached_input_tokens": cached_input_tokens,
                    "output_tokens": output_tokens,
                    "reasoning_output_tokens": reasoning_output_tokens,
                    "total_tokens": total_tokens,
                },
                "last_token_usage": {"input_tokens": last_input_tokens},
                "model_context_window": 258400,
            },
        },
    }


if __name__ == "__main__":
    unittest.main()
