#!/usr/bin/env python3
"""Generate a static HTML dashboard from Ralph session report data."""

from __future__ import annotations

import argparse
import json
import statistics
import subprocess
import sys
from datetime import datetime, timezone
from pathlib import Path


def run_report(artifacts_dir: str, sessions_dir: str | None = None) -> dict:
    cmd = [
        "uv", "run", "--python", "3.11", "python",
        "ralph/report.py",
        "--artifacts-dir", artifacts_dir,
        "--format", "json",
    ]
    if sessions_dir:
        cmd += ["--sessions-dir", sessions_dir]
    env = {"UV_CACHE_DIR": "/private/tmp/uv-cache", "PATH": __import__("os").environ["PATH"]}
    result = subprocess.run(cmd, capture_output=True, text=True, env=env)
    if result.returncode != 0:
        print(result.stderr, file=sys.stderr)
        sys.exit(1)
    return json.loads(result.stdout)


def fmt_tokens(n: int) -> str:
    if n >= 1_000_000:
        return f"{n / 1_000_000:.1f}M"
    if n >= 1_000:
        return f"{n / 1_000:.0f}K"
    return str(n)


def fmt_dur(s: int) -> str:
    if s == 0:
        return "—"
    h = s // 3600
    m = (s % 3600) // 60
    sec = s % 60
    if h:
        return f"{h}h {m}m"
    if m:
        return f"{m}m {sec}s"
    return f"{sec}s"


def badge_phases(phases: list[dict]) -> str:
    names = [p["name"] for p in phases]
    short = {"select": "sel", "implement": "impl", "implement-tdd": "tdd",
             "swift-review": "rev", "ui-verify": "ui"}
    return " ".join(f'<span class="phase-chip">{short.get(n, n)}</span>' for n in names)


def badge_roles(roles: list[str]) -> str:
    short = {"swift-reviewer": "swift", "ui-screenshot-reviewer": "ui"}
    if not roles:
        return '<span class="muted">—</span>'
    return " ".join(f'<span class="role-chip">{short.get(r, r)}</span>' for r in sorted(set(roles)))


def ctx_class(pct: float) -> str:
    if pct >= 90:
        return "ctx-danger"
    if pct >= 70:
        return "ctx-warn"
    return ""


def outcome_class(outcome: str) -> str:
    return {"resolved": "resolved", "ready-for-human": "human", "incomplete": "incomplete"}.get(outcome, "")


def escape(s: str) -> str:
    return s.replace("&", "&amp;").replace("<", "&lt;").replace(">", "&gt;").replace('"', "&quot;")


def build_html(data: dict, generated_at: str) -> str:
    attempts = data["attempts"]
    resolved = [a for a in attempts if a["outcome"] == "resolved"]
    ready = [a for a in attempts if a["outcome"] == "ready-for-human"]
    incomplete = [a for a in attempts if a["outcome"] == "incomplete"]
    not_afk = ready + incomplete

    total_tokens = sum(a["tokens"]["total_tokens"] for a in attempts)
    total_compactions = sum(a["tokens"]["compactions"] for a in attempts)
    durations = [a["duration_seconds"] for a in attempts if a["duration_seconds"] > 0]
    med_dur = int(statistics.median(durations)) if durations else 0

    # Phase totals
    phase_totals: dict[str, dict] = {}
    for a in attempts:
        for p in a.get("phases", []):
            n = p["name"]
            if n not in phase_totals:
                phase_totals[n] = {"count": 0, "dur": 0, "tokens": 0}
            phase_totals[n]["count"] += 1
            phase_totals[n]["dur"] += p["duration_seconds"]
            phase_totals[n]["tokens"] += p["tokens"]["total_tokens"]

    # Outliers
    top_tokens = sorted(attempts, key=lambda a: a["tokens"]["total_tokens"], reverse=True)[:5]
    top_dur = sorted(attempts, key=lambda a: a["duration_seconds"], reverse=True)[:5]
    top_ctx = sorted(attempts, key=lambda a: a["tokens"]["max_context_percent"], reverse=True)[:5]
    top_compactions = sorted(attempts, key=lambda a: a["tokens"]["compactions"], reverse=True)[:5]

    # Build resolved rows
    resolved_rows = []
    for a in sorted(resolved, key=lambda x: x["issue"]):
        tok = a["tokens"]
        phases_html = badge_phases(a.get("phases", []))
        roles_html = badge_roles(tok.get("agent_roles", []))
        cc = ctx_class(tok["max_context_percent"])
        resolved_rows.append(f"""
        <tr>
          <td class="num">#{a['issue']}</td>
          <td class="num">{a['iteration']}</td>
          <td>{a['duration']}</td>
          <td class="num">{fmt_tokens(tok['total_tokens'])}</td>
          <td class="num">{fmt_tokens(tok['uncached_input_tokens'])}</td>
          <td class="num {cc}">{tok['max_context_percent']}%</td>
          <td class="num">{tok['compactions'] or '—'}</td>
          <td class="num">{tok['session_count']}</td>
          <td>{phases_html}</td>
          <td>{roles_html}</td>
        </tr>""")

    # Build not-afk rows
    not_afk_rows = []
    for a in sorted(not_afk, key=lambda x: (x["issue"], x["iteration"])):
        tok = a["tokens"]
        reason = escape(a.get("reason", "") or "")
        reason_short = reason[:100] + ("…" if len(reason) > 100 else "")
        oc = outcome_class(a["outcome"])
        label = {"ready-for-human": "human", "incomplete": "incomplete"}.get(a["outcome"], a["outcome"])
        not_afk_rows.append(f"""
        <tr>
          <td class="num">#{a['issue']}</td>
          <td class="num">{a['iteration']}</td>
          <td><span class="badge {oc}">{label}</span></td>
          <td>{a['duration'] if a['duration_seconds'] else '—'}</td>
          <td class="num">{fmt_tokens(tok['total_tokens'])}</td>
          <td class="reason">{reason_short or '<span class="muted">—</span>'}</td>
        </tr>""")

    # Build outlier rows helper
    def outlier_row(a: dict, metric: str) -> str:
        tok = a["tokens"]
        oc = outcome_class(a["outcome"])
        label = {"resolved": "✓", "ready-for-human": "human", "incomplete": "—"}.get(a["outcome"], "")
        if metric == "tokens":
            val = fmt_tokens(tok["total_tokens"])
        elif metric == "dur":
            val = a["duration"]
        elif metric == "ctx":
            val = f"{tok['max_context_percent']}%"
        else:
            val = str(tok["compactions"])
        return f'<tr><td class="num">#{a["issue"]} iter {a["iteration"]}</td><td class="num">{val}</td><td><span class="badge {oc}">{label}</span></td></tr>'

    # Phase table rows
    phase_order = ["select", "implement", "implement-tdd", "swift-review", "ui-verify"]
    phase_label = {"select": "select", "implement": "implement (mono)", "implement-tdd": "implement-tdd",
                   "swift-review": "swift-review", "ui-verify": "ui-verify"}
    phase_rows = []
    for name in phase_order:
        if name not in phase_totals:
            continue
        s = phase_totals[name]
        phase_rows.append(f"""
        <tr>
          <td>{phase_label.get(name, name)}</td>
          <td class="num">{s['count']}</td>
          <td>{fmt_dur(s['dur'])}</td>
          <td class="num">{fmt_tokens(s['tokens'])}</td>
          <td class="num">{fmt_tokens(s['tokens'] // s['count']) if s['count'] else '—'}</td>
        </tr>""")

    resolve_rate = round(len(resolved) / len(attempts) * 100, 1)

    return f"""<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>Ralph Session Dashboard</title>
<style>
  *, *::before, *::after {{ box-sizing: border-box; margin: 0; padding: 0; }}

  :root {{
    --bg: #050806;
    --bg2: #060E0A;
    --bg3: #081A12;
    --surface: #080F0D;
    --card: #08331F;
    --stroke: #215C40;
    --stroke-active: #3BD17A;
    --mint: #73FFB8;
    --text: #F5F7F3;
    --muted: #AAB8B0;
    --danger: #FF3B30;
    --warn: #FF9500;
    --human: #0A84FF;
    --radius-card: 12px;
    --radius-sm: 6px;
    --font: -apple-system, BlinkMacSystemFont, "SF Pro Text", "Segoe UI", system-ui, sans-serif;
    --font-mono: "SF Mono", "Fira Code", "Cascadia Code", ui-monospace, monospace;
  }}

  html, body {{
    background: var(--bg);
    color: var(--text);
    font-family: var(--font);
    font-size: 13px;
    line-height: 1.4;
    min-height: 100vh;
  }}

  .page {{
    max-width: 1200px;
    margin: 0 auto;
    padding: 28px 20px 64px;
  }}

  /* ─── header ─── */
  .header {{
    border-bottom: 1px solid var(--stroke);
    padding-bottom: 16px;
    margin-bottom: 24px;
    display: flex;
    align-items: baseline;
    gap: 12px;
    flex-wrap: wrap;
  }}
  .header h1 {{
    font-size: 17px;
    font-weight: 700;
    color: var(--text);
    letter-spacing: -0.01em;
  }}
  .header-meta {{
    font-size: 11px;
    color: var(--muted);
    margin-left: auto;
  }}

  /* ─── summary bar ─── */
  .summary {{
    display: flex;
    gap: 1px;
    background: var(--stroke);
    border: 1px solid var(--stroke);
    border-radius: var(--radius-card);
    overflow: hidden;
    margin-bottom: 28px;
  }}
  .stat {{
    flex: 1;
    background: var(--bg2);
    padding: 12px 14px;
    display: flex;
    flex-direction: column;
    gap: 3px;
    min-width: 80px;
  }}
  .stat-val {{
    font-size: 17px;
    font-weight: 700;
    line-height: 1;
    color: var(--text);
    font-variant-numeric: tabular-nums;
  }}
  .stat-val.accent {{ color: var(--mint); }}
  .stat-val.human-color {{ color: var(--human); }}
  .stat-val.warn {{ color: var(--warn); }}
  .stat-label {{
    font-size: 10px;
    font-weight: 600;
    color: var(--muted);
    text-transform: uppercase;
    letter-spacing: 0.04em;
  }}

  /* ─── sections ─── */
  .section {{
    margin-bottom: 32px;
  }}
  .section-title {{
    font-size: 11px;
    font-weight: 700;
    color: var(--muted);
    text-transform: uppercase;
    letter-spacing: 0.06em;
    margin-bottom: 10px;
    display: flex;
    align-items: center;
    gap: 8px;
  }}
  .section-title .count {{
    background: var(--bg3);
    border: 1px solid var(--stroke);
    border-radius: 99px;
    padding: 1px 7px;
    font-size: 10px;
    color: var(--muted);
    font-weight: 600;
  }}
  .section-title .count.resolved {{ border-color: var(--stroke-active); color: var(--mint); }}

  /* ─── tables ─── */
  .table-wrap {{
    overflow-x: auto;
    border-radius: var(--radius-card);
    border: 1px solid var(--stroke);
  }}
  table {{
    width: 100%;
    border-collapse: collapse;
    font-size: 12px;
  }}
  thead th {{
    background: var(--bg2);
    color: var(--muted);
    font-size: 10px;
    font-weight: 700;
    text-transform: uppercase;
    letter-spacing: 0.05em;
    padding: 8px 10px;
    text-align: left;
    border-bottom: 1px solid var(--stroke);
    white-space: nowrap;
    position: sticky;
    top: 0;
  }}
  thead th.num {{ text-align: right; }}
  tbody tr {{
    border-bottom: 1px solid var(--bg3);
    transition: background 120ms ease;
  }}
  tbody tr:last-child {{ border-bottom: none; }}
  tbody tr:hover {{ background: var(--bg3); }}
  tbody td {{
    padding: 7px 10px;
    vertical-align: middle;
    color: var(--text);
    font-variant-numeric: tabular-nums;
    white-space: nowrap;
  }}
  td.num {{ text-align: right; font-family: var(--font-mono); font-size: 11px; }}
  td.reason {{
    white-space: normal;
    max-width: 360px;
    color: var(--muted);
    font-size: 11px;
  }}
  td.ctx-danger {{ color: var(--danger); }}
  td.ctx-warn {{ color: var(--warn); }}
  .muted {{ color: var(--muted); }}

  /* ─── chips ─── */
  .phase-chip, .role-chip {{
    display: inline-block;
    background: var(--bg3);
    border: 1px solid var(--stroke);
    border-radius: 4px;
    padding: 1px 5px;
    font-size: 10px;
    font-weight: 600;
    color: var(--muted);
    margin-right: 2px;
    font-family: var(--font-mono);
  }}
  .role-chip {{ border-color: #3BD17A44; color: #73FFB880; }}

  /* ─── badges ─── */
  .badge {{
    display: inline-block;
    border-radius: 4px;
    padding: 2px 6px;
    font-size: 10px;
    font-weight: 700;
    text-transform: uppercase;
    letter-spacing: 0.04em;
  }}
  .badge.resolved {{ background: #08331F; color: var(--mint); border: 1px solid var(--stroke-active); }}
  .badge.human {{ background: #001829; color: var(--human); border: 1px solid #0A84FF44; }}
  .badge.incomplete {{ background: var(--bg3); color: var(--muted); border: 1px solid var(--stroke); }}

  /* ─── outliers grid ─── */
  .outlier-grid {{
    display: grid;
    grid-template-columns: repeat(auto-fit, minmax(240px, 1fr));
    gap: 12px;
  }}
  .outlier-card {{
    background: var(--bg2);
    border: 1px solid var(--stroke);
    border-radius: var(--radius-card);
    overflow: hidden;
  }}
  .outlier-card-head {{
    padding: 8px 12px;
    border-bottom: 1px solid var(--stroke);
    font-size: 10px;
    font-weight: 700;
    text-transform: uppercase;
    letter-spacing: 0.05em;
    color: var(--muted);
    background: var(--bg3);
  }}
  .outlier-card table {{ font-size: 11px; }}
  .outlier-card tbody td {{ padding: 5px 10px; }}

  /* ─── caveats ─── */
  .caveats {{
    background: var(--bg2);
    border: 1px solid var(--stroke);
    border-radius: var(--radius-card);
    padding: 12px 16px;
    margin-top: 32px;
  }}
  .caveats-title {{
    font-size: 10px;
    font-weight: 700;
    text-transform: uppercase;
    letter-spacing: 0.05em;
    color: var(--muted);
    margin-bottom: 8px;
  }}
  .caveats ul {{
    list-style: none;
    display: flex;
    flex-direction: column;
    gap: 4px;
  }}
  .caveats li {{
    font-size: 11px;
    color: var(--muted);
    padding-left: 12px;
    position: relative;
  }}
  .caveats li::before {{
    content: "–";
    position: absolute;
    left: 0;
  }}

  @media (max-width: 640px) {{
    .summary {{ flex-wrap: wrap; }}
    .stat {{ min-width: calc(33% - 1px); }}
  }}

  @media (prefers-reduced-motion: reduce) {{
    tbody tr {{ transition: none; }}
  }}
</style>
</head>
<body>
<div class="page">

  <header class="header">
    <h1>Ralph Session Dashboard</h1>
    <span class="header-meta">Generated {generated_at} &middot; {data['artifacts_dir']}</span>
  </header>

  <div class="summary">
    <div class="stat">
      <span class="stat-val accent">{len(resolved)}</span>
      <span class="stat-label">AFK Solved</span>
    </div>
    <div class="stat">
      <span class="stat-val">{len(attempts)}</span>
      <span class="stat-label">Total Attempts</span>
    </div>
    <div class="stat">
      <span class="stat-val">{data['issue_count']}</span>
      <span class="stat-label">Unique Issues</span>
    </div>
    <div class="stat">
      <span class="stat-val human-color">{len(ready)}</span>
      <span class="stat-label">Needs Human</span>
    </div>
    <div class="stat">
      <span class="stat-val warn">{len(incomplete)}</span>
      <span class="stat-label">Incomplete</span>
    </div>
    <div class="stat">
      <span class="stat-val">{fmt_tokens(total_tokens)}</span>
      <span class="stat-label">Total Tokens</span>
    </div>
    <div class="stat">
      <span class="stat-val">{total_compactions}</span>
      <span class="stat-label">Compactions</span>
    </div>
    <div class="stat">
      <span class="stat-val">{fmt_dur(med_dur)}</span>
      <span class="stat-label">Median Duration</span>
    </div>
    <div class="stat">
      <span class="stat-val accent">{resolve_rate}%</span>
      <span class="stat-label">Solve Rate</span>
    </div>
  </div>

  <!-- AFK Solved -->
  <section class="section">
    <div class="section-title">
      AFK Solved
      <span class="count resolved">{len(resolved)}</span>
    </div>
    <div class="table-wrap">
      <table>
        <thead>
          <tr>
            <th>Issue</th>
            <th>Iter</th>
            <th>Duration</th>
            <th class="num">Tokens</th>
            <th class="num">Uncached</th>
            <th class="num">Max Ctx</th>
            <th class="num">Compact</th>
            <th class="num">Sessions</th>
            <th>Phases</th>
            <th>Reviewers</th>
          </tr>
        </thead>
        <tbody>
          {''.join(resolved_rows)}
        </tbody>
      </table>
    </div>
  </section>

  <!-- Needs Human -->
  <section class="section">
    <div class="section-title">
      Needs Human
      <span class="count">{len(not_afk)}</span>
    </div>
    <div class="table-wrap">
      <table>
        <thead>
          <tr>
            <th>Issue</th>
            <th>Iter</th>
            <th>Outcome</th>
            <th>Duration</th>
            <th class="num">Tokens</th>
            <th>Reason</th>
          </tr>
        </thead>
        <tbody>
          {''.join(not_afk_rows)}
        </tbody>
      </table>
    </div>
  </section>

  <!-- Phase Analysis -->
  <section class="section">
    <div class="section-title">Phase Analysis</div>
    <div class="table-wrap">
      <table>
        <thead>
          <tr>
            <th>Phase</th>
            <th class="num">Runs</th>
            <th>Total Duration</th>
            <th class="num">Total Tokens</th>
            <th class="num">Avg Tokens/Run</th>
          </tr>
        </thead>
        <tbody>
          {''.join(phase_rows)}
        </tbody>
      </table>
    </div>
  </section>

  <!-- Outliers -->
  <section class="section">
    <div class="section-title">Outliers</div>
    <div class="outlier-grid">
      <div class="outlier-card">
        <div class="outlier-card-head">Top Tokens</div>
        <table>
          <tbody>
            {''.join(outlier_row(a, 'tokens') for a in top_tokens)}
          </tbody>
        </table>
      </div>
      <div class="outlier-card">
        <div class="outlier-card-head">Longest Runs</div>
        <table>
          <tbody>
            {''.join(outlier_row(a, 'dur') for a in top_dur)}
          </tbody>
        </table>
      </div>
      <div class="outlier-card">
        <div class="outlier-card-head">Max Context %</div>
        <table>
          <tbody>
            {''.join(outlier_row(a, 'ctx') for a in top_ctx)}
          </tbody>
        </table>
      </div>
      <div class="outlier-card">
        <div class="outlier-card-head">Most Compactions</div>
        <table>
          <tbody>
            {''.join(outlier_row(a, 'compact') for a in top_compactions)}
          </tbody>
        </table>
      </div>
    </div>
  </section>

  <div class="caveats">
    <div class="caveats-title">Notes</div>
    <ul>
      <li>Report covers local artifacts only; attempts on other machines are not reflected.</li>
      <li>Shell and Xcode gate time is included in duration but not in token telemetry.</li>
      <li>Incomplete attempts with no terminal activity log event show zero duration.</li>
      <li>Older monolithic runs use a single "implement" phase; split-loop runs use select / implement-tdd / swift-review / ui-verify.</li>
      <li>Max context % is the highest recorded single-turn input for any session within the attempt.</li>
    </ul>
  </div>

</div>
</body>
</html>"""


def main() -> None:
    parser = argparse.ArgumentParser(description="Generate Ralph session HTML dashboard.")
    parser.add_argument("--artifacts-dir", default="ralph/.artifacts", help="Ralph artifacts directory.")
    parser.add_argument("--sessions-dir", default=None, help="Codex sessions directory.")
    parser.add_argument("--output", default="ralph/reports/ralph-session-dashboard.html")
    args = parser.parse_args()

    print(f"Running ralph/report.py against {args.artifacts_dir} ...", file=sys.stderr)
    data = run_report(args.artifacts_dir, args.sessions_dir)

    generated_at = datetime.now(timezone.utc).strftime("%Y-%m-%d %H:%M UTC")
    html = build_html(data, generated_at)

    out = Path(args.output)
    out.parent.mkdir(parents=True, exist_ok=True)
    out.write_text(html, encoding="utf-8")
    print(f"Dashboard written to {out}", file=sys.stderr)
    print(str(out))


if __name__ == "__main__":
    main()
