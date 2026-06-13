# ADR 0011: The Stage Session View

**Status:** Accepted
**Date:** 2026-06-12

## Context

The Session View had grown into a vertical scroll of every Exercise in the
Current Session — each a Title-scale section heading with its own Set rows, Last
Performed line, and Active Set Card. The logging flow inside a card (Active Set
Card → Smart Value Pills → Log) tested well, but the surrounding density did not:
on the gym floor the athlete is doing exactly one thing, yet the whole Session
competed for attention. The feedback was explicit — calm, peaceful, confident
while logging; only one card in focus at a time; keep the header HUD and the fast
logging flow.

PR 303 explored four single-Exercise layouts behind a Developer Tools switcher —
Focus Stack, Pager, Stage, and Rail (see
`docs/prototypes/session-view-prototypes.md`). They shared one coordinator and
the production logging flow, differing only in what surrounds the active
Exercise. Stage won on the "maximum calm" criterion: it shows the single action
and nothing else, with orientation available on demand rather than ambiently.

## Decision

Make **Stage** the one production Session surface. The Session renders exactly one
Exercise (or Superset) at a time as a "now playing" stage; everything else is
reachable but not on screen.

- **One stage at a time.** The stage shows the position label, Exercise name,
  coach note, a row of Set dots, the Last Performed reference line, and the
  Active Set Card / Logged Set Review Card. There is no scrolling list of Set
  rows and no stack of section-headed Exercises.
- **Orientation on demand.** A glass "Up next" bar and a queue button (labeled
  `N of M`) sit at the foot of the stage. The full Session — every Exercise, its
  progress, and any Superset — lives in a queue sheet at the `.medium` detent,
  opened from that button. Tapping a queue row jumps the stage to that item.
- **Open Exercises and Move On live in the queue sheet** (makeup work from
  earlier Sessions in the Current Week), and on the completion stage once every
  Set in the Session is logged. Both are gated on the athlete viewing the live
  edge of their plan.
- **Supersets are first-class.** An active Superset renders as its own stage.
  Pairing *creation* moved into the queue sheet: pick an Exercise, then its
  partner, and after a short confirmation the two fuse into one Superset stage; a
  paired stage can be dismissed back to two. This replaces the long-press grip
  flow that assumed the full production list.
- **Presentation is a tested deep module.** Stage resolution — which item is on
  stage, up-next selection, queue progress labels, completion summary, and
  pairing role — lives in `SessionStagePresentation` (Progress/), driven by the
  unchanged `SessionCoordinator.renderItems`, so the View layer stays thin and
  the stage logic is unit-testable without a running UI.
- **The header HUD and its overpull are unchanged.** The `SessionProgressHeader`
  glass HUD stays pinned, and both the HUD-drag and scroll-driven
  overpull-to-Settings gestures behave exactly as in the previous production
  view.

## Consequences

- The single-Exercise scroll components are no longer reachable and were removed:
  the `ExerciseSection` view and its orphaned `ExerciseSummaryRow` / `SetRow`
  rows, plus their visual baseline. `ActiveSupersetSection` and the Active Set /
  Logged Set / Smart Value Pills logging flow survive intact — Stage composes
  them directly.
- The Developer Tools "Session View Lab" switcher and all four prototype variants
  are deleted; Stage is no longer a variant but the surface itself.
- `SessionExerciseRenderConfig` still carries fields only the deleted scroll view
  consumed (`showsPairingGrip`, `isCollapsed`, `activeSetTransition`,
  `retiringTransition`, `isPairingConfirmation`). Pruning them touches many call
  sites and is deferred as a follow-up rather than bundled into this change.
- The domain glossary (CONTEXT.md) is unaffected — Superset, Open Exercise, and
  Move On are domain concepts the stage faithfully implements; Stage is a
  presentation decision, documented here and in DESIGN.md (§5 "Session Stage"),
  not a new domain term.

See PRD and slices: issues #304–#311; prototype exploration in PR 303.
