---
name: Workout App
description: A warm, light-filled Greenhouse for coach-programmed powerlifting Sessions.
colors:
  # The paint box (see docs/design/greenhouse-theme-tokens.md for the full role sheet)
  ink: "#152118"
  ink-night: "#EFF3E3"
  muted: "#404E44"
  muted-night: "#9AAA9B"
  cream: "#F2F7E8"
  action-day: "#0D6B40"
  action-day-ink: "#0A5936"
  action-night: "#1F8552"
  action-night-ink: "#A8CFB4"
  foliage: "#579168"
  paper-day-top: "#E9EEDC"
  paper-day-bottom: "#CBE1C2"
  paper-night-top: "#232C20"
  paper-night-bottom: "#121D14"
  bud-stroke-night: "#78F0B2"
  tile-current-border: "#1F8552"
  sheet-fill-day: "#EFF4E4"
  danger: "#FF3B30"
typography:
  exercise-name:
    fontFamily: "Fraunces"
    fontSize: "33px"
    fontWeight: 490
    lineHeight: 1.10
    letterSpacing: "0"
  ceremony-title:
    fontFamily: "Fraunces"
    fontSize: "38px"
    fontWeight: 490
    lineHeight: 1.10
    letterSpacing: "0"
  sheet-title:
    fontFamily: "Fraunces"
    fontSize: "24px"
    fontWeight: 490
    lineHeight: 1.1
    letterSpacing: "0"
  weight-entry:
    fontFamily: "Source Sans 3"
    fontSize: "46px"
    fontWeight: 700
    lineHeight: 1.1
    letterSpacing: "-0.015em"
  log-capsule:
    fontFamily: "Source Sans 3"
    fontSize: "18px"
    fontWeight: 650
    lineHeight: 1.2
    letterSpacing: "0.01em"
  body:
    fontFamily: "Source Sans 3"
    fontSize: "15px"
    fontWeight: 400
    lineHeight: 1.45
    letterSpacing: "0"
  field-label:
    fontFamily: "Source Sans 3"
    fontSize: "12px"
    fontWeight: 600
    lineHeight: 1.2
    letterSpacing: "0"
rounded:
  capsule: "999px"
  soft: "30px"
  focus-card: "24px"
  card: "20px"
  rail: "18px"
  tile: "15px"
  cell: "14px"
  mini: "6px"
  hairline: "3px"
spacing:
  xs: "8px"
  sm: "10px"
  md: "12px"
  lg: "16px"
  xl: "28px"
components:
  log-capsule-day:
    backgroundColor: "{colors.action-day}"
    textColor: "{colors.cream}"
    typography: "{typography.log-capsule}"
    rounded: "{rounded.capsule}"
  log-capsule-night:
    backgroundColor: "{colors.action-night}"
    textColor: "{colors.cream}"
    typography: "{typography.log-capsule}"
    rounded: "{rounded.capsule}"
  active-set-card-day:
    backgroundColor: "rgba(242,247,232,0.52)"
    textColor: "{colors.ink}"
    rounded: "{rounded.soft}"
    padding: "16px 16px 14px"
  active-set-card-night:
    backgroundColor: "rgba(242,247,232,0.07)"
    textColor: "{colors.ink-night}"
    rounded: "{rounded.soft}"
    padding: "16px 16px 14px"
  history-chip:
    backgroundColor: "rgba(21,33,24,0.055)"
    textColor: "{colors.ink}"
    rounded: "{rounded.capsule}"
    padding: "4px 10px"
  session-tile-complete:
    backgroundColor: "{colors.action-day}"
    textColor: "{colors.cream}"
    rounded: "{rounded.tile}"
---

# Design System: Workout App — Greenhouse

This document encodes **Greenhouse**, the design direction locked by the
visual-redesign map ([#408](https://github.com/Sunnshiine/workout-app/issues/408)).
It supersedes the "Warm Training Cockpit" system. The decided token values live
in `docs/design/greenhouse-theme-tokens.md`; this document is the system — the
ideas, roles, rules, and guardrails the tokens serve. ADR-0014 records the
decision to supersede ADR-0004 (Liquid Glass design system).

## 1. Overview

**Creative North Star: "Greenhouse" — a warm, light-filled room built for growth.**

Workout App is a native iOS tool for a single powerlifting athlete using it
between Sets on the gym floor. The Greenhouse frames each Session as tending
something alive: the room is bright, calm, and organic; progress is growth the
athlete causes, drawn as a branch that leafs out per logged Set. Warmth comes
from light and material — layered sunlit washes on sage paper, cream surfaces,
one serif voice — never from hype, density, or gamification.

**Key Characteristics:**

- **Light leads.** Day (sage-light) is the primary appearance. Night is the
  same room re-lit — never recolored, never neutral black.
- **One living thing per page.** The Session stage's branch is the app's only
  flora and the stage's one illustrative icon — **maximum one illustrative
  icon per page**. A control or status glyph does not count against it: any
  glyph on or inside a tappable control (the back arrow, play, X, chevrons, the
  steppers' triangles, the clear menu's ellipsis, the queue pill's stack, and
  the queue sheet's pairing stems, §5.4), one that leads a control's data (the
  Last Performed clock, the runline's calendar, the Superset partner's fork),
  or one that marks a state beside its word (the Saved check, the danger mark).
- **Growth is state, not reward.** The branch renders logged reality; the Move
  On ceremony is the single moment growth is performed. Nothing accumulates
  into a persisting garden.
- **Two voices.** Fraunces speaks (Exercise name, ceremony); Source Sans 3
  does everything else, with every numeral bold and tabular.
- **Rounded-soft, airy surfaces.** Capsules and large radii; editorial
  scaffolding (rules, uppercase microlabels, hairline grids) is stripped.
- **The Sunbird is a first-class brand element** — whole, quiet, and confined
  to its decided perches.
- The signature, accepted aesthetic risk is the **living stage** (§5.1).

The system still rejects bro-y hype, spreadsheet-shaped density, generic
fitness-SaaS cards, and over-gamification (§8) — those anti-regressions
survive from the previous system.

## 2. Appearances & Color

### Appearance strategy

Exactly **two appearances ship: Day and Night** (`.day` / `.night`). The
Settings preference stays three-way — System / Light / Night — with System
following iOS. "Dark" leaves the product vocabulary. All five legacy palettes
(`dark`, `black`, `mintGreen`, `sageLight`, `blueLight`) are retired. A fixture
launch pins the preference for screenshots and tests: `-UITEST_APPEARANCE dark`
renders Night and `-UITEST_APPEARANCE light` renders Day, whatever the
simulator's appearance. The flag takes the preference's stored values, `system`,
`light`, and `dark`, and any other value, `night` included, stops the launch with
a fatal error that names them. Without the flag, a fixture launch follows System.

**Night is a hand-lit value sheet, never derived from Day.** The room is
re-lit, not recolored: deep sage paper (`#232C20 → #121D14`, hue-preserved —
near-black drifts back toward the cockpit), leaves as moonlit foliage
(`#579168` with cream ribs), and exactly one soft glow, on the opening bud.

### The paint box

A small paint box plus flat semantic roles; views consume roles only, via the
environment palette. Full role tables: `docs/design/greenhouse-theme-tokens.md`.

- **`ink` / `inkNight`** — text; at low opacity, carved chips, shadows.
- **`muted` / `mutedNight`** — secondary text, skip strokes, ghost strokes.
- **`cream` (`#F2F7E8`)** — the workhorse: surfaces, pills, buds, leaf ribs,
  and text on action fills.
- **`actionDay` (`#0D6B40`)** — the day action green; also the day pigment for
  leaves, stems, and the bird.
- **`actionNight` (`#1F8552`)** — the night action green. **Mint fails the
  action role at night** (it reads candy and reverts to cockpit); the Log
  capsule stays green-fill with cream text in both appearances.
- **`actionDayInk` (`#0A5936`) / `actionNightInk` (`#A8CFB4`)** — the action
  green as words and glyphs on paper and as the system tint, except on
  Settings action rows (§5.9). Day uses the pressed Log green; Night is
  `actionNight` under cream @ 65%. The action
  greens stay fill and stroke colours: as small text `#1F8552` measures 1.9 to
  3.7:1 on night paper, and `#0D6B40` 4.0 to 4.4:1 on the queue sheet's darker
  foot.
- **`foliage` (`#579168`)** — *the* night pigment: leaves, stems, bird, and
  Block-grid tiles all re-light to this.
- **`paperDayTop` → `paperDayBottom` / `paperNightTop` → `paperNightBottom`** — the
  base gradient pairs under the washes.
- **`danger`** — system red, hold-to-skip only. Carried forward unchanged; no
  Greenhouse prototype styled an error state, so it awaits the build.

### Living paper (atmosphere)

Atmosphere is **organic light, never botanical objects**. The background is a
layered wash recipe per appearance — a base sage pair under four radial
washes: a warm sun pool top-left, mint breath and sage pooling at the edges,
deeper sage gathering at the foot. At night the same washes re-light: a warm
lamp pool where the sun stood, moonlit green lifts, dark pooling at the floor.
Sheets are living paper too — the queue sheet carries the washes; bare cream
reads too white.

### Named Rules

**The Room Re-lights Rule.** Night is the same room re-lit, never recolored:
hue-preserved deep sage paper, foliage pigment for everything that grows,
cream kept as the light source. No neutral black, no new hues at night.

**The Green Means Action Rule.** The action greens are for the Log capsule,
the current/selected state, and progress that has actually happened — never
decoration. (The Mint Means Current rule, restated for a system where day's
action color is a deep green and mint is banned from the night action role.)

**The Light Is Not Flora Rule.** Warm washes, pools, and glows may shape the
room; drawn plants may not. The branch is the page's only flora — flora in
the branch's air is where wellness-journal drift begins.

**The One Glow Rule.** Night carries exactly one glow: the opening bud (the
Log capsule's night shadow is a soft green light, not a glow effect). Day's
one delight is the Block grid's sunlit hour (§5.5).

**The Sage-Cream Exception Rule** (carried forward). Surfaces may be
cream-tinted, but must remain sage-led — never amber, gold, orange, tan, or
generic beige wellness styling.

## 3. Typography

**Voice Font:** Fraunces (variable TTF, bundled; pinned at `SOFT 100, WONK 0,
wght 490`, `opsz` tracking point size)
**Instrument Font:** Source Sans 3 (variable TTF, bundled)

**Character:** One warm serif voice speaking rarely, over a plain workhorse
that carries every number. Fraunces appears **only** as the Exercise name and
in ceremony moments (ceremony title, connect title, sheet titles). Source
Sans 3 does everything else — and **every numeral role is bold + tabular**
(`tnum`), so loads, reps, and RPE always read as instrumentation.

### Hierarchy (key roles — full table in the token sheet)

- **Exercise Name** (Fraunces, 33pt / 1.10): the page lead on the Session
  stage. May run two lines for mega-names; the branch cedes vertical air.
- **Ceremony Title** (Fraunces, 38pt, centered) / **Connect Title** (36pt) /
  **Sheet Title** (24pt).
- **Weight Entry** (SS3, 46pt / 700, tnum): the Active Set Card's biggest
  number.
- **Log Capsule** (SS3, 18pt / 650, tnum).
- **Set head** (SS3): `Set 3 of 5` as 16pt / 700 tnum + 14pt / 500 muted.
- **Body / Coach note** (SS3, 15pt / 1.45 muted), **labels** (12pt / 600
  muted), **runlines and reference text** (13.5pt and below, tnum).

### Named Rules

**The One Voice Rule.** Fraunces is the Exercise name and ceremony only. It
never labels chrome, never sets numbers, and stays off utility pages (Block
grid, Settings, History chips).

**The Numbers Stay Plain Rule** (carried forward). Loads, reps, RPE, Set
counts, and sync state use direct type — bold, tabular, no novelty styling,
no gradient text, no decorative tracking.

**The Product Scale Rule** (carried forward, re-derived). Fixed type sizes,
derived from the **single-page principle**: training surfaces never scroll,
and every locked composition was validated at fixed proportions. The
`Theme.type` role table is the single choke point (one row per role; a lint
rule bans font construction elsewhere), so adopting Dynamic Type later is a
one-file diff. System-owned surfaces (Settings, system alerts, share sheet)
keep native text styles and scale normally, and so does the app-drawn
destructive confirmation card (§5.9).

**The Shrink-Then-Truncate Rule.** Reference lines (Last Performed, history
chips' text, runlines) never wrap: shrink to a dense floor (≈11pt), then
truncate. Chips may flow to a new line; text itself never wraps.

## 4. Surfaces, Elevation & Radius

Depth is made of light: washes on the paper, cream surfaces at varying
opacity, soft wide shadows by day and border-as-light by night. Liquid Glass
is retired as the surface language — the one survivor is the Sunbird
colophon's glass disc (§6).

- **The one soft container** (`surface`, radius `soft` 30): the Active Set
  Card and the ceremony stats. Cream @ 52% by day with a soft double shadow;
  cream @ 7% at night with an inset cream border instead of a drop shadow.
- **Flat at rest** (carried forward): pills, rails, tiles, and chips are
  quiet cream fills with 1px strokes; hierarchy comes from fill, stroke, and
  type before any shadow.
- **Carved history** (the app's **only below-flat elevation**): Exercise
  History chips are inset into their sheet — "history is carved." Nothing
  else in the app is ever pressed below the surface except the volume
  control's active state, which borrows the same recipe.
- **Light and shade at one elevation** (Block grid): collapsed week cards sit
  in shade; the focus card alone stands in morning light with a glowing rim.

### Radius family

A named, concentric family (inner radius ≈ outer − inset); no view invents a
radius outside it. It replaces the old 8 / 16 / 28 scale:

`capsule ∞` (all controls: pills, steppers, queue pill, Log capsule, chips) ·
`soft 30` (the one soft container, sheet shoulders) · `focusCard 24` ·
`card 20` (week cards) · `rail 18` · `tile 15` · `cell 14` · `mini 6` ·
`hairline 2–3`.

### Named Rules

**The One Soft Container Rule.** Radius `soft` belongs to the Active Set
Card, the ceremony stats, and sheet shoulders — nothing else earns it. No
cards inside cards; each layer has a distinct job.

**The History Is Carved Rule.** Below-flat elevation exists only in the
Exercise History sheet's chips (and the pressed volume control). Everything
else sits on or above the paper.

## 5. Components

Each component's spec lives under its own number in a file beside the token sheet. Read the
spec for every surface you change.

| Section | Spec |
| --- | --- |
| §5.1 The Living Stage (Session stage) | [docs/design/session-stage.md](docs/design/session-stage.md) |
| §5.2 Active Set Card & input block | [docs/design/session-stage.md](docs/design/session-stage.md) |
| §5.3 Log capsule | [docs/design/session-stage.md](docs/design/session-stage.md) |
| §5.4 Superset stage — one plant, two branches | [docs/design/session-stage.md](docs/design/session-stage.md) |
| §5.5 Block grid — the focus week | [docs/design/screens.md](docs/design/screens.md) |
| §5.6 Exercise History sheet — the chip ledger | [docs/design/screens.md](docs/design/screens.md) |
| §5.7 Move On ceremony | [docs/design/screens.md](docs/design/screens.md) |
| §5.8 Sheet-connect screen | [docs/design/screens.md](docs/design/screens.md) |
| §5.9 Settings | [docs/design/screens.md](docs/design/screens.md) |

## 6. The Sunbird

The app icon's mark inside the app, its timing, and the bird's two perches:
[docs/design/sunbird.md](docs/design/sunbird.md).

## 7. Motion & Haptics

Custom motion is confined to **three growth moments**, all on the wing ease;
every piece of chrome — including the Log capsule — rides stock system
springs.

The three moments' timings, the haptics, hold-to-skip timing, and reduced motion:
[docs/design/motion-and-haptics.md](docs/design/motion-and-haptics.md).

## 8. Do's and Don'ts

### Do:

- **Do** keep coach-authored spreadsheet structure hidden behind Sessions,
  Exercises, Sets, and Set Logs.
- **Do** present one Exercise (or Superset) at a time on the stage; keep
  orientation in the plain `Set N of M` head and the queue sheet the queue
  pill opens.
- **Do** make the next logging action obvious and reachable with one hand —
  a chalky thumb is the benchmark; affordances stay visible, never
  chrome-on-demand.
- **Do** show sync and pending-write state honestly. Never imply a Set Log
  has landed if it has not.
- **Do** keep growth honest: the branch shows logged reality, dashed means
  empty bed, and skipped work never disappears from the stage (though it
  never renders in History chips).
- **Do** keep Night the same room re-lit: foliage pigment, cream light,
  hue-preserved sage paper.
- **Do** keep Fraunces to the Exercise name and ceremony, and every numeral
  bold + tabular.
- **Do** spend at most one illustrative icon per page, and let the branch be
  it on the stage.
- **Do** prefer a self-describing glyph (X, back arrow, play, a pairing stem) to an
  action spelled out in words, give each icon-only control an accessibility
  label, and keep on-screen text to a minimum (operator ruling 2026-10-11).
- **Do** use exact domain language from CONTEXT.md: Block, Week, Session,
  Exercise, Set, Set Log, Last Performed, Exercise History, Move On.
- **Do** preserve native iOS affordances for Settings, sheets, navigation,
  and text input; system surfaces keep native type and scaling.
- **Do** keep celebration tied to Move On — completion, not achievement.

### Don't:

- **Don't** use **bro-y hype / aggro fitness** styling: no beast-mode copy,
  flames, neon-on-black aggression, or all-caps shouting.
- **Don't** make a **spreadsheet-in-an-app** UI: no raw cell editing, dense
  grids, tiny tap targets, or visible row and column plumbing.
- **Don't** use **generic fitness SaaS** patterns: no interchangeable
  rounded-card dashboards, stock gradients, badge spam, ring charts, or
  cheerful clip art.
- **Don't** over-gamify: no XP bars, points, levels, streak pressure,
  mascots-as-reward, or confetti on normal logging taps.
- **Don't** let growth accumulate: no persisting garden, no per-Session
  flora carried between screens, no botanical objects in the atmosphere.
- **Don't** put flora in the branch's air — that is where wellness-journal
  drift begins.
- **Don't** use mint as the night action color, neutral black paper, or any
  recoloring of the room at night.
- **Don't** expose the retired palettes (`dark`, `black`, `mintGreen`,
  `sageLight`, `blueLight`) or the superseded amber direction.
- **Don't** use gradient text, side-stripe borders, broad decorative glass,
  or repeated identical card grids. The colophon's glass disc is the only
  glass.
- **Don't** add decorative motion. Custom motion belongs to the three
  growth moments only; chrome rides system springs.
- **Don't** invent radii outside the named family, or give radius `soft` to
  anything but the one soft container and sheet shoulders.
- **Don't** use "workout", "training day", "lift", "working set", "actual
  load", or "Finish Session" where the glossary says Session, Exercise,
  Set, Set Log, or Move On.
