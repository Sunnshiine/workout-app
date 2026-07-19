---
name: Workout App
description: A warm, light-filled Greenhouse for coach-programmed powerlifting Sessions.
colors:
  # The paint box (see docs/design/greenhouse-theme-tokens.md for the full role sheet)
  ink: "#152118"
  ink-night: "#EFF3E3"
  muted: "#526457"
  muted-night: "#9AAA9B"
  cream: "#F2F7E8"
  action-day: "#0D6B40"
  action-night: "#1F8552"
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
  flora and, with the day tiles' state marks, effectively its only icon —
  **maximum one icon per page**.
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
(`dark`, `black`, `mintGreen`, `sageLight`, `blueLight`) are retired; the
`-WORKOUT_THEME` launch argument survives as the screenshot/test pin with
`day` and `night` as its only values.

**Night is a hand-lit value sheet, never derived from Day.** The room is
re-lit, not recolored: deep sage paper (`#232C20 → #121D14`, hue-preserved —
near-black drifts back toward the cockpit), leaves as moonlit foliage
(`#579168` with cream ribs), and exactly one soft glow, on the opening bud.

### The paint box

A small paint box plus flat semantic roles; views consume roles only, via the
environment palette. Full role tables: `docs/design/greenhouse-theme-tokens.md`.

- **`ink` / `inkNight`** — text; at low opacity, carved chips, scrims, shadows.
- **`muted` / `mutedNight`** — secondary text, skip strokes, ghost strokes.
- **`cream` (`#F2F7E8`)** — the workhorse: surfaces, pills, buds, leaf ribs,
  and text on action fills.
- **`actionDay` (`#0D6B40`)** — the day action green; also the day pigment for
  leaves, stems, and the bird.
- **`actionNight` (`#1F8552`)** — the night action green. **Mint fails the
  action role at night** (it reads candy and reverts to cockpit); the Log
  capsule stays green-fill with cream text in both appearances.
- **`foliage` (`#579168`)** — *the* night pigment: leaves, stems, bird, and
  Block-grid tiles all re-light to this.
- **`paperDay` / `paperNight`** — the base gradient pairs under the washes.
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
one-file diff. System-owned surfaces (Settings, alerts, share sheet) keep
native text styles and scale normally.

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

### 5.1 The Living Stage (Session stage)

The Session is a single "now playing" surface and the system's signature: one
Exercise at a time, its progress drawn as a **branch that leafs out per
logged Set**. From top: the Cadence line (muted, 11pt), the Fraunces Exercise
name leading the page, the coach note, the branch, the Last Performed
reference line, and the Active Set Card with the Log capsule. The foot holds
the queue pill and up-next preview.

**The branch** is the page's one icon and one piece of flora — a 2px
round-cap stem carrying one leaf per logged Set, a cream bud with a green
stroke for the active Set, faint future strokes for what remains, and a
**dashed-outline leaf for a Skipped Set** (Set dots are fully retired;
validated at 8 Sets). The branch stands **textless** — no labels ride it.
By day it inks in `actionDay`; at night it is moonlit foliage with cream
ribs, and the bud carries the page's one glow.

- **Guardrail — the plain head:** the Active Set Card's head carries a plain
  `Set 3 of 5` in Source Sans 3. Position and progress are always legible as
  text; the branch is never the only way to read them. This is the no-botany
  pressure valve — under extreme content the words still carry the page.
- **Last Performed** is a quiet muted runline anchored to the Active Set
  Card — `W1 D2 — 90×5 @8 · …` — no "Last performed" label (the Set-Log
  shape says what it is). It shrinks then truncates, never wraps. A
  Movement-level fallback match labels itself with the matched entry's own
  entered name in muted italic (*as "Standing Calve Raises"*). Tapping it
  opens the Exercise History sheet — its only entry point, with at most the
  subtlest disclosure hint.
- **The stage foot:** an `N of M` **queue pill** owns position and opens the
  day's Exercise queue sheet; beside it, a plain `Up next · ` preview. The
  old glass up-next bar and the position label above the name are gone.

**The Stage Shows One Thing Rule** (carried forward). Exactly one Exercise
or Superset renders at a time. No stacked section-headed Exercises, no
scrolling Set-row list, no ambient rest-of-Session.

**Growth Is State Rule.** The branch renders what the athlete actually
logged — nothing more. Growth is performed only in the Move On ceremony;
nothing persists between Sessions as an accumulating garden, streak, or
trophy. A dashed leaf is honest about a Skip; a full branch marks
completion, not achievement.

**One Icon Per Page Rule.** The branch is the stage's icon budget spent.
Other pages spend theirs as sparingly (the Block grid spends its on nothing —
tiles are wordless fills).

### 5.2 Active Set Card & input block

The Active Set Card is the one soft container, ordered like the athlete's
actual entry — weight deliberate before the lift, reps and RPE reported
after:

- **Weight leads as the card's biggest number** — open, centered, ~54pt
  round ± steppers flanking it; tap-to-type raises the keyboard.
- **Reps (1–100) and RPE (5–10) are side-by-side one-tap scroll rails**,
  labels below; selected chips take a cream fill with an inset action ring.
- **Everything prefills from last week's actuals** — not a computed
  suggestion.
- **No units anywhere** in the block.
- A prescription tick marks last week's value on the rails.

Card padding is 16 / 16 / 14; steppers hold ~54pt targets, rail cells 48×44.
Invalid fields mark themselves with `danger` on the specific bad field only;
disabled states reduce opacity, not hue.

**Inert-Space All-Clear Rule** (carried forward). Tapping inert stage
background clears transient UI — dismisses keyboard editing and transient
utility state — without swallowing real controls.

### 5.3 Log capsule

A full-capsule action button: green fill (`actionDay` / `actionNight`),
cream text, previewing the exact Set Log about to be written. Day carries a
soft green drop shadow; night a soft green light. **Hold-to-skip** fills
with a muted overlay and reveals the Skip affordance (reveal 250ms, commit
850ms); a skipped state renders transparent with muted text and a 1.5px
dashed stroke — the dashed "empty bed" vocabulary.

### 5.4 Superset stage — one plant, two branches

A Superset draws as a **single forked stem** — still the page's one icon.
The focused Exercise's branch leads at full stroke and alone carries the
open bud (**the bud rides the focus**); the partner's branch is a shorter
drooping lateral (1.6px). Alternation is one bud settling and one waking —
never a branch redraw.

The focus tie is **tone coupling**: by day the partner's whole branch and
its Fraunces "**& partner**" name line (the manual focus switch) carry
foliage green while full pigment stays with the focus; at night — where
foliage *is* the leaf pigment — the partner subordinates by **translucency**
instead (foliage @ 0.55). Day quiets by pigment, night by translucency.

Coach note, Last Performed, and the Active Set Card follow the focus (the
card head stays plain `Set N of M`); the foot's up-next names the partner's
next Set. In the queue sheet, a Superset reads by **containment**: one soft
group, a sentence-case `Superset` caption, `Unlink`, and creation via
`Pair` → `Pair with this` — no bracket glyph. The queue sheet itself is
living paper (§2).

### 5.5 Block grid — the focus week

**The growth vocabulary does not extend to the Block grid.** Tiles are
plain, wordless, wider-than-tall; state is fill + stroke alone: inked
complete (green fill, cream text), cream-bud current (cream @ 95% with the
approved `#1F8552` border + sun glow), quiet available, ghost unavailable.
Zero icons — the lock icon is dead — and Fraunces stays off the page.

- **Focus-week layout:** only the week holding the Current Session expands.
  Every collapsed week is an elevated tappable card in shade, carrying a
  summary and a mini day-strip; the focus card alone stands in morning
  light with a glowing rim — hierarchy by **light and shade at one
  elevation**.
- **Partial day:** ink rising from the tile's foot in quantized quarters.
- **Empty bed:** an un-uploaded day is a dashed empty slot **grouped at the
  week's end**. Dashed means "empty bed" everywhere: Skipped Set and
  un-uploaded day alike.
- The **sunlit hour** (halo + panes + wash on the focus card) is the page's
  only delight — no branches, no bird.
- Night: tiles re-light like leaves — foliage fills, deep-ink text.

### 5.6 Exercise History sheet — the chip ledger

A sheet (radius `soft` shoulders, living-paper fill) opened only from Last
Performed. Every Set is a small **carved chip** — `27.5×10 @8`, inset into
the sheet — flowing off a `W1 D1` gutter label under quiet muted Block
headers, newest first. Chips may flow to a second line; text never wraps.

- **Skipped Sets never render.** All annotations — fallback spelling, Legacy
  Log rawness, skips — hide behind a `*` on the W/D label that expands into
  a small carved well. Legacy Logs render best-effort parsed into chips.
- A **Volume control** (chip-vocabulary pill, pressed-in when active, off by
  default) toggles a **total-volume chart**: weight × reps per session, ink
  line, hollow `≈` dots where Legacy Logs make totals approximate, a dotted
  Block seam.
- Night follows the night sheet recipe (flagged for build validation — not
  re-prototyped).

**The History Is Reference Rule** (carried forward, restated). No action
green in the sheet beyond the control vocabulary; history is quiet reading
material — no trend arrows, badges, or dashboard chrome. The volume chart is
the one chart, athlete-summoned and off by default.

### 5.7 Move On ceremony

The ceremony is the **only performed growth** in the app and the only large
celebratory moment, marking the athlete's explicit choice to Move On. On
living paper: the stem grows (1.0s), a 0.10s beat, then the **perched
songbird drops to the branch tip** (0.35s) — ≈1.5s total, at Brisk. The
Fraunces ceremony title speaks; the stats render on the shared soft surface
(values 26pt / 700, keys muted). With the bird present, the colophon is
absent and the composition re-centers.

**Completion, Not Achievement Rule.** The ceremony marks completion of the
athlete's choice, not the quality of the day — it must not curdle on an
ordinary day with Skipped Sets. The bird is brand, not badge. There is no
richer variant for a perfect Session (that rule is dead), no elapsed-time
UI, no confetti, XP, badges, or route previews.

**The No Fixed Day Count Copy Rule** (carried forward). No "only three days
left" or "halfway there" unless derived from the Week's actual Session count.

### 5.8 Sheet-connect screen

The second bird perch: a **flat calm** composition — the perched songbird
centered, the 40pt glass colophon above the ≥28pt floor, quiet copy.
Onboarding carries no monumental brand moment (prototyped and declined) and
sync carries no brand duty.

### 5.9 Settings

Settings stay native: system-owned rows, native text styles, normal Dynamic
Type. Appearance (System / Light / Night) lives here.

**Settings Own Manual Sync Rule** (carried forward). Manual sync is a
Settings row labeled **Sync now**, never a Session control or
pull-to-refresh affordance. The Session may show sync state honestly, but
never teaches the athlete to manage sync mid-Session.

## 6. The Sunbird

The app icon's sun-disc-with-bird-cutout mark (#370) is a first-class brand
element inside the app, governed by three named rules:

**The Mark Stays Whole.** The Sunbird appears only as the complete glass
mark — never disc-only, never wing-curve chrome, never below the **28pt
honesty floor** (it renders at 40pt). Its negative-space bird identity is
never reversed into a positive bird. It has no visual risks to take: it is
the colophon, quiet and whole.

**The Wing Is Timing.** The mark's one extraction is motion: the wing-curve
ease `cubic-bezier(0.46, -0.09, 0.83, 0.32)` is the app's signature timing.

**The Two Perches.** A separate **perched-songbird drawing** in the leaf
language (not the mark's glyph) lives in exactly two homes: center screen on
Sheet-connect, and the Move On ceremony branch tip (where it replaces the
colophon). **The Bird Re-lights Like a Leaf:** at night the bird takes
foliage ink with a cream wing-hint and no glow, while the glass colophon
keeps its icon greens unchanged.

## 7. Motion & Haptics

Custom motion is confined to **three growth moments**, all on the wing ease;
every piece of chrome — including the Log capsule — rides stock system
springs.

1. **Leaf inks on log** — 0.42s; a dashed Skip draws in the same language.
2. **Next bud opens** — inside the leaf's tail (starts 0.26s in, runs
   0.34s). **One Log, One Fill:** the transition must read as a bud waking,
   never a second leaf filling.
3. **Ceremony** — stem 1.0s, 0.10s beat, bird drops 0.35s (≈1.5s, Brisk).

Haptics are **Crisp, silent-chrome, semantic-only**: RPE detent tick
0.35/0.85 · log 1.0/0.65 · skip dud 0.45/0.15 · stepper ± 0.45/0.80 (the
floor hits the dud) · one identical swell-and-peak Move On pattern timed to
the ceremony · none on form fields. Hold-to-skip: reveal 250ms, commit
850ms, retreat 0.2s; logged-state hold 900ms, skipped-state hold 1100ms.

**Reduced motion** keeps end states via crossfade — the ceremony fades in
fully grown. Haptics are unaffected.

## 8. Do's and Don'ts

### Do:

- **Do** keep coach-authored spreadsheet structure hidden behind Sessions,
  Exercises, Sets, and Set Logs.
- **Do** present one Exercise (or Superset) at a time on the stage; keep
  orientation in the plain `Set N of M` head, the queue pill, and the queue
  sheet.
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
- **Do** spend at most one icon per page, and let the branch be it on the
  stage.
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
