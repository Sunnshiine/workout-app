#!/usr/bin/env python3
"""Generate a static HTML dashboard from Ralph session report data."""

from __future__ import annotations

import argparse
import json
import statistics
import subprocess
import sys
from datetime import UTC, datetime
from pathlib import Path


def run_report(artifacts_dir: str, sessions_dir: str | None = None) -> dict:
    cmd = [
        "uv",
        "run",
        "--python",
        "3.11",
        "python",
        "ralph/report.py",
        "--artifacts-dir",
        artifacts_dir,
        "--format",
        "json",
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
    short = {
        "select": "sel",
        "implement": "impl",
        "implement-tdd": "tdd",
        "swift-review": "rev",
        "ui-verify": "ui",
    }
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
    return {"resolved": "resolved", "ready-for-human": "human", "incomplete": "incomplete"}.get(
        outcome, ""
    )


def escape(s: str) -> str:
    return s.replace("&", "&amp;").replace("<", "&lt;").replace(">", "&gt;").replace('"', "&quot;")


# ── Inline CSS additions (sortable headers + charts) ──────────────────────────

_CSS_EXTRA = """
  /* ─── sortable headers ─── */
  thead th { cursor: pointer; user-select: none; }
  thead th::after { content: ''; display: inline-block; width: 14px; }
  thead th[data-sort="asc"]::after { content: ' ▲'; color: var(--mint); font-size: 8px; }
  thead th[data-sort="desc"]::after { content: ' ▼'; color: var(--mint); font-size: 8px; }
  thead th:hover { color: var(--text); }

  /* ─── chart layout ─── */
  .charts-grid {
    display: grid;
    grid-template-columns: 1fr 1fr;
    gap: 12px;
  }
  .chart-full { grid-column: 1 / -1; }
  .chart-card {
    background: var(--bg2);
    border: 1px solid var(--stroke);
    border-radius: var(--radius-card);
    overflow: hidden;
  }
  .chart-head {
    padding: 8px 12px;
    border-bottom: 1px solid var(--stroke);
    font-size: 10px;
    font-weight: 700;
    text-transform: uppercase;
    letter-spacing: 0.05em;
    color: var(--muted);
    background: var(--bg3);
    display: flex;
    align-items: center;
    gap: 10px;
  }
  .chart-legend {
    display: flex;
    gap: 12px;
    margin-left: auto;
  }
  .chart-legend-item {
    display: flex;
    align-items: center;
    gap: 4px;
    font-size: 9px;
    color: var(--muted);
    font-family: var(--font-mono);
    font-weight: 500;
  }
  .legend-swatch {
    width: 8px;
    height: 8px;
    border-radius: 2px;
    flex-shrink: 0;
  }
  canvas { display: block; width: 100%; }
  #chart-tokens  { height: 260px; }
  #chart-iters   { height: 240px; }
  #chart-scatter { height: 240px; }
  .chart-tooltip {
    position: fixed;
    background: var(--bg2);
    border: 1px solid var(--stroke-active);
    border-radius: var(--radius-sm);
    padding: 6px 10px;
    font-size: 11px;
    color: var(--text);
    font-family: var(--font-mono);
    pointer-events: none;
    display: none;
    z-index: 100;
    white-space: nowrap;
    line-height: 1.6;
  }
  @media (max-width: 720px) {
    .charts-grid { grid-template-columns: 1fr; }
    .chart-full  { grid-column: 1; }
  }
"""

# ── Inline JavaScript (table sorting + canvas charts) ─────────────────────────
# Uses __CHART_DATA__ as a placeholder; replaced with JSON before embedding.

_JS_TEMPLATE = """
(function () {
  'use strict';

  const DATA = __CHART_DATA__;

  const C = {
    bg2: '#060E0A', bg3: '#081A12', stroke: '#215C40',
    mint: '#73FFB8', muted: '#AAB8B0', blue: '#0A84FF', text: '#F5F7F3'
  };

  function outcomeColor(o) {
    return o === 'resolved' ? C.mint : o === 'ready-for-human' ? C.blue : C.muted;
  }

  function fmtTok(n) {
    if (n >= 1e6) return (n / 1e6).toFixed(1) + 'M';
    if (n >= 1e3) return Math.round(n / 1e3) + 'K';
    return String(n);
  }

  function fmtDur(s) {
    if (!s) return '—';
    const h = Math.floor(s / 3600), m = Math.floor((s % 3600) / 60), sec = s % 60;
    if (h) return h + 'h ' + m + 'm';
    if (m) return m + 'm ' + sec + 's';
    return sec + 's';
  }

  function setupCanvas(id) {
    const cv = document.getElementById(id);
    if (!cv) return null;
    const dpr = window.devicePixelRatio || 1;
    const rect = cv.getBoundingClientRect();
    if (!rect.width) return null;
    cv.width = Math.round(rect.width * dpr);
    cv.height = Math.round(rect.height * dpr);
    const ctx = cv.getContext('2d');
    ctx.scale(dpr, dpr);
    return { ctx, W: rect.width, H: rect.height };
  }

  // ── Token consumption bar chart ──────────────────────────────────────────
  function drawTokens() {
    const r = setupCanvas('chart-tokens');
    if (!r) return;
    const { ctx, W, H } = r;
    const pad = { t: 20, r: 12, b: 40, l: 56 };
    const cW = W - pad.l - pad.r, cH = H - pad.t - pad.b;
    const pts = [...DATA.attempts].sort((a, b) => a.issue - b.issue || a.iteration - b.iteration);
    const maxT = Math.max(...pts.map(a => a.total_tokens));

    ctx.fillStyle = C.bg2; ctx.fillRect(0, 0, W, H);

    ctx.font = '9px SF Mono, ui-monospace, monospace';
    for (let i = 0; i <= 4; i++) {
      const y = pad.t + cH * (1 - i / 4);
      ctx.strokeStyle = C.stroke + '55'; ctx.lineWidth = 0.5;
      ctx.beginPath(); ctx.moveTo(pad.l, y); ctx.lineTo(pad.l + cW, y); ctx.stroke();
      ctx.fillStyle = C.muted; ctx.textAlign = 'right';
      ctx.fillText(fmtTok(maxT * i / 4), pad.l - 4, y + 3);
    }

    const slotW = cW / pts.length;
    const barW = Math.max(1.5, slotW * 0.82);
    pts.forEach((a, i) => {
      const x = pad.l + slotW * i + (slotW - barW) / 2;
      const bH = (a.total_tokens / maxT) * cH;
      ctx.fillStyle = outcomeColor(a.outcome); ctx.globalAlpha = 0.82;
      ctx.fillRect(x, pad.t + cH - bH, barW, bH);
    });
    ctx.globalAlpha = 1;

    const step = Math.max(1, Math.floor(pts.length / 14));
    ctx.fillStyle = C.muted; ctx.textAlign = 'center';
    ctx.font = '9px SF Mono, ui-monospace, monospace';
    pts.forEach((a, i) => {
      if (i % step === 0)
        ctx.fillText('#' + a.issue, pad.l + slotW * i + slotW / 2, H - pad.b + 14);
    });

    ctx.strokeStyle = C.stroke; ctx.lineWidth = 1;
    ctx.beginPath(); ctx.moveTo(pad.l, pad.t); ctx.lineTo(pad.l, pad.t + cH); ctx.lineTo(pad.l + cW, pad.t + cH); ctx.stroke();
  }

  // ── Iteration depth stacked bar chart ────────────────────────────────────
  function drawIterations() {
    const r = setupCanvas('chart-iters');
    if (!r) return;
    const { ctx, W, H } = r;
    const pad = { t: 24, r: 20, b: 44, l: 44 };
    const cW = W - pad.l - pad.r, cH = H - pad.t - pad.b;

    const maxIter = Math.max(...DATA.attempts.map(a => a.iteration));
    const buckets = {};
    for (let i = 1; i <= maxIter; i++) buckets[i] = { res: 0, hum: 0, inc: 0 };
    DATA.attempts.forEach(a => {
      const b = buckets[a.iteration];
      if (a.outcome === 'resolved') b.res++;
      else if (a.outcome === 'ready-for-human') b.hum++;
      else b.inc++;
    });

    const allTotals = Object.values(buckets).map(b => b.res + b.hum + b.inc);
    const gridMax = Math.ceil(Math.max(...allTotals) / 5) * 5 || 5;

    ctx.fillStyle = C.bg2; ctx.fillRect(0, 0, W, H);
    ctx.font = '9px SF Mono, ui-monospace, monospace';
    for (let i = 0; i <= 4; i++) {
      const y = pad.t + cH * (1 - i / 4);
      ctx.strokeStyle = C.stroke + '55'; ctx.lineWidth = 0.5;
      ctx.beginPath(); ctx.moveTo(pad.l, y); ctx.lineTo(pad.l + cW, y); ctx.stroke();
      ctx.fillStyle = C.muted; ctx.textAlign = 'right';
      ctx.fillText(Math.round(gridMax * i / 4), pad.l - 4, y + 3);
    }

    const iters = Object.keys(buckets).map(Number).sort((a, b) => a - b);
    const slotW = cW / iters.length;
    const barW = Math.min(52, Math.max(18, slotW * 0.62));

    iters.forEach((iter, i) => {
      const x = pad.l + slotW * i + (slotW - barW) / 2;
      const b = buckets[iter];
      const total = b.res + b.hum + b.inc;
      let yBase = pad.t + cH;

      [[b.res, C.mint, 0.85], [b.hum, C.blue, 0.8], [b.inc, C.muted, 0.55]].forEach(([n, col, alpha]) => {
        if (!n) return;
        const bH = (n / gridMax) * cH;
        yBase -= bH;
        ctx.fillStyle = col; ctx.globalAlpha = alpha;
        ctx.fillRect(x, yBase, barW, bH);
      });
      ctx.globalAlpha = 1;

      ctx.fillStyle = C.muted; ctx.textAlign = 'center';
      ctx.font = '9px SF Mono, ui-monospace, monospace';
      ctx.fillText('iter ' + iter, x + barW / 2, pad.t + cH + 14);

      if (total > 0) {
        const topY = pad.t + cH - (total / gridMax) * cH;
        ctx.fillStyle = C.text;
        ctx.font = 'bold 10px SF Mono, ui-monospace, monospace';
        ctx.fillText(total, x + barW / 2, topY - 5);
      }
    });

    ctx.strokeStyle = C.stroke; ctx.lineWidth = 1;
    ctx.beginPath(); ctx.moveTo(pad.l, pad.t); ctx.lineTo(pad.l, pad.t + cH); ctx.lineTo(pad.l + cW, pad.t + cH); ctx.stroke();
  }

  // ── Duration vs Tokens scatter ────────────────────────────────────────────
  function drawScatter() {
    const r = setupCanvas('chart-scatter');
    if (!r) return;
    const { ctx, W, H } = r;
    const pad = { t: 20, r: 20, b: 44, l: 56 };
    const cW = W - pad.l - pad.r, cH = H - pad.t - pad.b;
    const pts = DATA.attempts.filter(a => a.duration_seconds > 0);
    if (!pts.length) return;
    const maxD = Math.max(...pts.map(a => a.duration_seconds));
    const maxT = Math.max(...pts.map(a => a.total_tokens));

    ctx.fillStyle = C.bg2; ctx.fillRect(0, 0, W, H);
    ctx.font = '9px SF Mono, ui-monospace, monospace';

    for (let i = 0; i <= 4; i++) {
      const y = pad.t + cH * (1 - i / 4);
      const x = pad.l + cW * i / 4;
      ctx.strokeStyle = C.stroke + '55'; ctx.lineWidth = 0.5;
      ctx.beginPath(); ctx.moveTo(pad.l, y); ctx.lineTo(pad.l + cW, y); ctx.stroke();
      ctx.beginPath(); ctx.moveTo(x, pad.t); ctx.lineTo(x, pad.t + cH); ctx.stroke();
      ctx.fillStyle = C.muted;
      ctx.textAlign = 'right';
      ctx.fillText(fmtTok(maxT * i / 4), pad.l - 4, y + 3);
      ctx.textAlign = 'center';
      const secs = maxD * i / 4;
      ctx.fillText(secs >= 3600 ? (secs / 3600).toFixed(1) + 'h' : Math.round(secs / 60) + 'm', x, pad.t + cH + 14);
    }

    pts.forEach(a => {
      const x = pad.l + (a.duration_seconds / maxD) * cW;
      const y = pad.t + cH - (a.total_tokens / maxT) * cH;
      ctx.beginPath(); ctx.arc(x, y, 4, 0, Math.PI * 2);
      ctx.fillStyle = outcomeColor(a.outcome); ctx.globalAlpha = 0.72;
      ctx.fill(); ctx.globalAlpha = 1;
    });

    ctx.strokeStyle = C.stroke; ctx.lineWidth = 1;
    ctx.beginPath(); ctx.moveTo(pad.l, pad.t); ctx.lineTo(pad.l, pad.t + cH); ctx.lineTo(pad.l + cW, pad.t + cH); ctx.stroke();

    ctx.fillStyle = C.muted; ctx.textAlign = 'center';
    ctx.font = '9px SF Mono, ui-monospace, monospace';
    ctx.fillText('Duration →', pad.l + cW / 2, H - 4);
    ctx.save(); ctx.translate(10, pad.t + cH / 2); ctx.rotate(-Math.PI / 2);
    ctx.fillText('Tokens →', 0, 0); ctx.restore();
  }

  // ── Tooltips ──────────────────────────────────────────────────────────────
  function makeTip() {
    const el = document.createElement('div');
    el.className = 'chart-tooltip';
    document.body.appendChild(el);
    return el;
  }

  function showTip(tip, e, html) {
    tip.innerHTML = html;
    tip.style.display = 'block';
    tip.style.left = (e.pageX + 14) + 'px';
    tip.style.top  = (e.pageY - 54) + 'px';
  }

  function hideTip(tip) { tip.style.display = 'none'; }

  function outcomeLabel(o) {
    return o === 'resolved' ? '✓ resolved' : o === 'ready-for-human' ? '⊙ needs human' : '○ incomplete';
  }

  function initTokenTooltip() {
    const cv = document.getElementById('chart-tokens');
    if (!cv) return;
    const tip = makeTip();
    const sorted = [...DATA.attempts].sort((a, b) => a.issue - b.issue || a.iteration - b.iteration);
    cv.addEventListener('mousemove', e => {
      const rect = cv.getBoundingClientRect();
      const x = e.clientX - rect.left;
      const cW = rect.width - 56 - 12;
      const idx = Math.floor((x - 56) / (cW / sorted.length));
      if (idx >= 0 && idx < sorted.length) {
        const a = sorted[idx];
        showTip(tip, e, '<b>#' + a.issue + '</b> iter ' + a.iteration + '<br>' + outcomeLabel(a.outcome) + '<br>' + fmtTok(a.total_tokens) + ' · ' + fmtDur(a.duration_seconds));
      } else hideTip(tip);
    });
    cv.addEventListener('mouseleave', () => hideTip(tip));
  }

  function initScatterTooltip() {
    const cv = document.getElementById('chart-scatter');
    if (!cv) return;
    const tip = makeTip();
    const pts = DATA.attempts.filter(a => a.duration_seconds > 0);
    const maxD = Math.max(...pts.map(a => a.duration_seconds));
    const maxT = Math.max(...pts.map(a => a.total_tokens));
    cv.addEventListener('mousemove', e => {
      const rect = cv.getBoundingClientRect();
      const mx = e.clientX - rect.left, my = e.clientY - rect.top;
      const cW = rect.width - 76, cH = rect.height - 64;
      const pl = 56, pt = 20;
      let near = null, dist = Infinity;
      pts.forEach(a => {
        const d = Math.hypot(mx - (pl + (a.duration_seconds / maxD) * cW), my - (pt + cH - (a.total_tokens / maxT) * cH));
        if (d < dist) { dist = d; near = a; }
      });
      if (near && dist < 20) {
        showTip(tip, e, '<b>#' + near.issue + '</b> iter ' + near.iteration + '<br>' + outcomeLabel(near.outcome) + '<br>' + fmtTok(near.total_tokens) + ' · ' + fmtDur(near.duration_seconds));
      } else hideTip(tip);
    });
    cv.addEventListener('mouseleave', () => hideTip(tip));
  }

  // ── Table sorting ─────────────────────────────────────────────────────────
  function initSortable(tableId) {
    const table = document.getElementById(tableId);
    if (!table) return;
    const ths = Array.from(table.querySelectorAll('thead th'));
    ths.forEach((th, col) => {
      th.addEventListener('click', () => {
        const cur = th.getAttribute('data-sort');
        const dir = cur === 'asc' ? 'desc' : 'asc';
        ths.forEach(h => h.removeAttribute('data-sort'));
        th.setAttribute('data-sort', dir);
        const tbody = table.querySelector('tbody');
        const rows = Array.from(tbody.querySelectorAll('tr'));
        rows.sort((ra, rb) => {
          const ca = ra.querySelectorAll('td')[col];
          const cb = rb.querySelectorAll('td')[col];
          const va = ca?.getAttribute('data-value') ?? (ca?.textContent ?? '').trim();
          const vb = cb?.getAttribute('data-value') ?? (cb?.textContent ?? '').trim();
          const na = parseFloat(va), nb = parseFloat(vb);
          const cmp = (!isNaN(na) && !isNaN(nb)) ? na - nb : va.localeCompare(vb);
          return dir === 'asc' ? cmp : -cmp;
        });
        rows.forEach(r => tbody.appendChild(r));
      });
    });
  }

  // ── Init ──────────────────────────────────────────────────────────────────
  function drawAll() { drawTokens(); drawIterations(); drawScatter(); }

  window.addEventListener('load', () => {
    ['table-resolved', 'table-not-afk', 'table-phases'].forEach(initSortable);
    drawAll();
    initTokenTooltip();
    initScatterTooltip();
  });

  let resizeTimer;
  window.addEventListener('resize', () => {
    clearTimeout(resizeTimer);
    resizeTimer = setTimeout(drawAll, 120);
  });
})();
"""


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

    # Chart data (compact, embedded in JS)
    chart_attempts = sorted(attempts, key=lambda x: (x["issue"], x["iteration"]))
    chart_data = {
        "attempts": [
            {
                "issue": a["issue"],
                "iteration": a["iteration"],
                "outcome": a["outcome"],
                "total_tokens": a["tokens"]["total_tokens"],
                "duration_seconds": a["duration_seconds"],
            }
            for a in chart_attempts
        ]
    }
    chart_data_json = json.dumps(chart_data, separators=(",", ":"))
    js_code = _JS_TEMPLATE.replace("__CHART_DATA__", chart_data_json)

    # Build resolved rows
    resolved_rows = []
    for a in sorted(resolved, key=lambda x: x["issue"]):
        tok = a["tokens"]
        phases_html = badge_phases(a.get("phases", []))
        roles_html = badge_roles(tok.get("agent_roles", []))
        cc = ctx_class(tok["max_context_percent"])
        resolved_rows.append(f"""
        <tr>
          <td class="num">#{a["issue"]}</td>
          <td class="num">{a["iteration"]}</td>
          <td data-value="{a["duration_seconds"]}">{a["duration"]}</td>
          <td class="num" data-value="{tok["total_tokens"]}">{fmt_tokens(tok["total_tokens"])}</td>
          <td class="num" data-value="{tok["uncached_input_tokens"]}">{fmt_tokens(tok["uncached_input_tokens"])}</td>
          <td class="num {cc}" data-value="{tok["max_context_percent"]}">{tok["max_context_percent"]}%</td>
          <td class="num" data-value="{tok["compactions"]}">{tok["compactions"] or "—"}</td>
          <td class="num" data-value="{tok["session_count"]}">{tok["session_count"]}</td>
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
        label = {"ready-for-human": "human", "incomplete": "incomplete"}.get(
            a["outcome"], a["outcome"]
        )
        not_afk_rows.append(f"""
        <tr>
          <td class="num">#{a["issue"]}</td>
          <td class="num">{a["iteration"]}</td>
          <td><span class="badge {oc}">{label}</span></td>
          <td data-value="{a["duration_seconds"]}">{a["duration"] if a["duration_seconds"] else "—"}</td>
          <td class="num" data-value="{tok["total_tokens"]}">{fmt_tokens(tok["total_tokens"])}</td>
          <td class="reason">{reason_short or '<span class="muted">—</span>'}</td>
        </tr>""")

    # Build outlier row helper
    def outlier_row(a: dict, metric: str) -> str:
        tok = a["tokens"]
        oc = outcome_class(a["outcome"])
        label = {"resolved": "✓", "ready-for-human": "human", "incomplete": "—"}.get(
            a["outcome"], ""
        )
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
    phase_label = {
        "select": "select",
        "implement": "implement (mono)",
        "implement-tdd": "implement-tdd",
        "swift-review": "swift-review",
        "ui-verify": "ui-verify",
    }
    phase_rows = []
    for name in phase_order:
        if name not in phase_totals:
            continue
        s = phase_totals[name]
        avg = s["tokens"] // s["count"] if s["count"] else 0
        phase_rows.append(f"""
        <tr>
          <td>{phase_label.get(name, name)}</td>
          <td class="num" data-value="{s["count"]}">{s["count"]}</td>
          <td data-value="{s["dur"]}">{fmt_dur(s["dur"])}</td>
          <td class="num" data-value="{s["tokens"]}">{fmt_tokens(s["tokens"])}</td>
          <td class="num" data-value="{avg}">{fmt_tokens(avg) if avg else "—"}</td>
        </tr>""")

    resolve_rate = round(len(resolved) / len(attempts) * 100, 1)

    legend_html = """
          <span class="chart-legend">
            <span class="chart-legend-item"><span class="legend-swatch" style="background:#73FFB8"></span>resolved</span>
            <span class="chart-legend-item"><span class="legend-swatch" style="background:#0A84FF"></span>needs human</span>
            <span class="chart-legend-item"><span class="legend-swatch" style="background:#AAB8B0"></span>incomplete</span>
          </span>"""

    scatter_legend = """
          <span class="chart-legend">
            <span class="chart-legend-item"><span class="legend-swatch" style="background:#73FFB8;border-radius:50%"></span>resolved</span>
            <span class="chart-legend-item"><span class="legend-swatch" style="background:#0A84FF;border-radius:50%"></span>needs human</span>
            <span class="chart-legend-item"><span class="legend-swatch" style="background:#AAB8B0;border-radius:50%"></span>incomplete</span>
          </span>"""

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

{_CSS_EXTRA}

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
    <span class="header-meta">Generated {generated_at} &middot; {data["artifacts_dir"]}</span>
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
      <span class="stat-val">{data["issue_count"]}</span>
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

  <!-- Charts -->
  <section class="section">
    <div class="section-title">Charts</div>
    <div class="charts-grid">
      <div class="chart-card chart-full">
        <div class="chart-head">
          Token Consumption by Issue
          {legend_html}
        </div>
        <canvas id="chart-tokens"></canvas>
      </div>
      <div class="chart-card">
        <div class="chart-head">
          Iteration Depth
          {legend_html}
        </div>
        <canvas id="chart-iters"></canvas>
      </div>
      <div class="chart-card">
        <div class="chart-head">
          Duration vs Tokens
          {scatter_legend}
        </div>
        <canvas id="chart-scatter"></canvas>
      </div>
    </div>
  </section>

  <!-- AFK Solved -->
  <section class="section">
    <div class="section-title">
      AFK Solved
      <span class="count resolved">{len(resolved)}</span>
    </div>
    <div class="table-wrap">
      <table id="table-resolved">
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
          {"".join(resolved_rows)}
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
      <table id="table-not-afk">
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
          {"".join(not_afk_rows)}
        </tbody>
      </table>
    </div>
  </section>

  <!-- Phase Analysis -->
  <section class="section">
    <div class="section-title">Phase Analysis</div>
    <div class="table-wrap">
      <table id="table-phases">
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
          {"".join(phase_rows)}
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
            {"".join(outlier_row(a, "tokens") for a in top_tokens)}
          </tbody>
        </table>
      </div>
      <div class="outlier-card">
        <div class="outlier-card-head">Longest Runs</div>
        <table>
          <tbody>
            {"".join(outlier_row(a, "dur") for a in top_dur)}
          </tbody>
        </table>
      </div>
      <div class="outlier-card">
        <div class="outlier-card-head">Max Context %</div>
        <table>
          <tbody>
            {"".join(outlier_row(a, "ctx") for a in top_ctx)}
          </tbody>
        </table>
      </div>
      <div class="outlier-card">
        <div class="outlier-card-head">Most Compactions</div>
        <table>
          <tbody>
            {"".join(outlier_row(a, "compact") for a in top_compactions)}
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
<script>{js_code}</script>
</body>
</html>"""


def main() -> None:
    parser = argparse.ArgumentParser(description="Generate Ralph session HTML dashboard.")
    parser.add_argument(
        "--artifacts-dir", default="ralph/.artifacts", help="Ralph artifacts directory."
    )
    parser.add_argument("--sessions-dir", default=None, help="Codex sessions directory.")
    parser.add_argument("--output", default="ralph/reports/ralph-session-dashboard.html")
    args = parser.parse_args()

    print(f"Running ralph/report.py against {args.artifacts_dir} ...", file=sys.stderr)
    data = run_report(args.artifacts_dir, args.sessions_dir)

    generated_at = datetime.now(UTC).strftime("%Y-%m-%d %H:%M UTC")
    html = build_html(data, generated_at)

    out = Path(args.output)
    out.parent.mkdir(parents=True, exist_ok=True)
    out.write_text(html, encoding="utf-8")
    print(f"Dashboard written to {out}", file=sys.stderr)
    print(str(out))


if __name__ == "__main__":
    main()
