# Current Session Manual Override Spec

## Goal

Add an explicit manual override for Current Session so an athlete can view any Session from Block Overview and intentionally make that viewed Session the app's Current Session.

The change preserves safe, view-only navigation by default: tapping a Session tile continues to view that Session only. The Current Session changes only when the athlete taps `Make Current`.

## Background

The app currently treats the Google Sheet as the workout data source of truth and keeps a local cache for offline use. See [ADR 0001: Google Sheet as backend with local-first sync](../../adr/0001-sheet-as-backend-local-first.md).

Current Session is derived by `SessionProgressTracker` from the latest Session with logged progress, with a local forward-only `advancedToOrder` override for Move On. `WorkoutStore` owns the displayed Session and currently exposes separate concepts:

- `currentSession`: the derived live Session, optionally advanced forward by Move On.
- `displayedSession`: the Session currently being viewed.
- `show(week:day:)`: changes only `displayedSession`.
- `showCurrent()`: returns `displayedSession` to `currentSession`.
- `moveOn()`: persists a forward-only override and advances both `currentSession` and `displayedSession`.

The approved design direction: while viewing a non-current Session, show two distinct Liquid Glass pills, `Go back` and `Make Current`.

## Decisions

- Decision: Block Overview tile taps remain view-only.
- Source: Approved design discussion.
- Consequence: No tile tap may directly change Current Session.

- Decision: The non-current viewing state exposes two separate pills: `Go back` and `Make Current`.
- Source: Approved design discussion.
- Consequence: The old full-width `Back to Current Session` banner should be replaced for this state by the two-pill control surface.

- Decision: The action label is `Make Current`.
- Source: Approved terminology decision.
- Consequence: Do not use icon-only controls, `Current`, `Set Current`, `Set as Current`, `Use This Session`, or `Resume Here`.

- Decision: Manual Current Session override is local app state, not Sheet data.
- Source: ADR 0001 and existing Move On override behavior.
- Consequence: `Make Current` must not enqueue a Sheet write.

- Decision: `Make Current` should work for any displayed Session in the current Block, including Sessions behind derived logged progress.
- Source: The approved behavior says the viewed Session becomes Current Session.
- Consequence: The existing forward-only `advancedToOrder` contract is insufficient by itself.

## Scope

### In

- Persisting a local manual Current Session override for the current Block.
- Showing `Go back` and `Make Current` only while viewing a non-current Session.
- Keeping Block Overview tile navigation view-only.
- Updating Current Session derivation so a manual override can point backward or forward within the current Block.
- Preserving Move On behavior as an explicit advance from the current Session.
- Tests for store behavior, presentation visibility, and UI integration where the project already has coverage hooks.

### Out

- Writing manual Current Session state to Google Sheets.
- Multi-athlete sync or cross-device propagation of manual Current Session state.
- Changing Set Log, Last Set RPE, Open Exercise, or Last Performed write contracts.
- Redesigning Block Overview tiles.
- Adding developer tools.

## Current Architecture

`SessionProgressTracker` computes the current Session from logged Set progress. If there is no logged progress it returns the first Session. It accepts `advancedToOrder` but applies it only when the stored order is ahead of the derived Session.

`WorkoutStore` owns local navigation state. It stores the Move On override in `UserDefaults` under `advancedToOrder_<tabName>`. Reloading the store preserves a non-current `displayedSession` by week/day when requested, otherwise it resets `displayedSession` to `currentSession`.

`SessionView` uses `workout.isViewingLiveEdge` to decide whether it is viewing Current Session. Today, a non-current Session shows `BackToCurrentSessionBanner`, a full-width accent banner above `SessionProgressHeader`. `Move On` and Open Exercises only appear on the live edge.

`BlockOverviewView` receives the current Session for tile presentation. Tapping a tile calls `workout.show(week:day:)` and dismisses back to SessionView.

## Target Architecture

`WorkoutStore` remains the owner of manual Current Session state and displayed Session state.

Current Session derivation becomes:

1. Derive the Sheet-progress Session with `SessionProgressTracker`.
2. If a valid manual override exists for the current Block, use that Session as Current Session until the athlete changes it with `Make Current` or `Move On`.
3. Otherwise, use the derived Session.

Move On continues to advance from the current Session, but it should write through the same manual override mechanism instead of a forward-only interpretation. That keeps one local Current Session override contract instead of parallel override meanings.

When `displayedSession` differs from `currentSession`, the UI shows a compact top-right override surface:

- `Go back`: calls `showCurrent()`.
- `Make Current`: calls a store action that sets the displayed Session as Current Session and leaves it displayed.

The old non-current full-width banner is removed once the two-pill control surface covers its behavior.

## Contracts

- [CHANGED] Current Session derivation:
  - Before: latest logged Session, optionally advanced forward by `advancedToOrder`.
  - After: latest logged Session unless a valid block-scoped manual override points to a Session in the current Block.

- [ADDED] Manual override store action:
  - A `WorkoutStore` API makes the currently displayed Session, or a passed Session, the Current Session.
  - It persists the target as a block-scoped Session order.
  - It leaves `displayedSession` on the same Session.
  - It clears non-current preservation state because the displayed Session is now live.
  - It is applied even when Sheet-derived logged progress points to a later Session.

- [CHANGED] Move On override:
  - Move On persists the next Session as the same manual Current Session override.
  - Move On still refuses to advance past the last Session.

- [CHANGED] Non-current Session controls:
  - Before: full-width `Back to Current Session` banner.
  - After: two distinct top-right Liquid Glass pills, `Go back` and `Make Current`.

- [REMOVED] Full-width non-current Session banner:
  - Remove it once the two-pill controls exist and are covered by tests.

- [ADDED] Accessibility labels:
  - `Go back` must communicate that it returns to Current Session.
  - `Make Current` must communicate that it makes the viewed Session Current Session.

- [ADDED] Direct `Make Current` behavior:
  - `Make Current` acts immediately, with no confirmation prompt.
  - The UI must update immediately so the viewed Session no longer appears as non-current.

## Migration Plan

### Phase 1: Store Contract

- Change: Add a block-scoped manual Current Session override contract in `WorkoutStore` and route Move On through it.
- Compatibility: Existing `advancedToOrder_<tabName>` values should continue to work as manual override orders.
- Acceptance criteria:
  - A manual override can point behind derived logged progress.
  - Move On still advances Current Session and displayed Session.
  - Sheet-derived logged progress does not replace a valid manual override until the athlete changes the override.

### Phase 2: Non-Current Controls

- Change: Replace the non-current banner with the two-pill `Go back` / `Make Current` control surface.
- Compatibility: `Go back` preserves the old banner behavior.
- Acceptance criteria:
  - Viewing Current Session does not show the pills.
  - Viewing a different Session shows both pills.
  - `Make Current` updates Current Session and keeps the viewed Session displayed.

### Phase 3: UI Verification

- Change: Add or update UI coverage around Block Overview navigation and the manual override flow.
- Compatibility: Existing Block Overview tap-to-view behavior remains unchanged.
- Acceptance criteria:
  - A tile tap views a Session without making it Current.
  - The user can make the viewed Session Current from SessionView.
  - The app remains readable with supported Dynamic Type sizes.

## Deletion Criteria

- The full-width `BackToCurrentSessionBanner` can be deleted after `Go back` has equivalent store behavior and UI test coverage.
- Any forward-only helper naming such as `advancedToOrder` can be renamed or hidden after existing persisted values are still read correctly.

## Acceptance Criteria

- [ ] Tapping a Block Overview Session tile views that Session without changing Current Session.
- [ ] Viewing a non-current Session shows separate `Go back` and `Make Current` pills.
- [ ] `Go back` returns the displayed Session to Current Session.
- [ ] `Make Current` makes the displayed Session the Current Session and leaves it displayed.
- [ ] Manual override can target a Session behind derived logged progress.
- [ ] Sheet-derived logged progress does not replace a valid manual override until the athlete changes it.
- [ ] Move On still advances Current Session and displayed Session.
- [ ] No Google Sheets write is created by `Make Current`.

## Testing Strategy

Use Swift Testing for store and presentation contracts. Add focused tests around Current Session derivation, manual override persistence, reload behavior, and Move On compatibility. Use existing UI integration coverage for Block Overview navigation and visible controls where practical.

Run `swift test` for unit/component coverage. Use XcodeBuildMCP UI verification only for rendered SwiftUI behavior that `swift test` cannot cover.

## Open Questions

None.
