# Set-Log Slot Resolver Spec

## Goal

Resolve a Set's **Set-Log Slot** — its row, its position within that row's comma-separated
Set-Log list, and which addressing rule applies — **once**, in a deep module on the Exercise
anchor, so the reader (`SheetParser`) and the write planner (`SheetWriter`) cannot target the
same Set differently. This is the unbuilt half of [ADR-0010](../adr/0010-per-line-set-template-and-set-slot-model.md):
the ADR coined the shared Set-Slot model but left targeting re-derived independently on each side.

The change replaces three duplicated "is this header a compact aggregate of Set Logs?" predicates
and two parallel row-resolution paths with a single `resolveSetLog(...) -> SetLogSlot` interface.
It also fixes one latent divergence the duplication hides: the reader's plain per-Set path reads by
**raw** row offset while the writer walks **visible** rows, so they address different cells when a
row in the Exercise span is hidden.

## Background

The Sheet is the single source of truth; the app reads and writes Set Logs into it
([ADR-0001](../adr/0001-sheet-as-backend-local-first.md)) with fully dynamic cell targeting
([ADR-0003](../adr/0003-dynamic-cell-targeting.md)) and batched, verify-before-write pending writes
([ADR-0006](../adr/0006-batched-pending-sheet-writes.md)). [ADR-0010](../adr/0010-per-line-set-template-and-set-slot-model.md)
introduced the **Prescription Line** and a shared Set-Slot model so display and write targeting
"cannot diverge"; the [SheetLayoutInterpreter spec](2026-05-30-sheet-layout-interpreter.md)
concentrated layout facts (Week/Day/anchor/role-column/Visible Writable Row) into one module.

The remaining friction is Set-Log **addressing**. Today the layout module exposes the seam as a set
of low-leverage helpers (`setLogRow`, `visibleSetLogRow`, `firstVisibleWritableRow`,
`continuationSetRow`) and each caller re-assembles the targeting decision from them:

- `SheetParser.parsedSingleLineExercise` (`WorkoutTracker/Parsing/SheetParser.swift:234`) computes
  `compactHeaderSetOne`, `usesVisibleWritableRow`, `headerSetLogValues`, then branches across them in
  `parsedSets` (`SheetParser.swift:122`).
- `SheetWriter.resolveNotesTarget` (`WorkoutTracker/Sheets/SheetWriter.swift:267`) recomputes the same
  classification and branches again to pick a row.
- `DeveloperToolsDiagnostics` (`WorkoutTracker/Stores/DeveloperToolsDiagnostics.swift:243`) re-derives the
  aggregate classification a third time for its write-targeting audit.

The "is this header a compact aggregate of Set Logs?" test is written **three times**, byte-for-byte:
`SheetParser.headerSetLogValues` (`SheetParser.swift:153`), `SheetWriter.isCompactAggregateHeader`
(`SheetWriter.swift:438`), and `DeveloperToolsDiagnostics.isCompactAggregateHeaderForAudit`
(`DeveloperToolsDiagnostics.swift:243`) — the last even clones its own `isSetLogListValueForAudit`.

Applying the **deletion test** to those helpers: deleting any one predicate copy does not concentrate
complexity, it just re-spreads the same rule across the survivors. They are **shallow** — the interface
is as complex as the implementation, and the real bugs live in how the three copies are kept in lockstep,
which has no **locality**. A single deep `resolveSetLog` is where that complexity earns its keep:
one small interface (a Set index against a layout) behind which all the addressing rules and their
precedence live.

Domain terms used below are defined in [CONTEXT.md](../../CONTEXT.md): **Set-Log Slot**,
**Prescription Line**, **Visible Writable Row**, **Coach Note**, **Compact Header**, **Set Log**,
**Set State**.

## Decisions

- **Decision:** Add a `SetLogSlot` value type and a `resolveSetLog(setIndex:columns:in:) -> SetLogSlot`
  interface on `SheetLayoutExerciseAnchor` — the seam both reader and writer already consume.
  **Source:** 2026-06-14 `/improve-codebase-architecture` review, candidate C1; design captured in
  [CONTEXT.md](../../CONTEXT.md) (Set-Log Slot term) and the ADR-0010 pointer.
  **Consequence:** Targeting is resolved once; reader maps the slot to a `ParsedSet`, writer maps it to
  `(row, col)` plus a list splice. The domain term already exists in `CONTEXT.md`, so no glossary change is needed.

- **Decision:** The slot is a **distinct-intent enum**, not a tagged `(row, position, rule)` tuple — one case
  per addressing rule, with a single `blocked(reason)` case for "no Visible Writable Row exists."
  **Source:** Grilling loop — "Distinct intent cases."
  **Consequence:** The reader maps `.blocked` to a Pending Set; the writer maps `.blocked` to a typed throw.
  The compiler enforces that every caller handles every rule, which is the **leverage** the deep module buys.

- **Decision:** Canonicalize the plain per-Set path on **visible-row** semantics for both sides.
  **Source:** Grilling loop — "Canonicalize on visible."
  **Consequence:** The reader's plain path stops using the raw `setLogRow` offset and walks visible rows like
  the writer already does. This is a **correct behavior change**: when a row inside the Exercise span is
  hidden, the reader had been reading the wrong cell. No existing test pins the old raw-offset read
  (confirmed: `setLogRow`'s only production caller is `SheetParser.swift:134`).

- **Decision:** Extract the compact-aggregate classification into one predicate owned by the layout module;
  `resolveSetLog` consumes it for its `.aggregate` case, and the diagnostics audit consumes the same predicate
  directly rather than routing the audit through full targeting resolution.
  **Source:** This spec (KISS / YAGNI — the audit needs the classification, not a write target).
  **Consequence:** All three duplicated predicates collapse to one source of truth without coupling
  developer-tools diagnostics to write-targeting.

- **Decision (precedence invariant):** A Compact Header that holds an aggregate of Set Logs is classified
  `.aggregate` **before** the protected/Coach-Note test.
  **Source:** Code-verified divergence risk. A multi-value aggregate header satisfies `hasProtectedValue`
  (`SheetLayoutInterpreter.swift:71`); only the OR-ordering in each copy
  (`SheetParser.swift:245`, `SheetWriter.swift:276`) currently stops it from being misread as a Coach Note
  and clobbered. The resolver owns this ordering once.

## Scope

### In

- A `SetLogSlot` type and `resolveSetLog(...)` interface on `SheetLayoutExerciseAnchor`.
- Routing `SheetParser` (single-line and multi-line read paths) and `SheetWriter` (`resolveNotesTarget` and
  the Notes-splice helpers) through the resolver.
- Routing `DeveloperToolsDiagnostics`' aggregate classification through the shared predicate.
- Deleting the three duplicated predicates and the orphaned anchor helpers.
- The hidden-row plain-path read fix (a consequence of canonicalizing on visible rows).

### Out

- Any change to the Prescription Line model, Line detection, or Set-count math from ADR-0010 — the resolver
  consumes `prescriptionLines`, it does not redefine them.
- Last Set RPE targeting — it continues to target the Exercise anchor row (ADR-0010), untouched.
- Any change to verify-before-write, batched-flush ordering, or conflict handling (ADR-0006).
- The Google Sheets transport, auth, or sync coordination.
- New user-facing behavior beyond the hidden-row read correction.

## Current Architecture

`SheetLayoutExerciseAnchor` (`WorkoutTracker/Parsing/SheetLayoutInterpreter.swift:133`) exposes the seam as
independent helpers:

- `setLogRow(for:compactHeaderSetOne:)` (line 182) — **raw** row = `anchor.row + offset`.
- `visibleSetLogRow(for:compactHeaderSetOne:in:)` (line 190) — walks **visible** rows in the span.
- `firstVisibleWritableRow(in:)` (line 205) — first visible row past the anchor (Coach-Note case).
- `continuationSetRow(for:)` (line 178) — thin wrapper over raw `setLogRow`; **no production caller**
  (only `Tests/Unit/SheetLayoutInterpreterTests.swift:86`).
- `prescriptionLines(in:setsColumn:)` (line 154) + `PrescriptionLine` (line 110) — the ADR-0010 per-Line model.

Both sides re-assemble targeting from those helpers and re-classify the header:

```text
                       ┌─ SheetParser.headerSetLogValues ─────────────┐
"is this header a      ├─ SheetWriter.isCompactAggregateHeader ───────┤  three byte-identical copies,
 compact aggregate?"   └─ DeveloperToolsDiagnostics.isCompactAggregate…┘  kept in lockstep by hand

reader plain path  → setLogRow (RAW offset)      ┐  diverge when a row in
writer plain path  → visibleSetLogRow (VISIBLE)  ┘  the span is hidden
```

The reader's branch ladder is `parsedSets` (`SheetParser.swift:122`): aggregate values → header set-one →
empty → Visible Writable Row → **raw** `setLogRow`. The writer's is `resolveNotesTarget`
(`SheetWriter.swift:267`): compact/aggregate → header row; protected → `firstVisibleWritableRow`; else
**visible** `setLogRow`. The two ladders encode the same precedence in two places.

## Target Architecture

One deep module owns Set-Log addressing. `resolveSetLog` is the interface; the rules and their precedence are
the implementation; callers receive a `SetLogSlot` and map it to their side's concern.

```text
                         ┌───────────────────────────────────────────┐
   Set index + layout →  │  SheetLayoutExerciseAnchor.resolveSetLog   │  → SetLogSlot
                         │   • precedence: aggregate before protected │
                         │   • visibility: visible-row walk           │
                         │   • one compact-aggregate classifier       │
                         └───────────────────────────────────────────┘
                              │                         │
              reader: slot → ParsedSet     writer: slot → (row, col) + list splice
              .blocked → Pending           .blocked → typed throw
                              │                         │
              DeveloperToolsDiagnostics ── shares the compact-aggregate classifier (not full resolution)
```

**Locality:** the precedence rule, the visible-row rule, and the aggregate classifier live in one place;
a Sheet-shape bug is now fixed once. **Leverage:** callers ask one question (where is this Set's log?) and
get an exhaustive, compiler-checked answer. **The interface is the test surface** — the addressing edge cases
become unit tests against `resolveSetLog`, and one anti-divergence test asserts reader-slot == writer-slot per
Set index. Two real adapters (reader, writer) consume the seam, so it is a real seam, not a hypothetical one.

## Contracts

### `SetLogSlot` — resolved Set-Log address [ADDED]

```swift
/// The resolved address for a single Set's Set Log: which row, the position within that
/// row's comma-separated Set-Log list, and which addressing rule applied. Resolved once
/// so the reader and the write planner cannot target a Set differently.
enum SetLogSlot: Sendable, Equatable {
    /// Compact Header holding an aggregate of Set Logs in the anchor's Notes cell.
    case aggregate(row: Int, position: Int)
    /// A Prescription Line's own Notes cell (ADR-0010 per-line template).
    case perLineList(row: Int, position: Int)
    /// Next Visible Writable Row past a Coach Note in the same Session.
    case visibleWritableRow(row: Int, position: Int)
    /// A plain per-Set row (one Set Log per row), resolved by the visible-row walk.
    case setRow(row: Int)
    /// No writable row exists for this Set (e.g. Coach Note with no Visible Writable Row).
    case blocked(reason: SetLogSlotBlockedReason)
}
```

### `resolveSetLog` — the interface [ADDED]

```swift
extension SheetLayoutExerciseAnchor {
    /// Resolves the Set-Log Slot for `setIndex` against this Exercise's layout. Precedence:
    /// per-Line (multi-line) → compact aggregate → Compact Header set-one → Coach-Note
    /// Visible Writable Row → plain visible per-Set row → blocked. Uses visible-row semantics
    /// throughout, so reads and writes address the same cell even when rows are hidden.
    func resolveSetLog(setIndex: Int, columns: DayColumns, in snapshot: SheetSnapshot) -> SetLogSlot
}
```

Consumed by:

- `SheetParser` — slot → `ParsedSet` (read the cell at `(row, position)`; `.blocked` → Pending). [CHANGED]
- `SheetWriter` — slot → `(row, col)` + comma-list splice at `position`; `.blocked` → typed throw. [CHANGED]

### Removed interfaces [REMOVED]

- `SheetParser.headerSetLogValues(from:setCount:)` — folded into the shared classifier + resolver.
- `SheetWriter.isCompactAggregateHeader(_:setCount:)` — folded into the shared classifier.
- `DeveloperToolsDiagnostics.isCompactAggregateHeaderForAudit(_:setCount:)` and its private
  `isSetLogListValueForAudit` — replaced by the shared classifier.
- `SheetLayoutExerciseAnchor.setLogRow(for:compactHeaderSetOne:)` (raw offset) — superseded by the resolver.
- `SheetLayoutExerciseAnchor.continuationSetRow(for:)` — already production-orphaned.

### Behavior change [CHANGED]

- Reader plain per-Set path: **raw** row offset → **visible** row walk. When a row in the Exercise span is
  hidden, the reader now reads the same cell the writer writes. Correct by ADR-0010's "cannot diverge" intent.

## Migration Plan

Each phase is independently reviewable, ships green, and reduces risk before the next.

### Phase 1: Land the deep module

- **Change:** Add `SetLogSlot` + `resolveSetLog` on `SheetLayoutExerciseAnchor`, and the single shared
  compact-aggregate classifier it uses. Consumed by no caller yet.
- **Compatibility:** Pure addition; no behavior change anywhere.
- **Acceptance criteria:** Per-case unit tests for all five slot cases (aggregate, per-line, Visible Writable
  Row, plain set-row, blocked); a precedence test proving a compact aggregate header resolves `.aggregate`,
  not `.visibleWritableRow`; existing `swift test` suite stays green.

### Phase 2: Route the reader

- **Change:** `SheetParser` resolves each Set through `resolveSetLog` instead of its own branch ladder; drop
  the `headerSetLogValues` / `usesVisibleWritableRow` plumbing from `ParsedSetContext`.
- **Compatibility:** Behavior-preserving **except** the intended hidden-row fix on the plain path.
- **Acceptance criteria:** `Tests/Unit/SheetParserLogTests.swift` stays green; a new hidden-row plain-path test
  asserts the reader skips the hidden row; the reader no longer references raw `setLogRow`.

### Phase 3: Route the writer

- **Change:** `SheetWriter.resolveNotesTarget` and the Notes-splice helpers (`multiLineNotesValue`,
  `compactAggregateHeaderValue`, `resolveCompactNotesTarget`) resolve through `resolveSetLog`.
- **Compatibility:** Behavior-preserving; the writer is already visible-aware.
- **Acceptance criteria:** `Tests/Unit/SheetSnapshotWriterTests.swift` and the SheetWriter suite stay green;
  a new anti-divergence test asserts the reader's slot row/position equals the writer's for every Set index
  across the compact-aggregate, per-line, Coach-Note, and hidden-row fixtures.

### Phase 4: Collapse the duplication

- **Change:** Delete `headerSetLogValues`, `isCompactAggregateHeader`, `isCompactAggregateHeaderForAudit`
  (+ `isSetLogListValueForAudit`); route `DeveloperToolsDiagnostics` through the shared classifier; remove
  orphaned `continuationSetRow` and raw `setLogRow`, updating `SheetLayoutInterpreterTests` accordingly.
- **Compatibility:** No behavior change; diagnostics output unchanged.
- **Acceptance criteria:** A grep for the aggregate predicate finds exactly one definition; the orphaned anchor
  helpers are gone; full `swift test` green.

## Deletion Criteria

The duplicated predicates and the orphaned anchor helpers may be removed once:

- every Set-Log targeting call site (`SheetParser`, `SheetWriter`, `DeveloperToolsDiagnostics`) resolves through
  `resolveSetLog` or the shared classifier, and
- the anti-divergence test (Phase 3) passes, proving reader and writer agree per Set index.

`continuationSetRow` and raw `setLogRow` are removable as soon as their only references are the resolver's
internals and `SheetLayoutInterpreterTests` (which Phase 4 updates).

## Acceptance Criteria

- [ ] `SetLogSlot` + `resolveSetLog(setIndex:columns:in:)` exist on `SheetLayoutExerciseAnchor`.
- [ ] Both `SheetParser` and `SheetWriter` resolve Set-Log targeting through `resolveSetLog`.
- [ ] An anti-divergence test asserts reader-slot == writer-slot for every Set index across the compact-aggregate,
      per-line, Coach-Note, and hidden-row fixtures.
- [ ] A new test proves the reader's plain path skips a hidden row in the Exercise span.
- [ ] A precedence test proves a compact aggregate header resolves `.aggregate`, never the Coach-Note path.
- [ ] The three duplicated predicates and the orphaned `continuationSetRow` / raw `setLogRow` are deleted.
- [ ] `swift test` is green.

## Testing Strategy

Unit tests against `resolveSetLog` are the primary surface — one per slot case plus the precedence and
visibility invariants — because the interface is now the test surface. The existing `SheetParserLogTests` and
SheetWriter/`SheetSnapshotWriterTests` suites guard against read/write regressions through the reroute. The
anti-divergence test is the keystone: it encodes ADR-0010's "cannot diverge" promise as an executable check.
No UI or simulator tests are required — this is pure layout/targeting logic exercised through `swift test`.

## Open Questions

- None blocking. The slot's `position` is unused by the `.setRow` case (one Set Log per row); if a future
  coach template puts several logs on a plain per-Set row, `.setRow` would gain a `position` — out of scope here.
