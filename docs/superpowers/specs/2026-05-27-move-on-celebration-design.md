# Move On Celebration

**Date:** 2026-05-27
**Status:** Approved
**Builds on:** `2026-05-27-session-progress-strip-design.md`

## Problem

The athlete needs an emotionally satisfying close-out moment when they choose
to leave the Current Session. That moment matters even when life prevents a
perfect Session. The app should celebrate the explicit decision to Move On
without treating incomplete work as failure and without auto-advancing when the
Session merely reaches 0 left.

## Decision

Add a full-screen `Move On Celebration` shown after the athlete taps `Move On`.

Reaching 0 left does not show the celebration, close the Session, or advance to
the next Session. At 0 left, the Session stays reviewable so the athlete can
correct an accidental Set Log or inspect the work before closing. The screen may
quietly show `0 left` and a full progress rail, but `Move On` remains the
explicit close-out action.

## Celebration Flow

1. The athlete taps `Move On`.
2. The app captures a presentation snapshot for the displayed Current Session.
3. A full-screen stamp-style celebration appears over the current Session.
4. The athlete taps anywhere on the celebration.
5. The celebration dismisses and the app advances to the next Session.

`WorkoutStore.moveOn()` remains the state-advance operation. It is invoked only
after the celebration is dismissed, not when the overlay first appears.

## Visual Design

The celebration uses the previously chosen stats summary layout:

- Stamp checkmark at the top.
- `Week N` label.
- `Day X Done` heading.
- Stats row: `Sets` | `Exercises` | `Left`.
- One randomly selected approved quote that remains stable for that celebration
  display.
- `Tap anywhere to continue` hint.

The stamp should feel decisive: a bold checkmark slams in with expanding ripple
rings, consistent with the app's mint/emerald motion language.
The celebration should keep the app's dark green gradient visible; avoid a
full-screen gray material veil that mutes the screen.

## Copy Rules

The celebration primarily celebrates closure, not perfection.

When Sets remain Pending:

- Subline: `Moved on with N left`.
- Stats row third column: `N` / `Left`.

When no Sets remain Pending:

- Subline: `Perfect session`.
- Stats row third column: `0` / `Left`.
- The animation and haptics use the richer perfect-session treatment.

Use `left` for athlete-facing UI copy. The domain model still uses the `Pending`
Set State for unfinished Sets.

## Quotes

Select one quote at random from these exact quotes when the celebration appears,
then keep that quote stable until the celebration is dismissed:

- "You're fucking amazing."
- "God damn!"
- "Get it girl!"
- "Shake it!"

## Haptics

- Normal Move On Celebration: success notification haptic.
- Perfect session: success notification haptic plus an additional impact beat.

## Architecture

Use a SwiftUI overlay owned by `SessionView`.

Recommended units:

- `MoveOnCelebrationPresentation`: pure value type containing Week/Day text,
  stats, subline, quote, accessibility text, and perfect-session flag.
- `MoveOnCelebrationView`: visual overlay for stamp/ripple animation, stats,
  quote, tap-anywhere dismissal, and accessibility.
- `SessionView`: captures the presentation when `Move On` is tapped, shows the
  overlay, fires haptics, and calls `workout.moveOn()` after dismissal.
- `WorkoutStore`: remains focused on Session state and does not own celebration
  UI behavior.

Do not introduce a separate navigation route, persistent coordinator, or effects
engine for this slice. A Canvas implementation is acceptable only if pure
SwiftUI cannot produce a convincing stamp/ripple during visual verification.

## Accessibility

The celebration should expose a clear accessibility label and value describing
the closed Session and stats. The dismissal action should be discoverable as the
way to continue to the next Session.

## Verification

Before implementation is considered complete, verify:

- Reaching 0 left does not automatically show the celebration.
- Reaching 0 left does not advance the Current Session.
- Tapping `Move On` shows the celebration before advancing.
- Tapping anywhere on the celebration dismisses it and advances.
- Incomplete Sessions show `Moved on with N left`.
- Perfect Sessions show `Perfect session`, `0 Left`, and the richer haptic beat.
- The stats row is `Sets · Exercises · Left` in both incomplete and perfect
  cases.
- The stable random quote uses the approved quote list.
- Existing `WorkoutStore.moveOn()` tests still prove advancement behavior.
- iOS simulator verification confirms the overlay, animation, layout, and no
  text overlap on the target device family.
