# ADR 0014: One Set Card, Two Modes

**Status:** Accepted
**Date:** 2026-07-18

## Context

The stage rendered two separate card implementations for the same three
weight/reps/RPE fields: `ActiveSetCard` → `SmartValuePills` for logging the
active pending Set, and `LoggedSetReviewCard` for editing an already-logged one.
The review card re-implemented the field pills from scratch, used a different
RPE picker (`RPEGrid`) than the logging card's `RPEScaleScroller`, and carried
its own focus machinery (`LoggedSetReviewEditableField`,
`LoggedSetReviewPillHitRegion` — the latter a no-op in practice). Editing a
logged Set therefore looked and behaved unlike logging one, and every field-UI
change had to be made twice. Both paths already converged below the view layer:
one `SmartValuePillsForm`, one `WorkoutStore.log` write, one Sheet upsert.

## Decision

`ActiveSetCard` is the one Set card, parameterized by a mode:

- **`.logging`** — the existing behavior: "Up next" header, Exercise name row,
  and the hold-to-skip Log button as the explicit commit trigger.
- **`.reviewingLogged`** — the edit surface for a logged Set: "Set Log" header
  with the Saved confirmation and a collapse chevron, no Log button, and a
  silent commit — any changed, valid draft is written when the card leaves the
  screen. An Unstructured Set Log's original text stays visible as reference
  while its structured replacement is edited.

Mode-derived facts (header status text, reference text, whether log controls
show, whether changes commit on disappear) live in `SetCardPresentation`
(Progress/), the unit-testable seam. Both modes share `SmartValuePills`
unchanged fields and the single `RPEScaleScroller` picker.

Deleted as a consequence: `LoggedSetReviewCard`, `RPEGrid` (and its
presentation types), `LoggedSetReviewPresentation`,
`LoggedSetReviewEditableField`, and `LoggedSetReviewPillHitRegion`. The
legacy-log read-only rendering is gone with them: a review card is always
editable through the shared form.

## Consequences

- Field UI, validation display, and RPE selection are implemented once; the
  review path can no longer drift from the logging path.
- Editing keeps its distinct commit semantics (auto-commit on collapse, no rest
  timer, no focus advance) — those were always coordinator decisions
  (`updateLoggedSet` vs `log`) and are untouched.
- The RPE grid interaction is retired; editing RPE uses the same scroller as
  logging.
- ADR 0011's mention of the "Logged Set Review Card" now reads historically:
  the stage still shows a review state, but it is a mode of the Active Set
  Card, not a second card.
