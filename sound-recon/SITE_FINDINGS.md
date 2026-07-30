# Site Recon — How aicodingdictionary.com Is Built

Investigation date: 2026-07-30. Evidence files live in this directory: `bundles/` (downloaded
chunks, incl. the lazy Atlas chunks), `pretty/` (beautified via js-beautify), `0v7_pretty.js`
(beautified app shell), `homepage.html`. Line numbers refer to the beautified files. Confidence:
**confirmed** = quoted code; **probable** = strong signature match; **guess** = inference.

The site is a Next.js single-page app: an R3F (react-three-fiber) canvas rendering ~69 dictionary
terms as a 3D "constellation", with search, a focus/zoom interaction, and a detail sheet. Almost
everything interesting is hand-rolled on top of three.js rather than taken from a graph library.

---

## 1. The 3D knowledge graph

### 1.1 What renders it — **confirmed**

**No force-graph library.** It is a custom scene built with **three.js + @react-three/fiber**,
with **camera-controls** (yomotsu) for the camera, **troika-three-text** for labels, and
**postprocessing** (+ its React wrapper) for effects. The graph *layout is precomputed at build
time* and shipped as JSON; d3-force-3d primitives are bundled only for a runtime "repack" of
search results (see 1.6).

- R3F: `bundles/0j8sj_zlz-pqv.js:393` contains `react-three-fiber` doc-link strings; the app
  mounts `<Canvas>` at `0v7_pretty.js:14198-14212`:
  ```js
  c = [1, 2], a = { antialias: !0, alpha: !1, powerPreference: "high-performance" },
  u = { position: [120, 90, 620], fov: 50, near: .1, far: 6e3 },
  ... (0,f.jsx)(h.Canvas, { dpr: c, gl: a, camera: u, onCreated: sV, ... })
  ```
  `onCreated` just does `gl.setClearColor(BG)`.
- The Atlas scene is **lazy-loaded**: `0v7_pretty.js` → `e.A(76016).then(e => e.Atlas)` with
  `ssr:!1` (next/dynamic); chunk 76016 maps to `static/chunks/0~p.rje6~zd8p.js` +
  `02s.6q3~d8cqh.js` (`bundles/03y99ypz_cvmk.js`, byte offset ~26133).
- camera-controls: the full class (with its telltale warnings `"camera-controls: ..."`) is in
  `pretty/atlas2.js:250-` and is mounted as drei-style `<CameraControls>` (`eO`) at
  `pretty/atlas2.js:8081-8086`.
- postprocessing: full export table (`EffectComposer`, `DepthOfFieldEffect`, `NoiseEffect`, …) at
  `pretty/atlas1.js:6089`; composer mounted with `multisampling: 4` at `pretty/atlas2.js:8087+`.
- troika-three-text: glyph SDF machinery (`glyphAtlasIndices`, `textRenderInfo`) at
  `pretty/atlas2.js:5755, 7011`, wrapped in a drei-`<Text>`-style component (suspend-react cache
  key `["troika-text", font, characters]`, `pretty/atlas2.js:7290-7315`).

### 1.2 Precomputed layout data — **confirmed**

`bundles/13k7ugx_ckuw-.js` module `67281` inlines the whole graph as
`JSON.parse('{"generatedFrom":"mattpocock/dictionary-of-ai-coding","sections":[...],"nodes":[...],"edges":[...]}')`
— node positions (`layout: [x,y,z]`), per-edge Bézier `control` points, and per-section bounding
`centroid`/`radius` are all baked at build time. Nothing is simulated at page load for the main view.

Node radius (`pretty/13k7.js:41`): `nodeRadius(inDegree) = 2.2 + log1p(d)/log1p(37) * 6.5`
(so radius ∈ [2.2, 8.7] world units).

### 1.3 Node representation — **confirmed**

Nodes are **billboarded quads shaded as flat discs**, drawn as one `InstancedMesh` of unit
`PlaneGeometry` (`pretty/atlas2.js:7601-7607` `args:[plane, void 0, count]`, `renderOrder:2`).
Per-frame positions+radii live in a **float RGBA DataTexture** (xyz = position, w = radius) that
every shader samples (`pretty/atlas2.js:2155-2161`):

```js
tO = Math.ceil(Math.sqrt(tC.MOTION_COUNT)), ... tM = new Float32Array(tO*tA*4),
tF = new er.DataTexture(tM, tO, tA, er.RGBAFormat, er.FloatType);
```

Vertex shader (`aE`, `pretty/atlas2.js:7416+`): fetch texel by instance index, billboard in view
space (`centerView.xy += position.xy * radius * 2.0`). Fragment shader (`aU`): hard-edged circle
(`if (length(vUv) > 0.5) discard;` — "MSAA handles AA, no shading"), plus:
- accent color mix when `vState > 1` (hovered/focused),
- a "depth-tint" separating overlapping discs (`sep * 0.220` toward paper),
- distance fade toward paper: `depthFade = 1 - smoothstep(uFadeNear, uFadeFar, vDepth) * uFadeStrength`
  with camera-relative uniforms `uFadeNear = camDist − nearOffset(35)`, `uFadeFar = camDist + farOffset(200)`,
  `strengthNodes .82 / strengthEdges .98 / strengthLabels .95`, tightened during search
  (`searchCut .78, searchNear 90`) (`pretty/atlas2.js:2445-2456, 7592-7600`).

Node dim/highlight states (`pretty/atlas2.js:7604-7617`): target state = focused `2`, neighbor
`1.3`, others `.035` (focus) / `.12` (hover), lerped with asymmetric smoothing
`1-.16**dt` up / `1-.012**dt` down.

### 1.4 The motion system (why it feels alive) — **confirmed**

One `useFrame(fn, -10)` pass (`tJ`, `pretty/atlas2.js:2213-2290`) recomputes every node position
per frame into the DataTexture:

- **Wobble**: per-axis dual-sine `amp * (0.7·sin(t·f + φ) + 0.3·sin(t·f·2.3 + 1.7φ))` with
  hash-random `amp = 3·(0.45+1.1·rand)`, `f = 0.19·(0.6+1.1·rand)`, phases seeded by golden angle
  `2.39996·i`.
- **Neighbor pull**: when a node is focused, its neighbors spring a fraction
  `tY = 0.24·(0.55+0.95·rand)` of the way toward it (plus ±4 unit random offset), via a
  damped spring: `F += ((target−x)·k − 17·v)·dt` with `k = 42·(0.45+1.4·rand)`.
- **Reveal**: staggered by distance-from-center (`delay = (‖p‖/maxR)·0.9`), eased with
  `1 − 2^(−10t)` over 2.4 s total; scale and label opacity follow.
- **Breathing size**: `radius · (1 + 0.012·sin(0.5t + φ))`.
- Search-match visibility multiplies size (`tL` array lerped toward 0/1 at `1−e^(−dt/0.18)`).

### 1.5 Links — **confirmed**

Custom ribbon mesh, one draw call (`ri`, `pretty/atlas2.js:2560-2700`): each edge = quadratic
Bézier `p = mu²·s + 2·mu·u·c + u²·t`, where endpoints come from the node DataTexture and
`c = midpoint + aControlOffset·uControlScale` (control offsets from the baked JSON;
`uControlScale` goes 0 during search → straight lines). Geometry: 16 arc-length-resampled points
per edge (CPU-precomputed, trimmed at both node radii), 2 rim verts each (`aSide ∓1`), widened in
the vertex shader along a screen-space perpendicular (`mv.xy += perp * (aSide * 0.5 * uLineWidth * aWidth)`).
The shader comments are shipped intact and are the best documentation:

```glsl
// ── shockwave ── physically vibrate the connected lines: a damped travelling
// wave that launches from the active node and rings down over a few seconds.
float env = exp(-uPulseTime * (1.5 + seed*0.8));
float wave = sin((vEdgeT * freq - uPulseTime * 0.6 + seed) * PI2);
float amp = vConnected * env * front * ends * wave * len * (0.022 + seed*0.012);
```

Edge brightness states (`pretty/atlas2.js:2668-2680`): base `.14`→`.08` rest; focused edge `.6`;
non-connected while focused `.022`; search: matched `.28` (or `.6` if touching the active node),
unmatched `0`. Same asymmetric lerp as nodes. A separate `Points` system (`aP`,
`pretty/atlas2.js:7710+`) runs **320 particles** traveling along the same Béziers (size 5,
per-particle speed/direction) — the "data packets" effect.

### 1.6 Search repack (runtime d3-force-3d) — **confirmed**

`pretty/13k7.js:1235-1266` (`solveRepack`): when a search matches, matched nodes are re-laid-out
around the origin with **d3-force-3d** primitives, solved synchronously (`T.stop(); 180× T.tick()`)
and applied as per-node offsets (animated by the spring system):

```js
let y = forceManyBody(); y.strength(-55);
let k = forceCollide(e => e.r + 18); k.iterations(4);
forceX(0).strength(.06) /* + forceY, forceZ */
forceSimulation(p, 3).force("charge", y).force("collide", k)...
// custom link force: rest length rA + rB + 40, stiffness .08
```

### 1.7 Hover & click — **confirmed**

**No Raycaster.** Picking is manual screen-space projection (`pretty/atlas2.js:7530-7560`): for
each node, project the live position, compute apparent radius `r·(h/2)/(dist·tan(fov/2))`, pick
the nearest node whose screen distance < `1.3×` apparent radius. `pointermove` is rAF-throttled
and sets cursor + `setHovered`; click = `pointerup` within **6 px** of `pointerdown`
(`Math.hypot(dx,dy) > 6 → return`), calling `focusNode(slug)` or clearing focus
(`pretty/atlas2.js:7563-7587`). Hover/focus draw a shader **ring** billboard (band via two
smoothsteps, radius animated in from `1.1·(0.5+0.35·(1−k))` on approach, opacity spring
attack `.13`/release `.05`) — `pretty/atlas2.js:2293-2360`.

### 1.8 Camera behavior — **confirmed**

`pretty/atlas2.js:7872-8100` (Atlas root):
- `<CameraControls makeDefault smoothTime={.28} draggingSmoothTime={.1} polarRotateSpeed={.6} azimuthRotateSpeed={.6}>`,
  plus `dollyToCursor = true, minDistance = 70, maxDistance = 1200, boundaryFriction = .85`,
  right-mouse disabled.
- **Focus animation**: `setLookAt(nodePos + dir·D, nodePos, smooth)` where `dir` is the node's
  radial direction and `D = min(1100, (230 + 9·nodeRadius) · (portrait ? 1.05 : 1))`, shrunk up to
  28 % for nodes near the center. During search-repack focus: `D = 125 + 8·nodeRadius`.
- **Intro**: camera set to final pose, then `rotateTo(az − 6.6, polar + .6)` instantly and eased
  back over **4.2 s** with `1 − 2^(−10t)` — a long swooping orbit.
- **Inertia**: manual — angular velocity sampled while dragging (clamped ±2.4 rad/s), then decayed
  `e^(−dt/0.6)` and fed to `controls.rotate()`.
- **Auto-rotate**: after 0.5 s idle, ramps over 1.6 s (smoothstep) to `0.045 rad/s` azimuth.
- Overview distance: `fitRadius`-based (`a_(w,h)`), `×0.52` portrait / `×0.85` landscape.

### 1.9 Post-processing & atmosphere — **confirmed**

`pretty/atlas2.js:2404-2436, 8087-8100`: EffectComposer (multisampling 4) with:
1. **DepthOfField** (optional, `enabled` store): focus distance/range spring-tracked to the
   focused node (or the hovered node's neighborhood mid-distance), bokehScale eased in ~0.3 s.
2. **Duotone** — custom `Effect` mapping luma → mix(shadow=INK, highlight=BG), with a white-point
   stretch (`l / 0.86`) documented in shipped comments; shadow/highlight colors are re-tinted to
   section palettes by interpolating **in OKLab** (`aD`, `pretty/atlas2.js:7690-7700`).
3. **Noise** (`SOFT_LIGHT`, premultiplied, opacity `.16` desktop / `.07` under 800 px).
Scene fog: `<fog args={[BG, 700, 2400]}>`; background color = BG.

**Replication note (area 1).** With ~1000 nodes this architecture is exactly right and scales:
precompute layout offline (run `d3-force-3d` or `graphology-layout-forceatlas2` in a build script,
save `[x,y,z]` + Bézier controls to JSON), render nodes as one InstancedMesh billboard-disc shader
fed by a DataTexture you rewrite each frame, edges as one indexed ribbon mesh sampling the same
texture, labels via troika/drei `<Text>` (cap visible count at distance), camera via the
`camera-controls` package (`setLookAt` for focus flights), and `postprocessing` for DoF/noise.
Everything except the two custom shaders is standard npm: `three`, `@react-three/fiber`,
`@react-three/drei` (Text, CameraControls), `camera-controls`, `troika-three-text`, `d3-force-3d`,
`postprocessing`, `@react-three/postprocessing`, `zustand`. Manual screen-space picking beats
Raycaster for discs and is ~30 lines.

---

## 2. Search

**Library: MiniSearch** — **confirmed** (its BM25 defaults `bm25:{k:1.2,b:.7,d:.5}`, fuzzy/prefix
weights `.45/.375`, `autoVacuum` options at `0v7_pretty.js:7695-7710` are verbatim MiniSearch
source; class instantiated at `0v7_pretty.js:10936-10957`):

```js
let e = new ny({
  idField: "slug",
  fields: ["title", "aliases", "description", "body", "usage", "avoid"],
  searchOptions: { boost: nD, prefix: !0, fuzzy: .2, combineWith: "OR" }
});
e.addAll(T.nodes.map(e => ({ slug, title, aliases: e.aliases.join(" "),
  description: nF(e.description), body: nF(e.body), usage: e.usage.map(nF).join(" "), avoid: nF(e.avoid) })))
```

- Field boosts (`nD`, `0v7_pretty.js:7748`): `title:3, aliases:2.6, usage:2, description:1.5, body:1, avoid:1`.
- `nF` strips markdown (`[text](url)` → text, `#>*_\`~` removed) before indexing.
- Index is built **lazily on first keystroke** and cached (`nW` singleton).
- Result post-filter (`0v7_pretty.js:10960-10974`): drop results scoring below **30 % of the top
  score**, cap at **15**; matches drive `applyMatches` (graph visibility) immediately, and the
  d3-force **repack is debounced 250 ms** (`setTimeout(..., 250)`, `0v7_pretty.js:10981`).
- Query state lives **in the URL** via a nuqs-style `useQueryState("q", { history:"replace",
  throttleMs:250, clearOnDefault:!0 })` (`0v7_pretty.js:10920-10926`) — **probable** nuqs, the
  option names match its API. Focused term is a second param `C("term", ...)` pushed/replaced
  (`0v7_pretty.js:14180-14193`).
- Keyboard (`0v7_pretty.js:10990-11000`): `/`, `⌘/Ctrl+K`, and `⌘/Ctrl+F` (only when nothing
  focused) focus+select the input; `Escape` clears query → then focus → then blurs the field;
  `Enter` focuses the top match (`$.current = t.slugs[0]`). Each keystroke plays the snd-lib
  "type" sound (see SOUND_FINDINGS.md).

**Replication note.** MiniSearch is a great pick at 1000 nodes (index of ~1000 short docs builds in
tens of ms — still fine to build lazily). Copy the boost table idea, the 30 %-of-top-score cutoff
(it keeps fuzzy junk out), URL-sync with nuqs, and debounce only the expensive layout reaction,
not the match highlighting.

---

## 3. Data model (shape only)

**Confirmed** — single inline JSON module (`bundles/13k7ugx_ckuw-.js` module `67281`,
`"generatedFrom":"mattpocock/dictionary-of-ai-coding"` — content is authored in a separate GitHub
repo, presumably as markdown, and compiled + laid out at build time):

```jsonc
{
  "generatedFrom": "mattpocock/dictionary-of-ai-coding",
  "sections": [ { "title": "The Model", "index": 0, "slugs": ["ai", "model", ...],
                  "centroid": [98.83, 0.34, 3.36], "radius": 166.74 }, ... ],   // 7 sections
  "nodes":   [ { "slug": "afk", "title": "AFK",
                 "description": "A working pattern where the user kicks off a session and lea…",
                 "body": "…", "prose": "…",                  // plain-text variants of the entry
                 "aliases": ["away from keyboard", ...],
                 "links": ["session", "agent", ...],          // slugs → cross-links = graph edges
                 "usage": ["…"], "avoid": "…",
                 "section": 6, "inDegree": 10,
                 "layout": [-12.83, 118.4, -56.92] }, ... ],  // 69 nodes
  "edges":   [ { "source": "afk", "target": "session",
                 "control": [-1.77, 61.38, -41.91] }, ... ]   // 527 edges, Bézier control point
}
```

- Edges are **derived from `links`** (slug references inside entries) and precomputed with a
  `control` point so curves can bow around the cloud; adjacency at runtime is rebuilt into a
  `Map<slug, Set<slug>>` treating edges as undirected (`pretty/13k7.js:12-17`).
- `inDegree` is precomputed and drives node size, label size, and camera distance.
- There is **no `_next/data` or API fetch** — the whole dataset rides in the client bundle
  (~368 KB raw for 69 entries; body text dominates). The slug detail sheet renders from the same
  in-memory objects (markdown-ish parsing of `body` happens client-side, `0v7_pretty.js:5955-6100`).

**Replication note.** At ~1000 nodes, keep the same shape but split payloads: a small "graph"
JSON (slug, title, section, inDegree, layout, edges+controls — a few hundred KB) inlined or
fetched eagerly, and lazy-load entry bodies per node (or ship a second JSON) so first paint isn't
gated on prose. Author entries as markdown files with front-matter (slug, aliases, links) in a
repo; a build script derives edges from cross-links, runs the 3D force layout, fits Bézier
controls, and emits the JSON.

---

## 4. UI / interaction details

- **Animation library: none.** No framer-motion/GSAP (the only "framer" hit is `framerates`,
  `bundles/0.w_1awdr2n3t.js`). All motion is hand-rolled per-frame lerps/springs in `useFrame`
  (graph) and CSS transitions/keyframes in CSS Modules (DOM). The one tween helper is snd-lib's
  internal fade. **Confirmed.**
- **Component library: Base UI** (`@base-ui-components/react`) — `data-base-ui-inert`,
  `useDialogRootContext`, popup/tooltip/dialog stores in `bundles/05.bvfuueijq4.js` and
  `0v7_pretty.js:7784-7860`; the bottom node-detail sheet is a Base-UI-style **Drawer** with CSS
  vars `--drawer-height`, `--drawer-swipe-movement-y`, `--drawer-snap-point-offset`, detents
  (`data-detent="rest|expanded"`), swipe handling in JS (`0v7_pretty.js:4065+`). **confirmed**
  base-ui presence; drawer package identity **probable** (could be a Base UI Drawer or a port of
  vaul's mechanics onto Base UI dialogs).
- **State**: zustand everywhere (`create((set,get) => …)` stores: `useJourney` for
  hover/focus/query/section, `useBoot` for reveal, fade/DoF tuning stores). **Confirmed**
  (`pretty/13k7.js:48-105`, `2397-2401`).
- **Styling: CSS Modules compiled by Turbopack** (class names like
  `node-detail-module__Sy7m5W__root`, `aihero-badge-module__O4Uapa__root`) — **no Tailwind**.
  Design tokens live in JS (`pretty/13k7.js:36-40`): paper `BG #f2f2f0`, ink `INK #1a1a19`,
  `SECTION_COLORS ["#FFD79E","#fff","#000","#000","#fff","#000","#fff"]`,
  `SECTION_PAPERS ["#4500B3","#EB4347","#9DD395","#D3C2FE","#0F7A6B","#FFD23F","#2D3DCF"]` —
  section tinting happens in the Duotone pass, not in DOM. **Confirmed.**
- **Fonts**: monospace-only identity. One `next/font` local face exposed as `--font-mono`
  (html class `mono_3117762b-module__Wa6naG__variable`, `font-family: var(--font-mono)` in
  `bundles/main.css`); 3D labels load `/fonts/mono/JetBrainsMono-Medium.ttf` into troika
  (`pretty/atlas2.js:7389`), uppercase, `fontSize 2.1 + 2·sizeT`, `outlineWidth "7%"` in paper
  color (halo for legibility), `baseOpacity .3 + .5·sizeT`. UI font **probable** JetBrains Mono
  (same family as labels).
- **Touch/mobile**: camera-controls' built-in touch actions (rotate / dolly+truck two-finger);
  portrait detection (`height >= width`) changes camera distances (×1.12/×1.05 focus, ×0.52
  overview); noise opacity halved under 800 px; `dpr` capped at 2; labels/DoF tuned per aspect.
  Tap-vs-drag uses the same 6 px slop as mouse. **Confirmed.**
- **Sound**: snd-lib kit 01 tap/type samples (full recipe in `SOUND_FINDINGS.md`). **Confirmed.**
- **Theme wrapper**: `<O.Theme theme="light" global>` (`0v7_pretty.js:14225`) — small theme
  provider, identity unverified. **guess**: minimal in-house or Base UI theming.

**Replication note.** The distinctive "feel" = paper/ink duotone post-pass + film-grain noise +
DoF + monospace-uppercase SDF labels + spring-based (not tween-based) motion. All achievable with
`postprocessing` (DepthOfField, Noise, one 15-line custom Effect for duotone), troika text, and
`zustand` + per-frame exponential smoothing (`x += (target-x) * (1 - k**dt)`) instead of an
animation library. For the sheet UI, `vaul` (Radix) or Base UI drawer gives the same swipe detents.

---

## 5. Framework & delivery

- **Next.js 16.2.6** (App Router / RSC) on **Vercel**, built with **Turbopack**. Evidence:
  `version:"16.2.6"` in `bundles/0-z66kerrpr8n.js` (next client runtime; React
  `19.3.0-experimental-…` alongside); `globalThis.TURBOPACK` chunk format in every bundle;
  `?dpl=dpl_…` Vercel deployment-skew query params on all assets; `self.__next_f.push` flight
  payload in `homepage.html`. **Confirmed.**
- **Rendering mode**: static shell (SSG) + fully client-rendered app. The HTML contains only the
  head, fonts, and the RSC flight payload; the graph/canvas mounts client-side with `ssr:false`
  next/dynamic. **No per-term routes**: `/afk` → 404; deep-linking uses query params `?q=` and
  `?term=` on `/`. Term pages exist only as the in-app sheet (external canonical pages live on
  aihero.dev: `AIHERO_URL/{slug}`, `pretty/13k7.js:36`). **Confirmed.**
- **React Compiler** is on — the `(0, tT.c)(n)` memo-cache pattern (`react.memo_cache_sentinel`)
  throughout the components. **Confirmed** (that pattern is compiler output).
- **Bundle strategy / performance tricks** (sizes are raw, pre-gzip):

  | Chunk | Size | Content |
  |---|---|---|
  | `0j8sj_zlz-pqv.js` | 508 KB | three WebGL renderer + react-three-fiber |
  | `0m2yd.i7~olfl.js` | 378 KB | three core (scene graph, audio, math) |
  | `13k7ugx_ckuw-.js` | 369 KB | **graph data JSON** + graph store + d3-force-3d + repack |
  | `0v7~_u7t~ujuk.js` | 307 KB | app shell: search, sheet, snd-lib, canvas mount |
  | `02s.6q3~d8cqh.js` (lazy) | 319 KB | Atlas scene, shaders, camera-controls, troika |
  | `0~p.rje6~zd8p.js` (lazy) | 274 KB | postprocessing library |
  | `0-z66kerrpr8n.js` | 251 KB | react-dom + next runtime |
  | remaining 13 chunks | ~580 KB | next router, Base UI, misc |

  The clever bits: (a) the heavy scene + postprocessing (~600 KB) is **deferred** behind
  `next/dynamic ssr:false` while three core loads eagerly; (b) **all** runtime work that can be
  precomputed is baked into the data (layout, Bézier controls, arc-length trim, inDegree);
  (c) single-draw-call instancing + DataTexture keeps per-frame JS ~O(n) array writes with zero
  allocations; (d) `preload as="script" fetchPriority="low"` hints for below-fold chunks;
  (e) immutable-cached assets keyed by `?dpl=` deployment id. **Confirmed** (file list +
  homepage `<link>` tags).

**Replication note.** Equivalent stack: Next.js (or Vite+React) + R3F, dynamic-import the scene,
precompute layout in a build script, ship graph JSON separate from prose. At 1000 nodes the same
InstancedMesh/DataTexture design holds (texture is 32×32); consider frustum-based label culling and
`frameloop="demand"` + invalidate-on-interaction if you want idle CPU near zero (this site runs a
continuous loop because everything wobbles).
