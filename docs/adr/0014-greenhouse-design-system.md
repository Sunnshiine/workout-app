# ADR 0014: Greenhouse Design System

**Status:** Accepted — supersedes ADR-0004 (Liquid Glass design system)
**Date:** 2026-07-19

## Context

The app's visual system grew out of ADR-0004's Liquid Glass adoption and the
subsequent "Warm Training Cockpit" direction (deep green/black dark mode with
mint action states, a softened Sage Light, glass surfaces on a fixed two-stop
gradient). The visual-redesign map
([#408](https://github.com/Sunnshiine/workout-app/issues/408)) set out to
find a deliberate departure — a new design direction validated through
prototypes on the iPhone 17 Pro simulator, with the Sunbird mark woven into
the app itself. Eighteen tickets converged on **Greenhouse**: a warm,
light-filled room built for growth.

## Decision

Greenhouse replaces the Warm Training Cockpit as the design system. DESIGN.md
encodes the system; `docs/design/greenhouse-theme-tokens.md` records the
decided token values. The decisions that supersede ADR-0004:

### Material language: living paper, not Liquid Glass

Liquid Glass is retired as the app's surface language. Surfaces are cream
fills at varying opacity on **living paper** — a layered wash recipe (base
sage gradient pair under four radial light washes) per appearance — with soft
wide shadows by day and border-as-light at night. The single surviving glass
element is the Sunbird colophon's disc. The `WorkoutGlass` helper's
vocabulary no longer describes product surfaces and is expected to shrink to
the colophon during the build.

### Appearances: Day and Night, hand-lit

Exactly two appearances ship — `.day` (primary) and `.night`, the same room
re-lit, never recolored. Night is a hand-lit value sheet, not derived from
day (mint fails the night action role; growth elements re-light to foliage
green). The five legacy palettes are retired; `-WORKOUT_THEME` accepts only
`day` and `night`.

### Token architecture

A small paint box plus flat semantic roles, consumed via the environment
palette. Most roles are paint @ opacity; wash recipes, glows, and one
deliberate literal (`tileCurrentBorder #1F8552`) are honest exceptions.

### Typography

Two bundled variable fonts replace all-SF-Pro: **Fraunces** (pinned `SOFT
100, WONK 0, wght 490`) as the voice — Exercise name and ceremony only — and
**Source Sans 3** as the instrument, every numeral bold + tabular. All text
styles route through a single `Theme.type` role table, lint-enforced. Fixed
sizes survive (the Product Scale Rule), now derived from the single-page
principle: training surfaces never scroll.

### Radius family

A named concentric family (`capsule ∞ · soft 30 · focusCard 24 · card 20 ·
rail 18 · tile 15 · cell 14 · mini 6 · hairline 2–3`) replaces the
8 / 16 / 28 scale.

### Signature elements

The **living stage** (Set progress as a branch that leafs out per logged
Set, with plain-text guardrails), growth performed only in the Move On
ceremony, one icon per page, and the Sunbird governed by three rules (The
Mark Stays Whole · The Wing Is Timing · The Two Perches). Custom motion is
confined to three growth moments on the wing-curve ease; haptics are Crisp,
silent-chrome, semantic-only.

### What ADR-0004 decided that still stands

- **iOS 26 minimum, no availability gates.**
- **Selective application** — the "glass everywhere" anti-pattern warning
  generalizes: Greenhouse spends its delights (glow, sunlit hour, ceremony)
  just as sparingly.
- **System chrome stays native** (navigation, Settings, sheets, text input).
- **Theme.swift as the single styling seam** — strengthened: tokens, the
  type role table, and motion/haptic constants all live behind it,
  lint-enforced.

## Consequences

- DESIGN.md is rewritten around Greenhouse; the Warm Training Cockpit
  document is replaced, carrying forward only its anti-regression
  Do/Don'ts and still-valid behavioral rules.
- The screen-by-screen implementation is a separate effort (the /to-spec
  handoff): Theme.swift reshaping, font bundling and `tnum` plumbing, the
  SwiftLint font rule, night values flagged for build-time validation
  (Exercise History sheet, Block grid), and an error-state pass on `danger`.
- Visual-regression baselines (ADR-0007) will need wholesale re-capture as
  screens adopt Greenhouse.
- Prototype assets and elimination trails live on the map's ticket branches
  under `docs/design/`, linked from
  [#408](https://github.com/Sunnshiine/workout-app/issues/408).
