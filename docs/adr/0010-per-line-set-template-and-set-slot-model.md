# ADR 0010: Per-Line Set Templates and a Shared Set-Slot Model

**Status:** Accepted
**Date:** 2026-06-07

## Context

The app was built against one coach's Sheet template (Kevin Nguyen): each
Exercise is a single anchor row whose `Sets` cell holds the *total* number of
Sets, and the athlete's Set Logs live either compactly in the anchor's Notes
cell (comma-separated) or on log-only continuation rows below it. The parser and
the write planner both derived the per-Set rows from that single `Sets` cell.

A second athlete's coach (J. Alarcon) uses a different but equally common
template: **one prescription line per row**. An Exercise spans an anchor row plus
one or more blank-name continuation rows, and *each* row carries its own
`Sets`/`Reps`/`Load` and its own comma-separated Set Logs in its Notes cell. For
example `Comp BP` is authored as a `Sets=1` line followed by a `Sets=2` line — 3
Sets across two rows. Under the old reader these continuation rows were mistaken
for log rows, so every such Exercise displayed a single Set, and the write
planner could not address the missing Sets (it walked past the Exercise span).

Two facts made this tractable rather than a rewrite:

1. The two templates are distinguishable from the data alone. Kevin's
   continuation rows hold logs in the Notes column with an **empty** `Sets`
   cell; J's continuation rows have a **numeric** `Sets` cell.
2. A line's "comma-separated Set Logs in one Notes cell" is exactly the existing
   *compact header* mechanism — just applied per prescription row instead of
   only the anchor row.

## Decision

Introduce the **Prescription Line** as a first-class layout concept and a single
Set-Slot model that both the reader (`SheetParser`) and the write planner
(`SheetWritePlanner`) consume, so display and write targeting cannot diverge.

- **Line detection.** An Exercise occupies the rows `[anchor, nextAnchor)`. Line
  0 is always the anchor row. A continuation row becomes an additional Line **iff
  its `Sets` cell is a non-empty number**; otherwise it remains a log/blank row.
  This keeps single-line (Kevin) Exercises on the existing code path untouched.
- **Set count.** Multi-line Exercises have `sum(max(Sets, 1))` over their Lines;
  each Line distributes its comma-separated Reps/Load positionally (repeating the
  last token), matching the existing single-row split behaviour applied per Line.
- **Set addressing.** Each Set resolves to its Line's row, the Notes column, and
  the Set's index within that row's comma-separated Set-Log list. Reads pull the
  Set's State/Log from that address; writes aggregate into the same cell at the
  same position. This reuses the compact-header read/write logic per Line.
- **Last Set RPE** continues to target the Exercise anchor row.
- **Variable day count.** The `Day N` header pattern, previously capped at
  `Day 1–4`, now matches any `Day N`. Every downstream day count is already
  derived from the number of detected headers (ADR-0003), so 2–6 day Weeks parse
  and render without further structural change.

## Consequences

- One athlete's app can serve either coach template, and 2–6 day programs are
  supported. Kevin's 4-day single-anchor experience is unchanged — guarded by
  the empty-`Sets` continuation-row rule and the full existing test suite.
- Read and write share the Prescription Line model, so what the app shows and
  where it logs stay consistent by construction. The shared Set-Slot model is
  named the **Set-Log Slot** (see `CONTEXT.md`).
- **Honoured ambiguity:** where J's coach data is internally inconsistent (e.g. a
  single-row `Sets=1` line that lists two RPE targets), the `Sets` cell is taken
  as authoritative and surplus comma tokens are dropped, rather than guessing a
  larger count. This is the one place a human may later choose to reinterpret.
- The numeric cap on day count is removed entirely; 2–6 is the supported and
  tested range, but any `Day N` parses.

See PRD and slices: issues #297–#301.
