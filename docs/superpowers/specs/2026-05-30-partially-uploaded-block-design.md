# Partially Uploaded Block Design

## Goal

Let the athlete view and log any **Available Session** in a **Partially Uploaded Block** — a Block the coach has only partly populated — while clearly marking the **Unavailable Sessions** the coach has not yet uploaded as non-interactive in the Block grid.

The athlete should never be blocked from logging available work just because other days are empty, and should never be able to open, navigate to, or land on an empty day by accident.

## Background

The app treats a coach-managed Google Sheet as the source of truth and keeps a local cache. See [ADR 0001: Google Sheet as backend with local-first sync](../../adr/0001-sheet-as-backend-local-first.md). Each Block is one Sheet tab spanning 4 weeks × 4 days (16 Sessions).

Coaches frequently upload a Block **partially**: some Sessions have a complete set of Exercises, others have none yet. Crucially, the populated Sessions are **not contiguous**. The Block 28 snapshot (`S. Patel [Snapshot 20260529 - Block 28]`) has Day 1 populated for *all four weeks* plus Week 1 Day 2 — the rest empty:

|        | Day 1 | Day 2 | Day 3 | Day 4 |
|--------|-------|-------|-------|-------|
| Week 1 | ✅    | ✅    | ⬜    | ⬜    |
| Week 2 | ✅    | ⬜    | ⬜    | ⬜    |
| Week 3 | ✅    | ⬜    | ⬜    | ⬜    |
| Week 4 | ✅    | ⬜    | ⬜    | ⬜    |

In the Sheet, every empty day still carries its `Day N` label, date, and column headers — the **full 16-cell day skeleton is always present**. The only cell-level signal of "populated" is a non-empty Exercise-name cell in that day's name column. When the coach does upload a day, it is **complete** (no partial days).

Today the parser already builds a `Session` for every `Day N` header it finds, so empty days flow through as `Session`s with zero Exercises and the Block grid already renders 16 tiles. But there is no concept of availability: an empty day falls through `SessionProgressTracker.tileState` to `.incomplete`, rendering identically to a real not-yet-started day, and its grid tile is tappable.

Terms used here are defined in [CONTEXT.md](../../../CONTEXT.md): **Available Session**, **Unavailable Session**, **Partially Uploaded Block**, **Current Session**, **Move On**.

## Decisions

- **Decision: Availability is determined per Session, from whether it holds Exercises.** A Session is Available iff it has ≥1 Exercise; otherwise Unavailable. No contiguity is assumed.
  - Source: Block 28 data — Day 1 of every week is populated while Week 1 Days 3–4 are not, so any "lock everything after the first gap" rule is wrong.
  - Consequence: Availability is derived, not stored. No migration, no flag on the model.

- **Decision: Unavailable Sessions render as a distinct, polished, non-interactive grid tile.** Recessed/low-opacity frosted surface (no live glass effect), muted text, an icon plus the label "Not uploaded".
  - Source: Approved design discussion; must honor the Liquid Glass system ([ADR 0004](../../adr/0004-liquid-glass-design-system.md)) and read as intentional, not as a broken/disabled control.
  - Consequence: A new `SessionTileState.unavailable` case; the tile must pass `ui-screenshot-reviewer` on a fixture screenshot before the work is considered done.

- **Decision: Unavailable tiles are fully inert.** Tapping does nothing — no navigation, no feedback, no haptic.
  - Source: Approved design discussion. The "Not uploaded" label already explains why.
  - Consequence: The Block grid Button is disabled for Unavailable tiles.

- **Decision: Current Session is always an Available Session.** When no Session has been logged and no manual override applies, the default is the *first Available Session* in Block order rather than literally the first day.
  - Source: Approved design discussion. Closes the only automatic path to a broken (empty) Current Session.
  - Consequence: Zero behavior change for every real Block (Day 1 is always populated, so "first Available" equals "first" today). Implemented as a guarded fallback, not a rewrite.

- **Decision: Move On advances to the next Available Session, skipping Unavailable Sessions in between.** From Week 1 Day 2 it jumps to Week 2 Day 1.
  - Source: Approved design discussion (chosen over "stop at the first gap and drop to the grid").
  - Consequence: Move On can cross a Week boundary in a single action, which by the existing rule closes the prior Week and abandons its Open Exercises. This is the one surprising behavior and is documented here intentionally.

- **Decision: Move On is offered whenever any Session — Available or Unavailable — lies ahead in the Block; the celebration always fires.** When no Available Session remains ahead but Unavailable ones do, Move On celebrates and then navigates to the Block grid instead of advancing.
  - Source: Approved design discussion — Move On is the celebration moment, so finishing the last Available day must still celebrate.
  - Consequence: A fully-uploaded Block is untouched — on a complete Block's last day nothing lies ahead, so Move On stays hidden exactly as today. The terminal celebration is added *only* in the Partially Uploaded Block case.

## Scope

### In

- Per-Session availability derivation (`SessionProgressTracker`).
- `SessionTileState.unavailable` and its rendering in `SessionTile`.
- Disabling Unavailable tiles in `BlockOverviewView` / `BlockOverviewPresentation`.
- Current Session no-progress default = first Available Session.
- Move On skipping Unavailable Sessions to the next Available Session.
- Move On offered whenever any Session lies ahead, with terminal navigation to the Block grid when no Available Session remains ahead.
- A partially-uploaded-Block fixture scenario for tests and screenshots.
- Swift Testing coverage for tracker, presentation, and store behavior.

### Out

- Any change to Sheet parsing of populated days, Set logging, Last Performed, Open Exercise write contracts, or the makeup queue (Unavailable days hold no Exercises, so they cannot enter it).
- Synthesizing placeholder tiles for *missing* day/week headers — the full 16-cell skeleton is contractually always present.
- Surfacing a day that becomes Available *behind* the Current Session as a makeup (it remains reachable and loggable via the grid; no auto-surfacing).
- A new "end of block" celebration for fully-uploaded Blocks (their final-day behavior is unchanged).
- Handling partial *days* (coach uploads complete days).

## Current Architecture

`SheetLayoutInterpreter` creates a `SheetLayoutDay` for every `Day N` header column, regardless of Exercise rows. `SheetParser` maps each to a `ParsedSession`; `BlockBuilder` builds a `Session` with `exercises: []` for empty days. The Block grid therefore already has 16 tiles.

`SessionProgressTracker`:
- `tileState(for:currentSession:)` → `.complete` (non-empty sets, all logged/skipped), else `.current` (matches Current Session), else `.incomplete`. Empty days yield `.incomplete`.
- `currentSession(in:overrideOrder:)` → most recently logged Session, else `sessions.first`, with a manual override.
- `nextSession(after:in:)` → the Session at `order + 1`.

`WorkoutStore`:
- `canMoveOn` → `tracker.nextSession(after: currentSession) != nil`.
- `requestMoveOnCelebration()` guards on `nextSession != nil`, then shows the celebration.
- `dismissMoveOnCelebration()` → `advance(after:)`, which moves to `nextSession`, writes the override, and sets `displayedSession`.

`BlockOverviewView` renders each tile as a `Button` calling `show(week:day:)` — always enabled. The grid is reached via the `Week X · Day Y` location `NavigationLink` in `SessionProgressHeader`. `SessionView` shows `EmptyStateView` whenever `displayedSession` is `nil`.

## Target Architecture

### Availability

`SessionProgressTracker` gains a single predicate: a Session is Available iff `!session.exercises.isEmpty`. All availability logic derives from it; nothing is persisted.

### Tile state

`SessionTileState` gains `.unavailable`. `tileState` checks availability first: an Unavailable Session returns `.unavailable` before any complete/current/incomplete logic. `accessibilityValue` for `.unavailable` is "Not uploaded".

`SessionTile` renders `.unavailable` as a recessed frosted surface (no `glassEffect`), low opacity, muted text, with an icon + "Not uploaded". `Theme` gains the needed color/opacity constants. `BlockOverviewView` disables the tile's `Button` when the state is `.unavailable`.

### Current Session

`currentSession` default becomes "first Available Session in Block order" when nothing is logged. The "most recently logged" path is already safe (a logged Session has Exercises). A manual override is honored only if it resolves to an Available Session; otherwise the derived Current Session is used. If the Block has no Available Session, Current Session is `nil` and `SessionView` shows the existing `EmptyStateView`.

### Move On

`nextSession(after:in:)` is redefined as "the next **Available** Session in Block order after the given Session" (skipping Unavailable ones).

A new predicate "any Session lies ahead" (Available or Unavailable, by order) drives both `canMoveOn` and the `requestMoveOnCelebration()` guard, so Move On is offered — and the celebration fires — while any day remains ahead. (Today both gate on `nextSession != nil`; once `nextSession` means "next Available", that guard would wrongly suppress the celebration on the terminal day, so it must switch to the new predicate.)

`advance(after:)`:
- If a next Available Session exists → advance to it (write override, set `displayedSession`), as today.
- If none exists but the athlete chose Move On → emit a request to present the Block grid; do not change the override.

`WorkoutStore` exposes a navigation signal that `SessionView` binds to a `NavigationStack` destination so the grid can be presented programmatically after the celebration.

## Contracts

- [ADDED] `SessionTileState.unavailable` with `accessibilityValue` "Not uploaded".

- [CHANGED] `SessionProgressTracker.tileState(for:currentSession:)`:
  - Before: empty days fall through to `.incomplete`.
  - After: a Session with no Exercises returns `.unavailable`; all other states unchanged.

- [CHANGED] `SessionProgressTracker.currentSession(in:overrideOrder:)`:
  - Before: `logged.last ?? sessions.first`, override applied if present.
  - After: `logged.last ?? firstAvailableSession`; override applied only if it resolves to an Available Session; `nil` if no Available Session exists.

- [CHANGED] `SessionProgressTracker.nextSession(after:in:)`:
  - Before: the Session at `order + 1`.
  - After: the next Available Session in Block order (skips Unavailable Sessions).

- [ADDED] `SessionProgressTracker` predicate for "any Session ahead" (Available or Unavailable) used to gate Move On.

- [CHANGED] `WorkoutStore.canMoveOn` and the `requestMoveOnCelebration()` guard:
  - Before: both require a next (order+1) Session to exist.
  - After: both require only that any Session lies ahead in the Block (Available or Unavailable), so the celebration fires on the last Available day.

- [CHANGED] `WorkoutStore` Move On advance:
  - Before: always advances to `nextSession` and writes the override.
  - After: advances to the next Available Session if one exists; otherwise requests Block-grid navigation and leaves the override unchanged.

- [ADDED] `WorkoutStore` Block-grid navigation signal consumed by `SessionView`.

- [CHANGED] `BlockOverviewView` tile interactivity:
  - Before: every tile `Button` is enabled and calls `show(week:day:)`.
  - After: tiles with `.unavailable` state are disabled and inert.

- [UNCHANGED] Sheet parsing, Set logging, Last Performed, Open Exercises / makeups, and the manual `Make Current` flow (inert Unavailable tiles cannot be viewed, so `Make Current` can never target one).

## Migration Plan

### Phase 1: Availability + tile state

- Add the Available predicate, `SessionTileState.unavailable`, and the `tileState` change. Thread the new state through `BlockOverviewPresentation`.
- Acceptance: Unavailable Sessions report `.unavailable`; populated Sessions are unchanged.

### Phase 2: Current Session safety

- Change the no-progress default to first Available Session and guard the override to Available Sessions.
- Acceptance: a Block whose first day is empty resolves Current Session to the first Available day; a Block with no Available day resolves to `nil` (existing empty state). Real Blocks (Day 1 populated) are byte-for-byte unchanged.

### Phase 3: Move On

- Redefine `nextSession` as next Available; add the "any session ahead" gate; route `advance` to either the next Available Session or a Block-grid navigation request.
- Acceptance: from W1D2, Move On lands on W2D1; from the last Available Session with Unavailable days ahead, Move On celebrates then shows the grid; a fully-uploaded Block's final day still hides Move On.

### Phase 4: Rendering + UI verification

- Render the `.unavailable` tile (`SessionTile`, `Theme`) and disable its `Button` in `BlockOverviewView`. Add the partially-uploaded-Block fixture scenario.
- Acceptance: the grid clearly distinguishes Unavailable tiles; tapping one does nothing; the rendered tile passes `ui-screenshot-reviewer`.

## Acceptance Criteria

- [ ] A Session with ≥1 Exercise is Available; a Session with zero Exercises is Unavailable.
- [ ] The Block grid shows all 16 tiles; Unavailable tiles render with the distinct "Not uploaded" treatment and no live glass.
- [ ] Tapping an Unavailable tile does nothing (no navigation, no feedback).
- [ ] Current Session is never an Unavailable Session; with no logged progress it defaults to the first Available Session.
- [ ] A Block with no Available Session shows the existing "No session yet" empty state.
- [ ] Move On advances from W1D2 to W2D1 (skips Unavailable days).
- [ ] Move On is offered on the last Available Session when Unavailable days remain ahead; it fires the celebration and then navigates to the Block grid.
- [ ] A fully-uploaded Block's final-day behavior is unchanged (no Move On).
- [ ] Unavailable days never appear in the Open Exercises / makeup queue.
- [ ] No new Google Sheets write is created by any of this behavior.

## Testing Strategy

Use Swift Testing for tracker, presentation, and store contracts:
- `SessionProgressTracker`: `tileState` returns `.unavailable`; `currentSession` first-Available default and `nil` when none; override guarded to Available; `nextSession` skips Unavailable; "any session ahead" gate.
- `BlockOverviewPresentation`: emits `.unavailable` tiles with correct accessibility.
- `WorkoutStore`: `canMoveOn` reflects any-session-ahead; advance routes to next Available vs grid signal; the manual override path is unaffected.

Add a partially-uploaded-Block fixture scenario mirroring Block 28's fill pattern (Day 1 of all weeks + W1D2) for store/presentation tests and UI screenshots.

Run `swift test` for unit/component coverage. Use XcodeBuildMCP UI verification for the rendered Unavailable tile and the terminal Move On → grid navigation, and run `ui-screenshot-reviewer` on the Unavailable tile fixture.

## Open Questions

None.
