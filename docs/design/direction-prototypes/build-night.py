#!/usr/bin/env python3
# Throwaway builder: extracts the embedded font data URIs from greenhouse.html
# and writes greenhouse-night.html (the night-edition prototype for issue #418).
import re, pathlib

here = pathlib.Path(__file__).parent
src = (here / "greenhouse.html").read_text()
fonts = re.findall(r"url\((data:font/woff2;base64,[^)]+)\)", src)
assert len(fonts) == 2, f"expected 2 embedded fonts, found {len(fonts)}"
fraunces, sourcesans = fonts

html = """<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=393, initial-scale=1">
<title>GREENHOUSE NIGHT — re-lit prototype (#418)</title>
<style>
/* Self-contained fonts (data URIs) so file:// capture always renders them. */
@font-face {
  font-family: 'Fraunces';
  font-style: normal;
  font-weight: 100 900;
  src: url(__FRAUNCES__) format('woff2');
}
@font-face {
  font-family: 'Source Sans 3';
  font-style: normal;
  font-weight: 200 900;
  src: url(__SOURCESANS__) format('woff2');
}

/* ————— the room, re-lit per variant (same hues, different light) ————— */
/* A · Moonlit, green action — the honest re-lit room */
body[data-variant="a"], body[data-variant="b"] {
  --paper-top: #16201626;         /* unused marker */
  --bg-top: #16201A;
  --bg-bottom: #0D1911;
  --ink: #EDF2E2;
  --muted: #93A496;
  --surface: rgba(242, 247, 232, 0.06);
  --surface-stroke: rgba(237, 242, 226, 0.09);
  --stem: #47825E;
  --leaf: #4F8A64;
  --leaf-rib: rgba(237, 242, 226, 0.35);
  --bud-fill: rgba(237, 242, 226, 0.92);
  --bud-stroke: #8FD8AC;
  --bud-glow: rgba(115, 255, 184, 0.35);
  --future-stroke: rgba(143, 216, 172, 0.32);
  --action-fill: #1F8552;
  --action-text: #F2F7E8;
  --action-glow: 0 0 26px rgba(31, 133, 82, 0.38), 0 1px 2px rgba(0, 0, 0, 0.35);
  --home: rgba(237, 242, 226, 0.22);
}
/* B · Moonlit, mint action — same room, cockpit-mint Log capsule */
body[data-variant="b"] {
  --action-fill: #73FFB8;
  --action-text: #0A1F14;
  --action-glow: 0 0 30px rgba(115, 255, 184, 0.28), 0 1px 2px rgba(0, 0, 0, 0.35);
}
/* D · Night greenhouse — the candidate recipe: A's darkness lifted toward C's warmth */
body[data-variant="d"] {
  --bg-top: #232C20;
  --bg-bottom: #121D14;
  --ink: #EFF3E3;
  --muted: #9AAA9B;
  --surface: rgba(242, 247, 232, 0.07);
  --surface-stroke: rgba(237, 242, 226, 0.10);
  --stem: #4F8A64;
  --leaf: #579168;
  --leaf-rib: rgba(237, 242, 226, 0.38);
  --bud-fill: rgba(239, 243, 227, 0.93);
  --bud-stroke: #93D8AE;
  --bud-glow: rgba(120, 240, 178, 0.32);
  --future-stroke: rgba(147, 216, 174, 0.34);
  --action-fill: #1F8552;
  --action-text: #F2F7E8;
  --action-glow: 0 0 26px rgba(31, 133, 82, 0.40), 0 1px 2px rgba(0, 0, 0, 0.35);
  --home: rgba(237, 242, 226, 0.22);
}
/* C · Lamplit dusk — the room a step lighter and warmer */
body[data-variant="c"] {
  --bg-top: #333D2A;
  --bg-bottom: #202D1D;
  --ink: #F0F4E3;
  --muted: #AEBBA4;
  --surface: rgba(242, 247, 232, 0.10);
  --surface-stroke: rgba(237, 242, 226, 0.10);
  --stem: #5E9973;
  --leaf: #61A175;
  --leaf-rib: rgba(240, 244, 227, 0.40);
  --bud-fill: rgba(240, 244, 227, 0.95);
  --bud-stroke: #99D8AF;
  --bud-glow: rgba(153, 216, 175, 0.30);
  --future-stroke: rgba(153, 216, 175, 0.35);
  --action-fill: #17754A;
  --action-text: #F2F7E8;
  --action-glow: 0 0 24px rgba(23, 117, 74, 0.40), 0 1px 2px rgba(0, 0, 0, 0.30);
  --home: rgba(240, 244, 227, 0.22);
}

* { box-sizing: border-box; }
html, body { margin: 0; padding: 0; }
body {
  position: relative;
  width: 393px;
  height: 852px;
  overflow: hidden;
  background: linear-gradient(180deg, var(--bg-top) 0%, var(--bg-bottom) 100%);
  color: var(--ink);
  font-family: 'Source Sans 3', sans-serif;
  -webkit-font-smoothing: antialiased;
  text-rendering: optimizeLegibility;
}

.screen {
  display: flex;
  flex-direction: column;
  width: 393px;
  height: 852px;
  position: relative;
}

.num { font-variant-numeric: tabular-nums; }
.muted { color: var(--muted); }

.time {
  position: absolute;
  top: 21px;
  left: 36px;
  font-size: 15px;
  font-weight: 600;
  font-variant-numeric: tabular-nums;
}
.home-indicator {
  position: absolute;
  bottom: 9px;
  left: 50%;
  transform: translateX(-50%);
  width: 134px;
  height: 5px;
  border-radius: 3px;
  background: var(--home);
}

.runline {
  display: flex;
  justify-content: space-between;
  align-items: baseline;
  font-size: 13.5px;
  font-weight: 600;
  font-variant-numeric: tabular-nums;
}
.runline .left { color: var(--ink); }
.runline .right { color: var(--muted); font-weight: 500; }

.position {
  font-size: 13px;
  font-weight: 600;
  color: var(--muted);
  font-variant-numeric: tabular-nums;
}
h1.exercise {
  margin: 8px 0 0;
  font-family: 'Fraunces', serif;
  font-variation-settings: "opsz" 30, "wght" 490, "SOFT" 100, "WONK" 0;
  font-size: 34px;
  line-height: 1.10;
  letter-spacing: 0;
  color: var(--ink);
}
.coach-note {
  margin: 14px 0 0;
  font-size: 15.5px;
  line-height: 1.5;
  color: var(--muted);
  max-width: 300px;
}

.branch-anchor {
  position: absolute;
  font-size: 12px;
  font-weight: 600;
  color: var(--muted);
  font-variant-numeric: tabular-nums;
  white-space: nowrap;
}

.last-performed {
  font-size: 12.5px;
  line-height: 1.55;
  color: var(--muted);
  font-variant-numeric: tabular-nums;
}

.flex-grow { flex: 1; }

/* the one soft surface — at night it earns a whisper of glow, not a shadow */
.set-surface {
  background: var(--surface);
  border: 1px solid var(--surface-stroke);
  border-radius: 30px;
  padding: 22px 24px 20px;
}
.set-head {
  display: flex;
  align-items: baseline;
  gap: 8px;
  padding: 0 4px;
}
.set-head .upnext {
  font-size: 13px;
  font-weight: 500;
  color: var(--muted);
}
.set-head .setno {
  font-size: 16px;
  font-weight: 700;
  font-variant-numeric: tabular-nums;
}
.vals {
  display: flex;
  align-items: flex-end;
  justify-content: space-between;
  margin-top: 18px;
  padding: 0 4px;
}
.vals .lbl {
  font-size: 12px;
  font-weight: 600;
  color: var(--muted);
  margin-bottom: 8px;
}
.vals .val {
  font-size: 41px;
  font-weight: 700;
  line-height: 1;
  letter-spacing: -0.01em;
  font-variant-numeric: tabular-nums;
}
.vals .unit {
  font-size: 16px;
  font-weight: 500;
  color: var(--muted);
  margin-left: 4px;
}
.log-btn {
  display: block;
  margin-top: 20px;
  width: 100%;
  height: 62px;
  border: 0;
  border-radius: 999px;
  background: var(--action-fill);
  color: var(--action-text);
  font-family: 'Source Sans 3', sans-serif;
  font-size: 18px;
  font-weight: 650;
  font-variant-numeric: tabular-nums;
  letter-spacing: 0.01em;
  box-shadow: var(--action-glow);
}

.stage-foot {
  display: flex;
  align-items: baseline;
  justify-content: space-between;
}
.stage-foot .next {
  font-size: 13.5px;
  color: var(--muted);
}
.stage-foot .next b { color: var(--ink); font-weight: 600; }
.stage-foot .queue {
  font-size: 13px;
  font-weight: 600;
  color: var(--muted);
  font-variant-numeric: tabular-nums;
}

.col {
  display: flex;
  flex-direction: column;
  height: 100%;
  padding: 0 36px;
}
.runline { margin-top: 72px; }
.position { margin-top: 42px; }
.branch-wrap {
  position: relative;
  margin-top: 22px;
  height: 176px;
}
.branch-wrap svg { display: block; }
.last-performed { margin-top: 12px; margin-bottom: 18px; white-space: nowrap; }
.stage-foot { margin: 26px 0 46px; }

/* ————— switcher (NOT part of the design) ————— */
.switcher {
  position: absolute;
  bottom: 6px;
  left: 50%;
  transform: translateX(-50%);
  z-index: 99;
  display: flex;
  align-items: center;
  gap: 2px;
  background: #111;
  color: #fff;
  border-radius: 999px;
  padding: 4px 6px;
  font-family: -apple-system, 'Helvetica Neue', Arial, sans-serif;
  font-size: 12px;
  box-shadow: 0 2px 10px rgba(0,0,0,.5);
}
.switcher a {
  color: #fff;
  text-decoration: none;
  padding: 2px 8px;
  font-size: 14px;
  line-height: 1;
}
.switcher .label { padding: 0 6px; white-space: nowrap; }
</style>
</head>
<body data-variants="a,b,c,d" data-variant="a">

<!-- same leaf geometry as the locked Greenhouse stage -->
<svg width="0" height="0" style="position:absolute" aria-hidden="true">
  <defs>
    <path id="leafShape" d="M0 8 C 15 2.3, 41 3.3, 60 8 C 41 21.7, 15 22.6, 0 8 Z"/>
    <path id="leafRib" d="M4 8.1 C 20 9.8, 40 9.6, 56 8.1" fill="none"/>
  </defs>
</svg>

<section class="screen">
  <div class="time num">21:14</div>
  <div class="col">
    <div class="runline">
      <span class="left num">Block 27 · Week 2 · Day 2</span>
      <span class="right num">14 Sets left</span>
    </div>

    <div class="position num">2 of 6</div>
    <h1 class="exercise">Competition Bench&nbsp;Press</h1>
    <p class="coach-note">Pause every rep. Keep the arch honest — no&nbsp;bounce.</p>

    <div class="branch-wrap">
      <svg id="branch" width="321" height="176" viewBox="0 0 321 176" aria-label="Set 3 of 5">
        <path id="stem" d="M 10 156 C 84 142, 176 100, 306 26" fill="none" stroke="var(--stem)" stroke-width="2" stroke-linecap="round"/>
      </svg>
      <span class="branch-anchor num" id="anchor">Set 3 of 5</span>
    </div>

    <div class="last-performed num">Last performed · W1 D2 — 90×5 @8 · 90×5 @8 · 90×4 @9</div>

    <div class="flex-grow"></div>

    <div class="set-surface">
      <div class="set-head"><span class="upnext">Up next ·</span><span class="setno num">Set 3</span></div>
      <div class="vals num">
        <div class="cell"><div class="lbl">Weight</div><div class="val">92.5<span class="unit">kg</span></div></div>
        <div class="cell"><div class="lbl">Reps</div><div class="val">5</div></div>
        <div class="cell"><div class="lbl">RPE</div><div class="val">8</div></div>
      </div>
      <button class="log-btn num">Log 92.5&nbsp;kg × 5 @8</button>
    </div>

    <div class="stage-foot">
      <span class="next">Up next · <b>Larsen Press</b></span>
      <span class="queue num">2 of 6</span>
    </div>
  </div>
  <div class="home-indicator"></div>
</section>

<nav class="switcher">
  <a id="sw-prev" href="?variant=c">‹</a>
  <span class="label" id="sw-label">A · Moonlit — green action</span>
  <a id="sw-next" href="?variant=b">›</a>
</nav>

<script>
  const KEYS = ['a', 'b', 'c', 'd'];
  const NAMES = {
    a: 'A · Moonlit — green action',
    b: 'B · Moonlit — mint action',
    c: 'C · Lamplit dusk',
    d: 'D · Night greenhouse'
  };
  const param = new URLSearchParams(location.search).get('variant');
  const key = KEYS.includes(param) ? param : 'a';
  document.body.dataset.variant = key;
  const idx = KEYS.indexOf(key);
  document.getElementById('sw-label').textContent = NAMES[key];
  document.getElementById('sw-prev').href = '?variant=' + KEYS[(idx + KEYS.length - 1) % KEYS.length];
  document.getElementById('sw-next').href = '?variant=' + KEYS[(idx + 1) % KEYS.length];

  // The living branch, re-lit: leaves are moonlit foliage (mid-luminance green,
  // never full-luminance mint — that was the updraft-leaf candy failure); the
  // opening bud is the one thing that earns luminance and a soft glow (the
  // icon's rule: light earns shadow, dark earns glow). State drawn once.
  const css = getComputedStyle(document.body);
  const V = (name) => css.getPropertyValue(name).trim();

  function drawBranch(cfg) {
    const svg = document.getElementById(cfg.svg);
    const stem = document.getElementById(cfg.stem);
    if (!svg || !stem) return;
    const NS = 'http://www.w3.org/2000/svg';
    const L = stem.getTotalLength();
    cfg.nodes.forEach((n, i) => {
      const p = stem.getPointAtLength(n.t * L);
      const q = stem.getPointAtLength(Math.min(L, n.t * L + 1.5));
      const ang = Math.atan2(q.y - p.y, q.x - p.x) * 180 / Math.PI;
      const side = i % 2 === 0 ? -1 : 1;
      const rot = ang + side * n.spread;
      const g = document.createElementNS(NS, 'g');
      g.setAttribute('transform',
        'translate(' + p.x + ' ' + p.y + ') rotate(' + rot + ') scale(' + n.s + ') translate(0 -8)');
      const use = (href, attrs) => {
        const el = document.createElementNS(NS, 'use');
        el.setAttribute('href', href);
        for (const k in attrs) el.setAttribute(k, attrs[k]);
        g.appendChild(el);
      };
      if (n.kind === 'leaf') {           // logged Set: moonlit leaf
        use('#leafShape', { fill: V('--leaf') });
        use('#leafRib', { stroke: V('--leaf-rib'), 'stroke-width': (1.2 / n.s).toFixed(2) });
      } else if (n.kind === 'current') { // current Set: the opening bud carries the glow
        g.setAttribute('style', 'filter: drop-shadow(0 0 6px ' + V('--bud-glow') + ')');
        use('#leafShape', { fill: V('--bud-fill'), stroke: V('--bud-stroke'), 'stroke-width': (2.2 / n.s).toFixed(2) });
        use('#leafRib', { stroke: V('--stem'), 'stroke-width': (1.2 / n.s).toFixed(2) });
      } else {                           // future Set: faint bud
        use('#leafShape', { fill: 'none', stroke: V('--future-stroke'), 'stroke-width': (1.2 / n.s).toFixed(2) });
      }
      svg.appendChild(g);
      if (n.kind === 'current' && cfg.anchor) {
        const a = document.getElementById(cfg.anchor);
        if (a) { a.style.left = (p.x + cfg.dx) + 'px'; a.style.top = (p.y + cfg.dy) + 'px'; }
      }
    });
  }

  drawBranch({
    svg: 'branch', stem: 'stem', anchor: 'anchor', dx: 4, dy: 32,
    nodes: [
      { t: 0.10, kind: 'leaf',    s: 0.82, spread: 46 },
      { t: 0.32, kind: 'leaf',    s: 0.72, spread: 52 },
      { t: 0.56, kind: 'current', s: 0.55, spread: 34 },
      { t: 0.78, kind: 'bud',     s: 0.30, spread: 24 },
      { t: 0.91, kind: 'bud',     s: 0.22, spread: 20 }
    ]
  });
</script>
</body>
</html>
"""

html = html.replace("__FRAUNCES__", fraunces).replace("__SOURCESANS__", sourcesans)
(here / "greenhouse-night.html").write_text(html)
print("wrote greenhouse-night.html", len(html), "bytes")
