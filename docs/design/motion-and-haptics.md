# Design System: Motion & Haptics (DESIGN.md §7)

Part of [DESIGN.md](../../DESIGN.md) §7, whose rules this serves. A § number names a section of
DESIGN.md or of one of its component files, which keep its numbering. The timings below changed
under the operator's brief of 2026-10-31: "Where Emil's recommendation conflicts with an existing
rule in DESIGN.md, PRODUCT.md, or a past operator decision, Emil wins."

## Curves

- **Ink ease** `cubic-bezier(0.23, 1, 0.32, 1)`: everything a log or a skip causes on the branch.
  It covers about 40% of its travel in the first tenth of its duration, so the leaf moves on the
  frame the log's haptic lands.
- **Wing ease** `cubic-bezier(0.46, -0.09, 0.83, 0.32)`: the Move On ceremony's stem alone. It eases
  in, so nothing a tap causes rides it.
- **Press spring**: SwiftUI's snappy spring, 0.16 s, to a 0.97 scale.
- A view already on screen that moves, such as the branch re-laying out, rides a critically damped
  smooth spring.

## The branch

1. **Leaf inks on log**: 0.3 s on the ink ease. A dashed Skip draws in the same language. On a
   Superset the leaf inks at once under its bud, and the bud lifts off over the 0.12 s before the
   partner's bud wakes, so the logged node never empties and the stage never shows two cream leaves.
2. **Next bud wakes**: inside the leaf's tail. It starts 0.12 s in, when the leaf is about 93% inked,
   and runs 0.3 s, so the whole log finishes at 0.42 s. **One Log, One Fill:** the transition must
   read as the cream bud waking (logging then inks it solid), never a second leaf filling.
3. **Ceremony**: stem 1.0 s on the wing ease, a 0.10 s beat, the bird drops in 0.35 s (about 1.5 s,
   Brisk). The overlay fades in on a 0.2 s ease-out and out in 0.15 s.

## Chrome

- A log, a skip, or a tap on a Set moves everything outside the branch and the card, such as the
  Exercise name when the stage changes Exercise, on one 0.3 s smooth spring. The Active Set Card
  holds still across it (§5.2), and so does the Last Performed line above it, so the old and new
  lines never draw over each other.
- The header's `N Sets left` rolls its numeral on a 0.2 s snappy spring as a log or skip changes it.
- The rest pill fades in once Up next has faded out. Its restart beat, 2.5% larger and brighter for
  about 0.16 s, plays only when a rest restarts under a pill already showing, never on its reveal.
- The destructive confirmation card rises from 0.96 over a fading scrim on a 0.2 s ease-out, and
  both leave in 0.15 s.
- Onboarding's steps cross-fade on a 0.3 s smooth spring, and the URL card and the sheet picker each
  drift 24 pt toward their own side, the way the Back chevron points.
- Sheets and navigation keep their stock presentation.

## Haptics

Haptics are **Crisp, silent-chrome, semantic-only**: RPE detent tick 0.35/0.85 · log 1.0/0.65 ·
skip dud 0.45/0.15 · stepper ± 0.45/0.80 (the floor hits the dud) · one identical swell-and-peak
Move On pattern timed to the ceremony · none on form fields. A haptic and the motion it confirms
start on the same frame. Hold-to-skip: reveal 250ms, commit 850ms, retreat 0.2s; logged-state hold
900ms. A Skipped Set's capsule takes no hold: a tap logs it, and its More menu clears it (#820).

## Reduce Motion

**Reduced motion** turns the leaf ink and the bud wake into 0.2 s crossfades to their end states,
so both appear in place. The bud's crossfade starts as the leaf's ends, so the stage never shows two
cream leaves. A Superset bud lifts off its ink in the same 0.2 s, before its partner's bud wakes.
The ceremony fades in fully grown. The confirmation card and onboarding's steps only cross-fade. The
press scale stays, because it moves under the athlete's own finger. Haptics are unaffected.

Reduce Motion leaves the Active Set Card unchanged (§5.2), except that the mic glyph cuts to its
listening fill instead of running the system replace. Its box holds still, and what moves inside it
answers the athlete's own finger.

The header's numeral crossfades under Reduce Motion.
