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
is derived from Day by The Mirror Rule below, so no Night pigment is picked by hand.

### Color roles

Views take semantic roles from the environment palette (`@Environment(\.themePalette)`), never a
paint or a literal. The token sheet lists every paint and role with its Day and Night value.

Every pigment is a step of one of three OKLCH ramps, each on a single hue: `sage` (the tinted
neutral, H 148), `leaf` (the action green, H 156), and `ember` (destructive, H 27). Steps run 50
to 950 evenly spaced in lightness, so a contrast gap is a step gap. Every step sits inside sRGB.

- Text roles come in three tiers: `textPrimary` (sage 950), `textSecondary` (sage 800), and the
  green `actionInk` (leaf 800) for words that confirm or link, Saved included. Greens that are not
  words are `action` (leaf 700), the mark (a selected chip's ring, the prescription tick, a logged
  Set's dot), and `actionFill`, the fill under cream text (the Log capsule, Move On).
- The Log capsule is an `actionFill` with cream text in both appearances, leaf 700 by Day and leaf
  600 by Night.
- `danger` is ember 800 by Day and ember 200 by Night, for the invalid weight, the danger mark, and
  Developer Tools' Conflict. Settings action rows keep system blue and Sign Out keeps system red
  (§5.9).
- No warning or success hue ships, because no screen draws a warning, and a logged Set's success is
  the green growth itself.

### Living paper (atmosphere)

Every page the app draws sits on living paper: the appearance's sage base pair under four radial
light washes, recipe in the token sheet. Sheets are living paper too, because bare cream reads too
white.

### Named Rules

**The Room Re-lights Rule.** Night is the same room re-lit, never recolored: hue-preserved deep sage
paper, the leaf ramp for everything that grows, cream kept as the light source. No neutral black,
no new hues at night.

**The Mirror Rule.** A pigment is named once, as a ramp step. An ink or a mark reads the mirror
step at Night (200 ↔ 800, 300 ↔ 700, 50 ↔ 950). A fill reads one step lighter and keeps its text,
because a mirrored fill would be the brightest object on the Night page. The leaf ramp keeps 75% of
its chroma at Night so it does not vibrate on the dark paper. Lights do not mirror: cream, the
paper pair and its washes, the bud's rim, and the colophon glass stay literals. A role that cannot
pass contrast at Night changes its Day step, never only its Night one. Operator brief, 2026-10-31: "Where Emil's recommendation conflicts with an existing rule in DESIGN.md, PRODUCT.md, or a past operator decision, Emil wins."

**The Ink Is Not the Fill Rule.** Words take an ink role (`textPrimary`, `textSecondary`,
`actionInk`, `danger`), marks take `action`, and fills take `actionFill`. One green that is a
button fill, a mark, and small text fails one of them in one appearance. Same approval as The
Mirror Rule.

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

**The Product Scale Rule.** Text scales with Dynamic Type, up to `.xxxLarge`, the largest standard
size, on every app-drawn screen. Each type role keeps its size at the default content size and grows
along one system text style's curve (`Theme.TypeScale`), so every locked composition holds at the
default. At `.xxxLarge` the two-Exercise Session keeps its coach note and Last Performed, and the
sheets keep their proportions. Past it, at the accessibility sizes, text stays at `.xxxLarge` and the
stage's fixed-size controls (steppers, rail cells, queue pill) show the Large Content Viewer on a long
press. App-drawn screens still wrap or scroll rather than clip. System-owned surfaces keep native text
styles. Card Holds Still (§5.2) holds within a Session, not across content sizes. Supersedes fixed
sizes, under "Where Emil's recommendation conflicts with an existing rule in DESIGN.md, PRODUCT.md, or
a past operator decision, Emil wins." (operator, 2026-10-31). The cap reaches every screen because the
uncapped sheets at AX5 looked "horribly large" and the operator said "apply" to capping them
(2026-10-31).

**The Shrink-Then-Truncate Rule.** Reference lines (Last Performed, history chips' text, runlines)
never wrap: shrink to a dense floor (≈11pt), then truncate. Chips may flow to a new line; text
itself never wraps.

## 4. Surfaces, Elevation & Radius

Depth is made of light: washes on the paper, cream surfaces at varying opacity, layered soft shadows
by day, and a single ring of light by night. The Sunbird colophon's disc is the only glass (§6).
Editorial scaffolding stays off every surface: no ruled lines, uppercase microlabels, or hairline
grids. Hierarchy comes from fill and type first; elevation says what is raised, never decorates.

### Elevation scale

Five levels, lowest first. Each is a `Theme.BoxShadow` recipe in the token sheet, drawn through
`themeElevation`. A surface takes the level of what it is, never a one-off shadow.

| Level | Who sits there | Day | Night |
| --- | --- | --- | --- |
| Carved | History chips, the pressed volume control | inset shade + light lip | same recipe, night values |
| Flat | Rails, tiles, chips at rest | fill only | fill only |
| Raised control | Steppers, queue pill, the queue sheet's header button, the countdown pill, the volume control | 1px ink edge @ 8% + `cardLow` | 1px cream ring @ 14% |
| Card in shade | Collapsed week cards, Sheet tab Day cards | 1px ink edge @ 6% + `cardLow` | 1px cream ring @ 10% |
| Lifted card | Active Set Card, ceremony stats, Settings confirmation card | 1px ink edge @ 5% + crisp and wide drops | 1px cream ring @ 10% |

Three named lights sit outside the scale: the Log capsule's light, the focus card's sun halo (at
Night, a cream ring @ 14%, brighter than the week cards' edge), and the current tile's glow. A
halo's reach is part of its card's footprint, so neighbours keep their spacing from the light.

### Radius family

Every corner comes from the named family in token sheet §6, plus `hairline 2–3`. Sheets take the
system's own corners.

### Named Rules

**The Edge Is Light Rule.** A raised surface (a card, a container, a control you press) shows its
edge with a translucent 1px ring from its elevation level, never a solid stroke. Day rings are ink
at low opacity, so one token sits right on every wash; Night collapses every drop to one cream ring,
because a drop shadow vanishes on deep sage. Real strokes stay where they separate or state: text
field edges, the selected rail chip's ring, tile state outlines, the dashed empty bed, and the
logged-Set and dictation capsules. (Supersedes "at rest, pills, rails, tiles, and chips are quiet
cream fills with 1px strokes" for raised controls. Operator brief 2026-10-31: "Where Emil's
recommendation conflicts with an existing rule in DESIGN.md … Emil wins.")

**The Concentric Corner Rule.** A container whose corner holds a rounded child takes that child's
radius plus the inset between them, so the two curves run parallel. The container grows to meet the
child; the child keeps its shape. The Active Set Card is 43 (the Log capsule's ≈29 half-height plus
the 14 bottom inset) and the focus card is 31 (tile 15 plus 16). A container with no child in its
corner picks its radius on its own merits. (Supersedes the One Soft Container Rule's claim on the
Active Set Card and sheet shoulders. Operator brief 2026-10-31, as above.)

**The No Nested Cards Rule.** No cards inside cards; each layer has a distinct job.

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

Motion is feedback, never decoration: each move answers the athlete's hand, shows where something
went, or bridges a change that would otherwise jump. These rules replace the three-growth-moments
rule under the operator's brief of 2026-10-31: "Where Emil's recommendation conflicts with an
existing rule in DESIGN.md, PRODUCT.md, or a past operator decision, Emil wins."

**The Ink Answers the Hand.** The leaf and bud a log or a skip changes start moving on the frame its
haptic lands, on the ink ease, a strong ease-out. The rest of the stage rides one critically damped
spring, and nothing a tap causes rides an ease-in curve. The wing ease eases in, so
it belongs to the Move On ceremony alone.

**Frequency Sets the Budget.** What the athlete sees every Set, the leaf, the bud, the press, and the
header's count, finishes inside 0.42 s. Occasional surfaces such as a confirmation card take about
0.2 s. Only the rare moments, the Move On ceremony and onboarding, may run longer.

**The Press Sinks.** The Log capsule, the weight steppers, and every primary capsule sink to 0.97
on touch-down on the snappy press spring, and return when the finger lifts or leaves.

**Exits Are Quieter.** A surface the athlete dismisses leaves faster than it came, about 0.15 s
against 0.2 s, along the path it entered by.

**One Entrance.** A view plays one entrance. A beat or a pulse that would land on top of a reveal is
cut.

Sheets, navigation, and system controls keep their stock iOS motion. Under Reduce Motion the branch,
the ceremony, the confirmation card, and onboarding cross-fade instead of moving, and the branch
re-laying out cuts.

The timings, the haptics, hold-to-skip timing, and Reduce Motion in full:
[docs/design/motion-and-haptics.md](docs/design/motion-and-haptics.md).

## 8. Every screen

- Reach the next logging action with one hand, and take a chalky thumb as the benchmark.
  Affordances stay visible, never chrome-on-demand.
- Prefer a self-describing glyph (X, back arrow, play, a pairing stem) to an action spelled out in
  words, give each icon-only control an accessibility label, and keep on-screen text to a minimum
  (operator ruling 2026-10-11).
- Every tappable control has a hit area of at least 44×44pt that overlaps no neighbour's. Grow a
  short control's frame inside its Button and give the space back outside, so the layout does not
  move; where neighbours sit closer than 44pt, each takes its non-colliding share, as the branch
  leaves do. Emil's rule, under "Where Emil's recommendation conflicts with an existing rule in DESIGN.md, PRODUCT.md, or a past operator decision, Emil wins." (operator, 2026-10-31).
- Settings, sheets, navigation, and text input keep their native iOS affordances.
- On-screen words are `CONTEXT.md`'s terms, never the synonyms its avoid-lists name.
- Text is solid ink, never a gradient, and no surface carries a side-stripe border.

**The One Edge Rule.** The Session stage, the Block grid, and the empty state hang every row on one
left edge, `Theme.pageMargin` (16pt) in from the screen: the runline, the Exercise name, the
Active Set Card, the stage foot, the sync banner, and the week cards. A container insets its own
content by its padding, never by a second page margin. The completion stage's title sits where an
Exercise name sits. The Move On ceremony keeps its own centered column (§5.7).

**The Bare Count Rule.** A count is a bare number unless the screen can't be read without a word
beside it. A week card reads `2 of 4`, because the tiles beside it already show what is counted.
When a count does need a word, it is the `CONTEXT.md` term, capitalized, and the same on every
screen: a Set still to do is `left` (`5 Sets left`, `1 Set left` on an Open Exercise and on the Live
Activity), and a finished Session counts what it holds (`5 Sets across 3 Exercises`), never `done`,
which the Set State avoid-list bars. The operator, 2026-10-31, on a week card that read
`0 of 4 Sessions`: "I hate this, please prefer no descriptor text unless absolutely necessary."

**The Empty State Speaks Plainly Rule.** An empty state is a title, one or two short sentences that
say what is missing and what happens next, and the one action that recovers. It carries no
illustration: a stock glyph like a dumbbell is the generic-fitness clip art `PRODUCT.md` turns away.

These three rules came from the layout and hierarchy pass, under the operator's brief of
2026-10-31: "Where Emil's recommendation conflicts with an existing rule in DESIGN.md, PRODUCT.md,
or a past operator decision, Emil wins. Update DESIGN.md (through the product-design skill's
feedback loop) so the new rule is written down".
