# RPE-Adjacent Set Log Targeting Spec

## Goal

Change Set Log read and write targeting so the athlete log column is resolved from the `Last set RPE`
column, not from the `Notes` role column. For each Day group, the Set Log column is the column
immediately to the right of `Last set RPE`.

This keeps Day 1 safe when the sheet has a blank column between `Last set RPE` and `Notes`, while
preserving Days 2, 3, and 4 where the column immediately right of `Last set RPE` may also be the
visible `Notes` column. Coach notes and Legacy Logs are still read from the `Notes` role column.

## Background

The app treats the coach-managed Sheet as the source of truth and uses local-first pending writes for
gym reliability. Relevant constraints are documented in:

- [CONTEXT.md](../../CONTEXT.md)
- [Testing strategy](../TESTING.md)
- [ADR 0001: Google Sheet as backend with local-first sync](../adr/0001-sheet-as-backend-local-first.md)
- [ADR 0003: Fully dynamic cell targeting](../adr/0003-dynamic-cell-targeting.md)
- [ADR 0005: Legacy logs are completion evidence](../adr/0005-legacy-logs.md)
- [ADR 0006: Batched pending Sheet writes preserve local-first safety](../adr/0006-batched-pending-sheet-writes.md)
- [Sheet Layout Interpreter Spec](2026-05-30-sheet-layout-interpreter.md)
- [Local Workbook Sheets Client Spec](2026-05-30-local-workbook-sheets-client.md)

Current code has a shared `SheetLayoutInterpreter`, but `SheetParser` and `SheetWritePlanner` still
treat the `Notes` role column as the Set Log column. That works only when the athlete-visible log
column and the coach `Notes` column are the same physical column.

The reported sheet shape differs by Day group:

- Day 1 has an empty column between `Last set RPE` and `Notes`.
- Days 2, 3, and 4 go directly from `Last set RPE` to `Notes`.

Under the current contract, a Day 1 Set Log can be written to the coach `Notes` column even though the
athlete-visible log column is the blank column immediately right of `Last set RPE`. This can leave the
app showing a Set as logged while the spreadsheet does not show the log where the athlete expects to
inspect it.

## Decisions

- Decision: Set Logs target the column immediately right of `Last set RPE`.
  Source: User-reported Day 1 versus Day 2/3/4 sheet layout and redesign direction.
  Consequence: `PendingWriteColumn.notes` remains a persisted compatibility name, but its planning
  target becomes the athlete Set Log column, not necessarily the `Notes` header column.

- Decision: The `Notes` role column remains the source for Coach Notes and Legacy Logs.
  Source: Current domain model and user observation that the coach writes notes only in the `Notes`
  column.
  Consequence: Parser logic must separate coach-note/legacy-log extraction from Set Log extraction
  when `Notes` and the RPE-adjacent Set Log column differ.

- Decision: Preserve fully dynamic targeting.
  Source: [ADR 0003](../adr/0003-dynamic-cell-targeting.md).
  Consequence: The Set Log column is derived from the live `Last set RPE` column for each Day group
  at parse/write time. Raw cell addresses are still never persisted.

- Decision: Preserve Coach Note and Legacy Log protection.
  Source: [ADR 0001](../adr/0001-sheet-as-backend-local-first.md) and
  [ADR 0005](../adr/0005-legacy-logs.md).
  Consequence: Non-empty protected header content is not overwritten. When the RPE-adjacent header log
  cell is protected, Set Logs move to safe continuation rows in that same RPE-adjacent column.

- Decision: Preserve batched pending-write safety and final-RPE pairing.
  Source: [ADR 0006](../adr/0006-batched-pending-sheet-writes.md).
  Consequence: Final `Last set RPE` writes must still fail or conflict with the paired final Set Log
  when the Set Log cannot be planned or written safely.

## Scope

### In

- Layout interpretation for an athlete Set Log column derived from `Last set RPE + 1`.
- Parser behavior that reads Set Logs from the athlete Set Log column and Coach Notes/Legacy Logs from
  the `Notes` column.
- Writer behavior that plans `PendingWriteColumn.notes` writes to the athlete Set Log column.
- Conflict behavior for occupied/protected header log cells and stale continuation values.
- Round-trip tests that prove the mutated Sheet can be fetched, parsed, and shown as logged in the
  same cells the writer used.
- Documentation updates that remove the assumption that Set Logs always live in the `Notes` column.

### Out

- Live Google Sheet writes in automated tests.
- Publishing workbook names, private sheet data, or client-specific grid details.
- Changing the persisted `PendingWrite` schema or enum raw values.
- Changing Google Sheets API batching semantics.
- Reworking optimistic local UI state beyond preserving existing conflict/retry behavior.
- Migrating old Sheet values from the `Notes` column into the RPE-adjacent Set Log column.
- Introducing a new backend or making the app the source of truth.

## Current Architecture

`SheetLayoutInterpreter` discovers Week sections, Day groups, role columns, and Exercise anchors from
the live `SheetGrid`. `DayColumns` currently exposes both `lastSetRPE` and `notes`, but does not expose
a separate athlete Set Log column.

`SheetParser` reads the Exercise header `Notes` cell to classify Coach Notes, Legacy Logs, compact
Set 1 logs, and compact skip markers. It also reads continuation-row Set Logs from the same `Notes`
column.

`SheetWritePlanner` resolves `.notes` pending writes through `DayColumns.notes`. It writes compact
Set 1 to the Exercise header `Notes` cell when allowed, or continuation rows in the `Notes` column when
the header is protected. `.lastSetRPE` writes target the Exercise anchor row and the dynamically
resolved `Last set RPE` column.

`SyncCoordinator` flushes semantic pending writes in order, reuses one current grid snapshot per Block
tab, applies planned updates to that snapshot, and deletes pending writes only after successful batch
updates. Recent dirty-tree work extends dependent conflict handling so a failed Set Log can block later
writes for the same Exercise.

## Target Architecture

`SheetLayoutInterpreter` owns two distinct Day-level columns:

- Coach Notes column: resolved from the `Notes` role header.
- Athlete Set Log column: resolved as the column immediately right of the `Last set RPE` role header.

These columns may be the same physical column. When they are the same, current Coach Note protection and
compact-header semantics continue to apply to the shared header cell. When they differ, the parser reads
Coach Notes and Legacy Logs from the `Notes` header cell while reading Set Logs from the RPE-adjacent
header and continuation cells.

`SheetParser` consumes this split layout. Parsed `coachNote` and `legacyLog` come only from the Coach
Notes column. Parsed Set state comes from the athlete Set Log column. If both a Legacy Log in the
`Notes` column and structured Set Logs in the athlete Set Log column exist, structured Set Logs continue
to take precedence for Set-level state.

`SheetWritePlanner` treats `PendingWriteColumn.notes` as the semantic Set Log target. It resolves that
semantic target to the athlete Set Log column, not necessarily to `DayColumns.notes`. Last Set RPE
writes continue to target the `Last set RPE` role column.

`SyncCoordinator` does not gain direct layout ownership. It continues to depend on `SheetWritePlanner`
for planning, conflict detection, in-memory snapshot application, and batch grouping.

## Contracts

### [ADDED] `DayColumns.setLog`

`DayColumns` exposes an athlete Set Log column derived from the Day group's `Last set RPE` column.

```swift
struct DayColumns: Sendable {
    let lastSetRPE: Int?
    let notes: Int?
    let setLog: Int?
}
```

Contract:

- `setLog == lastSetRPE + 1` when `Last set RPE` exists and the adjacent column remains inside the Day
  span.
- `setLog == notes` is valid for Days where `Notes` directly follows `Last set RPE`.
- `setLog != notes` is valid for Days where a blank athlete log column sits between `Last set RPE` and
  `Notes`.
- Missing or out-of-span `setLog` fails safe for Set Log writes instead of falling back to the old
  `Notes` target.

### [CHANGED] `PendingWriteColumn.notes`

The persisted enum case stays unchanged, but its semantic meaning becomes "Set Log column" rather than
"physical `Notes` role column".

```swift
enum PendingWriteColumn: String, Codable, Sendable {
    case notes
    case lastSetRPE
}
```

The raw value remains `notes` for compatibility with existing pending writes. No migration is required.

### [CHANGED] Header Cell Classification

Header classification separates coach-note content from athlete-log content.

```swift
struct ExerciseHeaderCells: Sendable, Equatable {
    let coachNotes: SheetLayoutHeaderNotes
    let setLogHeader: SheetLayoutHeaderNotes
}
```

Rules:

- Coach Notes and Legacy Logs are classified from the `Notes` column.
- Compact Set 1, compact skip, and compact aggregate Set Logs are classified from the Set Log column.
- If both roles point to the same cell, existing classification semantics apply to that one cell.
- If roles point to different cells, a Coach Note in `Notes` does not block writing Set 1 to an empty
  RPE-adjacent Set Log header cell.
- A protected value in the RPE-adjacent Set Log header cell blocks header writes and moves Set Logs to
  continuation rows in that same column.

### [CHANGED] `SheetParser`

Parser output types stay unchanged, but source cells change.

```swift
struct ParsedExercise {
    var coachNote: String?
    var legacyLog: String?
    var sets: [ParsedSet]
}
```

Contract:

- `coachNote` is read from the `Notes` role column.
- `legacyLog` is read from the `Notes` role column.
- `sets[index].setLog`, `sets[index].unstructuredSetLog`, and `sets[index].state` are read from the
  RPE-adjacent Set Log column.
- Structured Set Logs in the Set Log column take precedence over Legacy Log completion evidence.
- Missing Set Log column leaves Sets pending unless Legacy Log rules complete them.

### [CHANGED] `SheetWritePlanner`

Set Log planning resolves through `DayColumns.setLog`.

```swift
func target(for request: SheetWriteRequest, in snapshot: SheetWritePlanningSnapshot) throws -> SheetWriteTarget
```

Contract:

- `.lastSetRPE` targets the Exercise anchor row and `DayColumns.lastSetRPE`.
- `.notes` targets `DayColumns.setLog`.
- Empty or expected app-written header Set Log cells can be used for compact Set 1 behavior.
- Protected Set Log header cells move Set Logs to continuation rows in `DayColumns.setLog`.
- Expected-current-value verification still happens on the final target cell.
- Final Last Set RPE writes remain dependent on the paired final Set Log write.

### [REMOVED] Notes Column as Set Log Target Assumption

The architecture no longer assumes the `Notes` header column is the physical Set Log column. Any docs,
fixtures, tests, or comments that state Set Logs always live in `Notes` must be updated or narrowed to
the layouts where `setLog == notes`.

## Migration Plan

### Phase 1: Characterize Split Day Layouts

- Change: Add focused layout, parser, writer, and local-workbook round-trip tests for a Week where Day
  1 has `Last set RPE`, a blank RPE-adjacent Set Log column, then `Notes`, while another Day has
  `Last set RPE` directly followed by `Notes`.
- Compatibility: Production code can still fail these tests before implementation.
- Acceptance criteria: Tests explicitly demonstrate the current bug and define the expected new cells
  for Set Logs, Coach Notes, Legacy Logs, and Last Set RPE.

### Phase 2: Interpret Set Log Column

- Change: Extend `SheetLayoutInterpreter`/`DayColumns` with the RPE-adjacent Set Log column and header
  role facts needed by parser and writer callers.
- Compatibility: Existing parser/writer behavior can remain temporarily unchanged until both callers
  consume the new layout fact.
- Acceptance criteria: Layout tests cover `setLog == notes`, `setLog != notes`, missing
  `Last set RPE`, and out-of-span adjacent column failure.

### Phase 3: Parser and Writer Consume Split Columns

- Change: Rewire `SheetParser` to read Coach Notes/Legacy Logs from `Notes` and Set Logs from `setLog`.
  Rewire `SheetWritePlanner` so `.notes` writes target `setLog`.
- Compatibility: Persisted pending writes and public parser output shapes stay unchanged.
- Acceptance criteria: Parser and writer agree on target/readback cells for Day 1 split layout and
  Days 2-4 adjacent layout.

### Phase 4: Preserve Batch Safety and Update Documentation

- Change: Keep dependent Set Log/Last Set RPE conflicts green, add round-trip coverage through
  `LocalWorkbookSheetsClient`, and update domain/ADR wording that still says Set Logs always live in
  the `Notes` column.
- Compatibility: No live Google writes are required for automated verification.
- Acceptance criteria: A flushed Set Log is visible in the mutated workbook cell, parsing that workbook
  marks the same Set logged, and failed Set Log writes still prevent paired final-RPE success.

## Deletion Criteria

- No production writer code resolves Set Log targets through `DayColumns.notes`.
- No parser code reads Set Logs from `DayColumns.notes` unless `DayColumns.setLog == DayColumns.notes`.
- Tests no longer encode a universal "Notes is the Set Log column" assumption.
- Documentation that describes Set Log storage has been updated to mention the RPE-adjacent Set Log
  column and the separate Coach Notes role.

## Acceptance Criteria

- [ ] Day 1 split layout writes Set Logs to the column immediately right of `Last set RPE`, not to the
      `Notes` column.
- [ ] Days 2, 3, and 4 adjacent layouts continue to write Set Logs to the visible column immediately
      right of `Last set RPE`, even when that column is also `Notes`.
- [ ] Coach Notes and Legacy Logs continue to be read from the `Notes` role column.
- [ ] A Coach Note in `Notes` does not block writing to a distinct empty RPE-adjacent Set Log column.
- [ ] A protected value in the RPE-adjacent Set Log header cell moves Set Logs to continuation rows in
      that same column.
- [ ] Parser and writer round-trip through `LocalWorkbookSheetsClient`: after flush, fetching and
      parsing the workbook shows the logged Set from the same cell the writer updated.
- [ ] Final Last Set RPE still writes to the `Last set RPE` column and still depends on the paired final
      Set Log write.
- [ ] Existing compact aggregate, Coach Note, Legacy Log, shifted-column, and batch-write regressions
      remain covered or are intentionally replaced with equivalent RPE-adjacent tests.

## Testing Strategy

Use TDD because this is a high-risk Sheet write path.

Minimum focused tests:

- `SheetLayoutInterpreterTests`: derive `setLog` from `Last set RPE + 1` for split and adjacent Day
  layouts.
- `SheetParserLogTests`: read Set Logs from `setLog` while reading Coach Notes and Legacy Logs from
  `Notes`.
- `SheetWriterTests`: plan `.notes` writes to `setLog`, including empty compact headers, protected
  header fallback, shifted role columns, and missing-column safe failure.
- `SyncCoordinatorLocalWorkbookRoundTripTests`: flush pending Set Log plus final Last Set RPE, fetch the
  workbook, parse it again, and assert final domain state and physical cells.
- `SyncCoordinatorBatchWriteTests`: keep stale Set Log conflicts blocking later Exercise writes and
  final Last Set RPE writes.

Verification commands for implementation:

- `swift test --filter SheetLayoutInterpreterTests`
- `swift test --filter SheetParserLogTests`
- `swift test --filter SheetWriterTests`
- `swift test --filter SyncCoordinatorLocalWorkbookRoundTripTests`
- `swift test --filter SyncCoordinatorBatchWriteTests`
- Full `swift test`
- `swiftlint lint --quiet`

## Open Questions

- None for the spec. The design assumes the athlete Set Log column is always the live column immediately
  right of `Last set RPE`; unsupported shapes must fail safe rather than silently falling back to the
  old `Notes` target.
