# Sunbird mark — formal design audit

The **Sunbird** is the WorkoutTracker app-icon mark: a sun disc with a soaring
bird cut out in negative space. Direction decided in
[#370](https://github.com/Sunnshiine/workout-app/issues/370)
([resolution comment](https://github.com/Sunnshiine/workout-app/issues/370#issuecomment-4951952071)),
assets produced in #369, glass icons in #373.

This audit extracts what the mark *is* — measured geometry, exact color
values, legibility limits, variant behavior — as raw material for a visual
redesign direction pick. It does not propose a direction.

**Primary sources**

| Source | What it is |
|---|---|
| `docs/design/app-icon/appicon-{light,dark,tinted}.svg` | canonical raster artwork (1024×1024) |
| `docs/design/app-icon/appicon-dev-{light,dark}.svg` | WT Dev flavor (amber hue flip) |
| `WorkoutTracker/AppIcon.icon/` (`icon.json` + `Assets/sunbird-disc.svg`) | Icon Composer glass document, stable |
| `WorkoutTracker/AppIconDev.icon/icon.json` | Icon Composer glass document, dev |
| `docs/design/app-icon/README.md`, `icon-composer-guide.md` | asset pipeline and glass-tuning ledger |
| Issue #370 thread (7 comments) | decision rationale, rejected alternatives |
| `PRODUCT.md`, `DESIGN.md`, `CONTEXT.md` | brand personality, current system, domain language |

All coordinates below are in the 1024×1024 viewBox shared by every SVG
(`viewBox="0 0 1024 1024"`). Derived numbers come from evaluating the actual
Bézier path data (numerically, to 2 decimals).

---

## 1. Geometry

### 1.1 The construction

Two primitives only, in every variant:

- **Disc**: `circle cx=512 cy=512 r=396` (`appicon-light.svg` and siblings) —
  equivalently `M 116 512 a 396 396 0 1 0 792 0 …` in
  `AppIcon.icon/Assets/sunbird-disc.svg`.
- **Bird**: one closed path of exactly **four cubic Béziers**:

  ```
  M 230 440
  C 360 415  465 465  512 510    (top-left wing edge)
  C 559 465  664 415  794 440    (top-right wing edge)
  C 686 470  592 518  512 592    (bottom-right wing edge)
  C 432 518  338 470  230 440 Z  (bottom-left wing edge)
  ```

The raster SVGs subtract the bird via an SVG `<mask>` (bird path filled
`#000` on a white rect); the Icon Composer asset subtracts it via
`fill-rule="evenodd"` on a single compound path
(`sunbird-disc.svg`). Same geometry, two negative-space mechanisms.

The bird path is **exactly mirror-symmetric about x = 512**: each right-side
control point is the reflection of its left counterpart (e.g. C1 offsets
±130, ∓25 from the two wing anchors). There is no interior detail — no eye,
no wing/body separation, no second contour.

### 1.2 Measured proportions

| Measure | Value (viewBox units) | Ratio |
|---|---|---|
| Disc diameter : canvas | 792 : 1024 | **0.773** (canvas margin 116 each side = 11.3%) |
| Bird wingspan (x 230→794) | 564 | **0.712 × disc diameter** (≈ 1/√2 = 0.707, +0.7%) |
| Bird height (y 433.3→592) | 158.7 | **0.200 × disc diameter** (1:5) |
| Wingspan : bird height | 564 : 158.7 | **3.55 : 1** |
| Bird bbox center | (512, 512.7) | optically concentric with disc center (512, 512) |
| Wing anchors (230/794, 440) above disc center | 72 | 0.18 r |
| Bottom keel (512, 592) below disc center | 80 | 0.20 r |
| Wingtip → rim clearance | 105 (wingtip is 291 from center, r = 396) | **26.5% of r**; the cutout never touches the rim |

(Issue #370's resolution states the bird is "centered at ~(512,500)"; the
measured bounding-box center is (512, 512.7) — for practical purposes,
dead-center on the disc.)

### 1.3 Curve character

Evaluating tangents and extrema of the path:

- **Wingtip launch angle**: the top edge leaves the wingtip at **10.9° above
  horizontal** (tangent toward C1 = (360,415)); the bottom edge arrives at
  **15.5°**. The wingtips are sharp cusps with an included angle of
  **≈ 26.4°**.
- **Wing crest**: the top edge rises only **6.7 units** above the anchor line,
  peaking at (299.3, 433.3), i.e. at 12.2% of the wingspan in from the tip.
  The upper contour is nearly taut.
- **Center dive**: both top edges meet the head-notch vertex (512, 510) at
  **±43.8°**; the wedge of disc material diving between the wings opens at
  **92.5°** — a near-right angle.
- **Bottom keel**: the lower edges meet (512, 592) at ±42.8°; keel wedge
  **≈ 94.5°**. Both center vertices sit within ~4° of 90°.
- **Asymmetry of contours**: the top edge traverses 77 units of y
  (433 → 510); the bottom edge traverses 152 (440 → 592). The lower contour
  sweeps **~2× fuller** than the upper — this taut-above / full-below
  relationship is what makes the glyph read as a gliding bird rather than a
  ribbon.
- **Control-point tension** (top edge, normalized to its chord Δx = 282):
  C1 at 46.1% of the chord with y-offset −0.089·Δx, C2 at 83.3% with
  +0.089·Δx, chord slope 0.248. Symmetric ± control offsets on an asymmetric
  chord: a long shallow launch, late fast dive.

### 1.4 Cutout thickness profile (the negative-space "stroke")

Vertical thickness of the cutout, measured from the path
(fractions of disc diameter 792):

| x (from wingtip at 230) | thickness | % of disc ⌀ |
|---|---|---|
| 235 (tip + 5) | 2.3 | 0.3% |
| 250 (tip + 20) | 9.1 | 1.1% |
| 299 (wing crest) | 29.1 | **3.7%** |
| 373 (mid-wing) | 53.9 | 6.8% |
| 512 (center, body depth 510→592) | 82.0 | **10.4%** |

So the cutout is a tapered slot: **max 10.4% of disc diameter at the body,
~3.7% through the outer wing, tapering to 0 over the last ~4% of span**.

### 1.5 What UI chrome can inherit (measured, not invented)

These are ratios and angles a designer can lift directly from the mark;
whether to use them is the direction pick's job:

- **0.773 containment ratio** — disc diameter : canvas. A circular element
  (loading arc, avatar, dial) inset to 77% of its square container, leaving
  an 11.3% margin ring, reproduces the icon's breathing room.
- **The wing curve as a reusable arc/ease** — normalized top edge:
  P0 (0, 0), C1 (0.461, −0.089), C2 (0.833, +0.089), P3 (1, 0.248), y in
  chord-x units. Usable as the profile of a swooping divider, a progress-rail
  end-cap curve, or (read as a timing function) a slow-launch / late-dive
  ease.
- **Angle vocabulary**: 10.9–15.5° (launch), ~43.8° (dive), 26.4° (tip cusp),
  92.5°/94.5° (near-right-angle center notches). Loading arcs or chart
  accents that start at ~11° and terminate at ~44° speak the mark's dialect.
- **Thickness ratios for rails and dividers**: 1 : 2.8 : 1 taper profile
  (crest 3.7% → body 10.4% → 0), or in current DESIGN.md terms, the
  mark's body-slot : disc ratio (10.4%) maps to roughly an 8px element in a
  76px container. The current progress radius (`rounded.progress: 3px`,
  `DESIGN.md`) has no relation to the mark; the mark's own corner language is
  **circle-or-cusp** — it contains no intermediate corner radii at all.
- **Rim hairline**: the baked rim stroke is 10/1024 ≈ **1.0% of frame**
  (1.26% of disc ⌀) — consistent with DESIGN.md's existing 1px-stroke
  vocabulary at card scale.
- **Shadow/glow displacement**: light icon drops its shadow **+26 y (2.5% of
  frame, blur σ30)**; dark icon offsets its glow **+22 (σ34)**
  (`appicon-light.svg`, `appicon-dark.svg` `translate`/`stdDeviation`
  values). A consistent "light from above, ~2.5% displacement" rule.

Hard geometric constraint: the mark has **no straight lines and no
rounded-rectangle language**. It offers circles, tapered slots, cusps, and
near-right-angle notches — it cannot legitimize a new corner-radius scale by
itself.

---

## 2. Color relationships

### 2.1 Exact values extracted from the SVGs

**Light icon (L1 "deep green on sage", `appicon-light.svg`):**

| Layer | Value |
|---|---|
| Background gradient (vertical) | `#E8EDDB → #C7E0BF` |
| Disc body gradient | white @0.34 → `#12925A` @0.66 (42%) → `#0B7A45` @0.50 (100%) |
| Drop shadow | `#0A2416` @0.32, blur σ30, offset +26y |
| Rim stroke (w=10) | white 0.95 → 0.25 (55%) → 0.55 |
| Ambient light | radial white 0.55 → 0, centered (0.25, 0.05) |
| Sheen | ellipse (300, −80) r(900, 520), white 0.30 → 0.05 → 0 |

**Dark icon ("Midnight glass", `appicon-dark.svg`):**

| Layer | Value |
|---|---|
| Background gradient | `#050806 → #041C11` |
| Disc body gradient | white @0.55 → `#73FFB8` @0.34 (38%) → `#73FFB8` @0.14 |
| Glow (behind disc) | `#73FFB8` @0.55, blur σ34, offset +22y |
| Ambient lights | `#73FFB8` @0.22 top-left; **`#3D9DFF` @0.16 bottom-right** |
| Rim stroke (w=9) | white 0.9 → 0.12 → 0.35 |

**Tinted (`appicon-tinted.svg`)**: white-only on transparent — body white
1.0 → 0.62, rim white 1.0/0.4/0.7, w=9. Geometry unchanged; the system
supplies background and tint.

**Dev flavor** (`appicon-dev-light.svg`, `appicon-dev-dark.svg`): identical
geometry and glass physics, hue-flipped to amber — light: `#C97C1E`/`#A85F10`
body on sand `#F0EADB → #E2D3B2`, shadow `#241705`; dark: `#FFC873` body/glow
on `#080604 → #1F1204`, ambients `#FFC873` @0.22 + `#FF6D3D` @0.16.

**Icon Composer documents** (`AppIcon.icon/icon.json`,
`AppIconDev.icon/icon.json`) — converting the stored sRGB floats:

| Document | Layer fill | Background gradient | Material |
|---|---|---|---|
| stable | `#0B7A45` | `#E8EDDB → #C7E0BF` | glass on, refractivity enabled (depth 1, strength 1), translucency 0.7, shadow neutral 0.2, specular off |
| dev | `#D9820F` | `#F0EADB → #D9C49C` | glass on, **blend-mode "screen"**, refractivity enabled (depth 0), translucency 0.7, shadow neutral 0.3, specular off |

Two documented-vs-actual discrepancies worth knowing when citing the guide:
`icon-composer-guide.md` (§3) describes the shipping state as
"shadow 0.3, translucency 0.25" with a dark-appearance color specialization;
the checked-in stable `icon.json` actually holds shadow 0.2, translucency
0.7, refractivity on, and **no per-appearance specialization is present in
the file** (single fill, single gradient). And the guide's rule that the two
documents "differ by hue only" does not currently hold (screen blend, shadow
and refraction depth differ). Whoever consumes these values should trust the
JSON, not the prose.

### 2.2 Computed contrast ratios (WCAG relative luminance)

| Pair | Ratio | Reading |
|---|---|---|
| `#0B7A45` on `#E8EDDB` (icon green on sage-top) | **4.52:1** | passes 4.5 by a hair |
| `#0B7A45` on `#C7E0BF` (sage-bottom) | **3.82:1** | large-text/graphics only |
| `#12925A` on `#E8EDDB` / `#C7E0BF` | 3.32:1 / 2.81:1 | glass-optics color, not text-safe |
| `#73FFB8` on `#050806` / `#041C11` | **16.02:1 / 14.18:1** | huge headroom |
| `#0B7A45` on `#73FFB8` (the two disc greens) | 4.31:1 | near-AA against each other |
| white on `#0B7A45` | 5.41:1 | text-on-green works |
| `#0D6B40` (app sage-primary-green, DESIGN.md) on sage-top/bottom | 5.50:1 / 4.65:1 | the app's green is deliberately darker than the icon's |
| `#C97C1E` on `#F0EADB` (dev light) | 2.74:1 | icon-scale only |
| `#FFC873` on `#080604` (dev dark) | 13.26:1 | |

### 2.3 What the relationships imply — and deliberately don't

**Identities with the in-app system (byte-exact):**

- Both icon backgrounds equal DESIGN.md's app backgrounds exactly:
  `#E8EDDB → #C7E0BF` = `sage-background-top/bottom`, `#050806 → #041C11` =
  `dark-background-top/bottom`. The icon literally sits on the app's canvas.
- `#73FFB8` = `dark-primary-mint` exactly — the dark icon's disc *is* the
  app's action color. Per DESIGN.md's **Mint Means Current Rule**, the icon
  spends the action color on the identity mark; the mark and "current action"
  share one hue.

**Divergences (glass-tuned, not palette members):**

- The light icon's greens `#0B7A45`/`#12925A` appear nowhere in DESIGN.md;
  the app's light action green is `#0D6B40` (5.50:1 vs sage-top). #370's
  resolution explains the icon greens as optics: bottle-green "nudged toward
  `#12925A` at the top of the disc so it keeps inner light." At 4.52/3.82:1
  and applied at 0.50–0.66 opacity over a gradient, they are tuned for
  figure-ground at icon scale — **not** contrast-safe text/UI colors on the
  sage gradient. The relationship to inherit is the *ramp* (darker green
  gains a lighter, more saturated top under light), not the literal hexes.
- `#3D9DFF` (dark) and `#FF6D3D` (dev dark) exist only as ≤0.16-opacity
  ambient light spots — glass physics (a cool/warm counter-light), not
  palette. DESIGN.md's **Preview Palette Quarantine Rule** explicitly
  quarantines blue; the icon does not overrule that.
- The amber dev family (`#C97C1E`–`#FFC873`) is build-flavor signaling only.
  DESIGN.md's **No Amber Regression Rule** forbids amber in-app;
  `appicon-dev-dark.svg`'s own comment frames it as "dawn sun for dev builds
  vs. the stable mint," and the dev-flavor decision (README.md) chose hue
  flip precisely because letters/badges were ruled out in #370.

**Glass physics as a transferable recipe** (both appearances, from the SVG
layer stacks): color lives in a mid-gradient at 0.34–0.66 opacity between a
white top-light (0.34–0.55) and a darker base; a white rim of ~1% frame
width; one off-axis white sheen; shadow/glow displaced +2.2–2.5% of frame
downward. Light mode earns a *shadow* (`#0A2416` @0.32), dark mode earns a
*glow* (`#73FFB8` @0.55) — the same object, re-lit rather than recolored.

---

## 3. Scalability

### 3.1 Reasoning from the geometry

The legibility bottleneck is the cutout's thickness profile (§1.4): body slot
10.4% of disc ⌀, outer-wing ~3.7%, tips → 0. Assumptions for the translation
to points:

- The glyph is scaled so the **disc diameter equals the rendered size S**
  (bare glyph, no canvas margin). If the full 1024 canvas is rendered
  instead, multiply every minimum below by 1.29 (disc is 77.3% of frame).
- A negative-space feature survives antialiasing at roughly **≥ 1 pt**
  (≥ 2 physical px @2x, 3 px @3x); below that it greys out or vanishes.
- Rasterizer ≈ Chromium (the repo's reference rasterizer,
  `docs/design/app-icon/README.md`); contrast per §2.2.

Feature widths at rendered disc size S:

| S (disc ⌀) | body slot (10.4%) | wing crest (3.7%) | verdict |
|---|---|---|---|
| 16 pt | 1.66 pt | 0.59 pt (1.8 px @3x, 1.2 px @2x) | disc + notch read; **wings collapse — not a bird** |
| 20 pt | 2.07 pt | 0.73 pt | wings a broken hairline; marginal @3x, no @2x |
| 24 pt | 2.48 pt | 0.88 pt | threshold; acceptable @3x only |
| 28 pt | 2.90 pt | 1.03 pt | **first honest size**: full silhouette incl. crest |
| 44 pt | 4.56 pt | 1.62 pt | comfortable; taper resolvable to within ~1 pt of tips |
| 120 pt | 12.4 pt | 4.4 pt | full fidelity: 26° cusps, 92°/94° notches, taper |

Solving crest ≥ 1 pt gives the analytic minimum: **S ≥ 792/29.1 ≈ 27 pt** for
the mark to read as a bird; the body slot alone reads from S ≈ 10 pt, but as
"disc with a bite," not a bird.

Cross-check against the decision record: #370's L1-over-L2/L3 choice was
gated on "figure-ground contrast at 40–60px"
([resolution](https://github.com/Sunnshiine/workout-app/issues/370#issuecomment-4951952071)).
At a 60 px rendering of the 1024 canvas, the crest is 29.1/1024 × 60 ≈ 1.7 px
— consistent with "just holds," matching this analysis.

### 3.2 Honest minimums per use

- **Sync indicator (~16–20 pt)**: the full mark is **not viable**. At 16 pt
  the wing is 0.59 pt. Options the geometry allows: disc-only (with or
  without the notch), or a redrawn small-size cut with the cutout thickened
  ≥ 1.5–2× (an SF-Symbols-style optical size). Do not ship the 1024 geometry
  here.
- **Tab/toolbar glyph (24–28 pt)**: 24 pt is marginal (@3x only); **28 pt is
  the honest floor** for the unmodified geometry. A thickened optical
  variant would buy back 24 pt and 2x displays.
- **Empty-state hero (≥ 64 pt; 120 pt comfortable)**: fully legible,
  including tip taper and notch angles; the glass layer stack (§2.3) also
  renders meaningfully at this scale.

---

## 4. Variants

### 4.1 What exists (all from the repo)

| Variant | Source | Behavior |
|---|---|---|
| Light (L1) | `appicon-light.svg` → `AppIcon.appiconset/Icon-1024.png` | deep-green glass on sage; shadow, crisp rim |
| Dark (Midnight) | `appicon-dark.svg` → `Icon-1024-dark.png` | mint glass, glow instead of shadow, blue counter-ambient |
| Tinted | `appicon-tinted.svg` → both sets' `Icon-1024-tinted.png` | grayscale on transparent; iOS supplies background + user tint; "lighter pixels read brighter" (file comment) |
| Dev light/dark | `appicon-dev-*.svg` → `AppIconDev.appiconset` | amber hue flip only; geometry and physics identical |
| True glass | `WorkoutTracker/AppIcon.icon`, `AppIconDev.icon` | one monochrome SVG layer (`sunbird-disc.svg`); iOS 26 Liquid Glass supplies rim/sheen/refraction; raster sets are the back-deploy fallback (`README.md`) |

Variant mechanics: the raster SVGs bake the glass (glow/rim/sheen layers);
the `.icon` documents carry *no* baked lighting — a flat evenodd disc-minus-
bird plus `icon.json` material settings, with the system material doing the
physics. Dev differentiation is **tint-only by decision**: "letters and
badges were ruled out with the #370 mark decision" (`README.md`).

### 4.2 Monochrome / silhouette viability

Proven, not speculative: `appicon-tinted.svg` is the mark in white-alpha
only, and `sunbird-disc.svg` is explicitly "Monochrome — the layer's fill in
icon.json supplies the color" (file comment). The mark survives a single flat
color with zero gradient support; its identity is carried entirely by the
disc-minus-bird geometry. The Icon Composer Mono appearance is also a checked
preview state (`icon-composer-guide.md` §5).

### 4.3 Can the bird fly outside the disc? (key finding)

**Geometrically, yes — the bird exists as an independent closed path.** In
all five raster SVGs the bird is a standalone, closed, fill-rule-clean path
(`M 230 440 C … Z`, filled `#000` inside a `<mask>`); it is not defined by
subtracting arcs from the disc. Only `sunbird-disc.svg` fuses it into a
compound evenodd path, and even there it is a self-contained subpath. Anyone
can lift the four-Bézier path and use it as a positive shape.

Three qualifications from the primary sources:

1. **The decision chose negative space on purpose.** #370's resolution:
   "a soaring bird as *pure negative space* in a glass sun disc." A
   bird-as-object composition was explicitly explored and not picked — round
   3's G2 "Skybird" ("the bird itself as the glass object … no disc") lost to
   the G1 baseline
   ([round-3 comment](https://github.com/Sunnshiine/workout-app/issues/370#issuecomment-4951903121),
   [round-5](https://github.com/Sunnshiine/workout-app/issues/370#issuecomment-4951935641)).
   So did G6 "Crossing," the one variant whose wingtip broke the disc edge.
2. **The positive bird is featureless.** No eye, no body mass, no wing
   separation — a 3.55:1 twin-arc glyph. As a cutout, the disc supplies its
   figure-ground and scale; as a free-flying positive shape it reads as a
   generic gull mark and loses the sun-disc identity that names it.
3. **Inside the icon it never touches the rim**: 105 units (26.5% of r) of
   clearance (§1.2). The mark's own composition rule is containment.

Net: the path affords extraction (watermarks, motion, a bird that leaves the
disc during an animation are all geometrically free), but the *decided
identity* is the cutout; a positive-bird usage is a new decision, not an
existing behavior.

---

## 5. What the mark gives the system

Formal assets a direction concept can build on — all measured above:

1. **A two-primitive construction rule**: one circle + one 4-Bézier closed
   path, subtractively combined; identity survives flat monochrome (§4.2).
2. **The wing curve**: normalized cubic P0 (0,0), C1 (0.461, −0.089),
   C2 (0.833, +0.089), P3 (1, 0.248) — taut above, full below (2:1 contour
   asymmetry), usable as arc profile or timing curve (§1.3, §1.5).
3. **A ratio kit**: 0.773 disc-in-frame; wingspan ≈ 0.712 ⌀ (≈ 1/√2); bird
   height = 0.200 ⌀; slot thickness 10.4% ⌀ tapering through 3.7% to 0;
   rim ≈ 1% frame (§1.2, §1.4, §1.5).
4. **An angle kit**: 11°/15.5° launch, 43.8° dive, 26.4° cusp, 92.5°/94.5°
   near-right notches (§1.3).
5. **Color identities**: icon backgrounds = app backgrounds byte-exact;
   `#73FFB8` = `dark-primary-mint` = the identity hue in dark. Plus a light
   green ramp `#0B7A45 → #12925A` that is glass-optics, not text color
   (4.52/3.82:1 on sage) — the app's own `#0D6B40` stays the text-safe green
   (§2.2–2.3).
6. **A re-lighting rule, not a recoloring rule**: light mode = shadow
   (`#0A2416` @0.32, +2.5% offset), dark mode = glow (`#73FFB8` @0.55,
   +2.2%); body color always sandwiched between a white top-light and a
   darker base at 0.34–0.66 opacity (§2.3).
7. **A containment ethic**: the cutout keeps 26.5% r clearance from the rim;
   the dev flavor differentiates by hue only (§1.2, §4.1).
8. **An independently usable bird path** — with the caveat that positive-bird
   usage reverses the decided negative-space identity (§4.3).

**Hard constraints — what the mark cannot do:**

- **It cannot go small unmodified.** Below ~28 pt (disc size) the wings die;
  below ~24 pt on 2x displays the mark is not a bird (§3). Small sizes need
  either disc-only usage or a thickened optical cut.
- **It offers no straight-line or corner-radius vocabulary.** Circles, cusps
  and tapered slots only; it cannot be cited to justify a rectangle language
  (§1.5).
- **Its light-mode greens are not accessibility colors** (3.82:1 against
  sage-bottom); inheriting the hexes into text/UI would fail where the app's
  existing `#0D6B40` passes (§2.2).
- **Amber and blue are off-limits as system colors** despite appearing in the
  icon family: amber is dev-flavor signaling (DESIGN.md No Amber Regression
  Rule), blue is a ≤0.16-opacity light effect (Preview Palette Quarantine)
  (§2.3).
- **No letters, no mascots, no literal lifting props** — #370 rejected
  letter marks in round 2 and every literal lifting-bird in round 4
  ("mascot, not a mark"), which aligns with PRODUCT.md's anti-references
  (over-gamified, generic fitness SaaS). The mark's abstractness is a
  decided property, not an accident.
