# Session Progress Strip

**Date:** 2026-05-27
**Status:** Approved
**Builds on:** `2026-05-26-active-set-visual-direction.md`

## Problem

The current top label, `Block · W1 D1`, is useful before selecting a Session but
low-value once the athlete is actively logging. During the Session, the athlete
needs a quick sense of remaining work without adding another card or competing
with the Active Set card.

## Decision

Replace the low-value title area with a minimal pinned Session progress strip.
The strip is lightweight chrome, not a card.

The approved shape is:

```text
W1 D1 ›    [literal set rail]    8 left
```

## Visual Rules

- The strip sits directly on the dark phone background.
- It is pinned at the top of the Session screen.
- It stays visually quieter than the Active Set card.
- It uses the mint/emerald palette from the active set visual direction.
- It does not use a gray panel, grouped container, or floating card treatment.
- It does not repeat progress as both `4 of 12` and `8 left`; the rail shows
  position, and the text shows remaining work.

## Rail Semantics

- Render one segment per Set in the displayed Session.
- Show every Set for now; do not aggregate, window, or bucket long Sessions.
- Logged Sets render mint.
- Skipped Sets count as progressed but render muted gray.
- The current or next pending Set renders as an active outlined mint segment.
- Future pending Sets render dim.
- The rail is display-only.

## Text Semantics

- `W1 D1 ›` is the compact Session location label.
- `8 left` is the remaining Set count.
- Avoid `Block` in the strip; Block context belongs in the overview route, not
  the live logging chrome.
- Avoid `4 of 12` in the strip because it duplicates the rail's job.

## Interaction

- Only `W1 D1 ›` is tappable.
- Tapping `W1 D1 ›` opens Block Overview when that route exists.
- The rail itself is not tappable, so progress display cannot be mistaken for a
  logging control.

## Relationship to Existing Design

The Active Set card remains the visual focus of the screen. The progress strip
only answers "how much work remains in this Session?" and provides the compact
route back to Session selection.

This supersedes the older Session header guidance in
`2026-05-26-active-set-visual-direction.md` where it conflicts with the approved
mini-strip layout.

## Verification

Before implementation is considered complete, verify:

- The strip is pinned and remains visible while logging.
- The strip has no gray background panel or card-like container.
- The text reads as `W1 D1 ›` and `{remaining} left`.
- The rail has one segment per Set.
- Logged, skipped, active, and future Sets are visually distinct.
- Skipped Sets reduce the remaining count.
- Only `W1 D1 ›` exposes navigation affordance.
