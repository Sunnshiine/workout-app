# Greenhouse design system

Greenhouse is the app's design system (ADR-0014). `PRODUCT.md` holds the users, the design
principles, and the anti-references, and they bind every screen this file covers. The token values
live in `docs/design/greenhouse-theme-tokens.md` and `Sources/WorkoutTracker/Theme.swift`. This
file holds the rules those values serve. A § number names a section of this file, or of the
component spec that keeps its number (§5).

## 1. Overview

Greenhouse treats each Session as tending something alive. Progress is growth the athlete causes,
drawn as a branch that leafs out per logged Set. Warmth comes from light and material: sunlit
washes on sage paper, cream surfaces, and one serif voice. The living stage (§5.1) is the signature
and the accepted aesthetic risk.

**One illustrative icon per page.** The Session stage's branch is the stage's one illustrative icon.
A control or status glyph does not count against it: any glyph on or inside a tappable control (the
back arrow, play, X, chevrons, the steppers' triangles, the clear menu's ellipsis, the card's mic,
the queue pill's stack, and the queue sheet's pairing stems, §5.4), one that leads a control's data
(the Last Performed clock, the runline's calendar, the Superset partner's fork), or one that marks a
state beside its word (the Saved check, the danger mark).

## 2. Appearances & Color

### Appearance strategy

Two appearances ship: Day (`.day`), the primary, and Night (`.night`). The Settings preference is
System / Light / Night, and System follows iOS. Athlete-facing copy calls it Night, not Dark. Night
is a hand-lit value sheet, and no rule derives it from Day.

### Color roles

Views take semantic roles from the environment palette (`@Environment(\.themePalette)`), never a
paint or a literal. The token sheet lists every paint and role with its Day and Night value.

- Green words and glyphs on paper, and the system tint, take `actionInk`. The `action` greens stay
  fill and stroke colours, because as small text `actionNight` measures 1.9 to 3.7:1 on night paper
  and `actionDay` 4.0 to 4.4:1 on the queue sheet's darker foot. Settings action rows keep system
  blue (§5.9).
- The Log capsule is an `action` fill with cream text in both appearances. Mint fails the action
  role at night, where it reads as candy.

### Living paper (atmosphere)

Every page the app draws sits on living paper: the appearance's sage base pair under four radial
light washes, recipe in the token sheet. Sheets are living paper too, because bare cream reads too
white.

### Named Rules

**The Room Re-lights Rule.** Night is the same room re-lit, never recolored: hue-preserved deep sage
paper, foliage pigment for everything that grows, cream kept as the light source. No neutral black,
no new hues at night.

**The Green Means Action Rule.** The action greens are for the Log capsule, the current/selected
state, and progress that has actually happened, never decoration.

**The Light Is Not Flora Rule.** Warm washes, pools, and glows may shape the room; drawn plants may
not. The branch is the app's only flora. Flora in the branch's air is where wellness-journal drift
begins.

**The One Glow Rule.** Night carries exactly one glow, on the opening bud. The Log capsule's night
shadow is a soft green light, not a glow effect. Day's one delight is the Block grid's sunlit hour
(§5.5).

**The Sage-Cream Exception Rule.** Surfaces may be cream-tinted, but stay sage-led: never amber,
gold, orange, tan, or generic beige wellness styling.

## 3. Typography

Two bundled variable faces carry the type. Fraunces is the voice and speaks rarely. Source Sans 3 is
the instrument and carries everything else, numbers included. The token sheet's type roles give each
role's size, weight, and axes.

### Named Rules

**The One Voice Rule.** Fraunces sets the Exercise name, the Superset partner name, and the
ceremony, connect, and sheet titles. It never labels chrome, never sets numbers, and stays off
utility pages (Block grid, Settings, History chips).

**The Numbers Stay Plain Rule.** Every numeral role is bold and tabular (`tnum`), so loads, reps,
and RPE read as instrumentation. Loads, reps, RPE, Set counts, and sync state take no novelty
styling, gradient text, or decorative tracking.

**The Product Scale Rule.** Type sizes are fixed, because training surfaces never scroll and every
locked composition was validated at fixed proportions. System-owned surfaces (Settings, system
alerts, share sheet) keep native text styles and scale normally, and so does the app-drawn
destructive confirmation card (§5.9).

**The Shrink-Then-Truncate Rule.** Reference lines (Last Performed, history chips' text, runlines)
never wrap: shrink to a dense floor (≈11pt), then truncate. Chips may flow to a new line; text
itself never wraps.

## 4. Surfaces, Elevation & Radius

Depth is made of light: washes on the paper, cream surfaces at varying opacity, soft wide shadows by
day, and border-as-light by night. The Sunbird colophon's disc is the only glass (§6). Editorial
scaffolding stays off every surface: no ruled lines, uppercase microlabels, or hairline grids. At
rest, pills, rails, tiles, and chips are quiet cream fills with 1px strokes, and hierarchy comes
from fill, stroke, and type before any shadow.

### Radius family

Every corner comes from the named family in token sheet §6, plus `hairline 2–3`, and a nested
radius is concentric (inner ≈ outer − inset).

### Named Rules

**The One Soft Container Rule.** Radius `soft` belongs to the Active Set Card, the ceremony stats,
and sheet shoulders, and nothing else earns it. No cards inside cards; each layer has a distinct
job.

**The History Is Carved Rule.** Below-flat elevation exists only in the Exercise History sheet's
chips and in the pressed volume control, which borrows the chips' recipe. Everything else sits on or
above the paper.

## 5. Components

Each component's spec lives under its own number in a file beside the token sheet. Read the spec
for every surface you change.

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

Custom motion is confined to **three growth moments**, all on the wing ease. Every piece of chrome,
the Log capsule included, rides stock system springs. Do not add decorative motion.

The three moments' timings, the haptics, hold-to-skip timing, and reduced motion:
[docs/design/motion-and-haptics.md](docs/design/motion-and-haptics.md).

## 8. Every screen

- Reach the next logging action with one hand, and take a chalky thumb as the benchmark.
  Affordances stay visible, never chrome-on-demand.
- Prefer a self-describing glyph (X, back arrow, play, a pairing stem) to an action spelled out in
  words, give each icon-only control an accessibility label, and keep on-screen text to a minimum
  (operator ruling 2026-10-11).
- Settings, sheets, navigation, and text input keep their native iOS affordances.
- On-screen words are `CONTEXT.md`'s terms, never the synonyms its avoid-lists name.
- Text is solid ink, never a gradient, and no surface carries a side-stripe border.
