# Sheet Layout Interpreter Spec

## Goal

Create a shared Sheet layout interpretation module at `WorkoutTracker/Parsing/SheetLayoutInterpreter.swift`.
The module concentrates Week, Day, Session boundary, Exercise anchor, row visibility, Visible Writable Row,
role-column, header Notes, and write-target layout rules that are currently split between parsing and write
planning.

The change updates the Set Log row model and centralizes it. It should make Sheet-shape edge cases testable
once, then let `SheetParser` and `SheetWritePlanner` consume the same interpreted layout without weakening
dynamic cell targeting or local-first write safety.

## Background

The app treats the coach-managed Sheet as the source of truth. Sheet structure is flexible: a coach can
insert rows, move Day groups, shift role columns, and place different kinds of values in Exercise header
Notes cells. Existing rules are documented in:

- [CONTEXT.md](../../CONTEXT.md)
- [ADR 0003: Fully dynamic cell targeting](../adr/0003-dynamic-cell-targeting.md)
- [ADR 0005: Legacy logs are completion evidence](../adr/0005-legacy-logs.md)
- [ADR 0006: Batched pending Sheet writes preserve local-first safety](../adr/0006-batched-pending-sheet-writes.md)
- [Testing strategy](../TESTING.md)

Today, `SheetParser` owns `WeekSection`, `DayColumns`, role-column scanning, anchor row discovery,
header Notes classification, Set Log parsing, and Legacy Log completion behavior.
`SheetWritePlanningIndex` separately rebuilds a write-side view of weeks, days, anchors, role columns,
Set Log target rows, Last Set RPE targets, and header Notes conflicts.

This duplication is risky because the highest-risk bugs are Sheet-shape bugs: a parser change and a writer
change can accidentally diverge on the same Sheet row.

## Decisions

- Decision: Add a concrete `SheetLayoutInterpreter` module in `WorkoutTracker/Parsing/SheetLayoutInterpreter.swift`.
  Source: Architecture planning discussion on Sheet layout interpretation.
  Consequence: The module name is internal architecture language, not a new domain term, so `CONTEXT.md` does not need a glossary update.

- Decision: The module owns low-level Sheet layout facts and typed layout errors, not user-facing parse warnings or sync conflict copy.
  Source: Planning decision to preserve current caller-facing behavior.
  Consequence: `SheetParser` keeps parse warning ownership, and `SheetWritePlanner` or `SyncCoordinator` keeps existing `SheetWriterError` and conflict-message behavior.

- Decision: Preserve fully dynamic targeting.
  Source: [ADR 0003](../adr/0003-dynamic-cell-targeting.md).
  Consequence: The layout module scans live Sheet values for Day headers, role headers, and Exercise anchors,
  and uses live row visibility metadata to exclude hidden rows. It must not persist or cache raw A1 addresses
  across syncs or app launches.

- Decision: Set Logs use one Visible Writable Row per Exercise.
  Source: Spreadsheet-write targeting design update after hidden-row workbook evidence.
  Consequence: Parser and writer must select the same Visible Writable Row inside the same Session. If the
  Exercise header Notes cell is available, the Exercise row is the target. If the header Notes cell contains
  a Coach Note, the search moves downward from the Exercise row to the next Visible Writable Row and stops
  before the next Session boundary. Hidden rows are ignored for reads and writes.

- Decision: Preserve Legacy Log semantics.
  Source: [ADR 0005](../adr/0005-legacy-logs.md).
  Consequence: Header Notes classification must distinguish Coach Note, Legacy Log, current Set Log list,
  current skip list, and empty header Notes.

- Decision: Preserve batched pending-write safety.
  Source: [ADR 0006](../adr/0006-batched-pending-sheet-writes.md).
  Consequence: `SheetWritePlanner` may reuse a freshly interpreted snapshot during one flush batch, but pending writes remain semantic and raw cell addresses remain transient planning results.

## Scope

### In

- A shared layout module for interpreting Sheet value and row visibility structure.
- Migration of parser and writer layout rules into that module while adopting the Visible Writable Row model.
- Typed layout facts for Week sections, Day role columns, Session boundaries, Exercise anchors, row visibility,
  header Notes role, Visible Writable Row addresses, and Last Set RPE addresses.
- Sheet snapshot values plus row visibility metadata, including rows hidden by user action or by filters.
- Write-target audit details that explain the row scan used for Set Log target selection.
- Characterization tests for the shared module using existing Sheet edge cases.
- Focused fixture improvements only where they reduce repeated raw A1 setup for layout edge cases.

### Out

- New athlete-facing logging behavior.
- Live Google Sheet exploration or source-sheet reanalysis.
- A broad test-suite redesign.
- A protocol seam for layout interpretation. There is only one real adapter, so a protocol would be speculative.
- Changes to Google Sheets API batching behavior.
- Changes to `PendingWrite` persistence shape.
- Automatic migration or rewriting of Legacy Logs.
- Moving parse warning or sync conflict message ownership into the layout module.

## Current Architecture

`SheetParser` currently builds parsed domain data directly from Sheet values:

- `locateWeekSections(in:)` finds rows with `Day 1` through `Day 4` headers.
- `resolveDayColumns(in:section:dayIndex:)` scans each Day span for role headers such as `Sets`,
  `Reps`, `%1RM`, `Load`, `Last set RPE`, and `Notes`.
- `parseDay(in:section:dayIndex:endRow:)` discovers Exercise anchor rows by non-empty cells in the
  Day name column, then derives each Exercise's next anchor and Session boundary.
- Header Notes classification happens inside parser flow: empty, structured Set Log, skip marker,
  Legacy Log, or Coach Note.
- Set Log parsing reads the Exercise's selected Visible Writable Row and ignores hidden rows.

`SheetWritePlanner` currently builds a separate write planning index:

- `SheetWritePlanningIndex` calls `locateWeekSections` and `resolveDayColumns`, then independently
  scans Exercise anchors.
- `target(for:in:)` resolves the Notes or Last Set RPE target row and column.
- Visible Writable Row selection and protected header Notes behavior is implemented again on the write side.
- `plan(_:target:in:)` verifies the expected current value and produces a transient `SheetCellUpdate`.

`SyncCoordinator` depends on `SheetWritePlanner` for pending write flushes. It may reuse one planning
snapshot per Block tab and apply successful writes to that in-memory snapshot before planning later
queued writes.

## Target Architecture

`SheetLayoutInterpreter` becomes the single owner of Sheet layout interpretation. It reads a Sheet snapshot
containing values and row visibility metadata, then returns immutable layout values that parser and writer
code can consume.

`SheetParser` remains responsible for producing `ParsedBlock`, `ParsedWeek`, `ParsedSession`,
`ParsedExercise`, and `ParsedSet`. It uses interpreted layout values instead of rediscovering Weeks,
Days, Exercise anchors, header Notes roles, row visibility, and Visible Writable Rows itself.

`SheetWritePlanner` remains responsible for semantic write planning, expected-current-value
verification, transient `SheetCellUpdate` creation, and mapping layout errors into the current
`SheetWriterError` surface. It uses interpreted layout values instead of `SheetWritePlanningIndex`
owning its own row-role model.

`SyncCoordinator` continues to depend on `SheetWritePlanner`, not directly on layout interpretation.
This preserves the current write flush ownership model.

The deletion boundary is `SheetWritePlanningIndex`: once parser and writer both use
`SheetLayoutInterpreter`, the duplicated writer-local week/day/anchor index can be removed or reduced
to a thin compatibility wrapper during migration.

## Contracts

### [ADDED] `SheetLayoutInterpreter`

Concrete value type that interprets a Sheet snapshot.

```swift
struct SheetLayoutInterpreter: Sendable {
    func layout(for snapshot: SheetSnapshot) -> SheetLayout
}
```

The interpreter must be deterministic and side-effect free. It must not perform network I/O, read live
Google Sheets, or store raw cell addresses outside the returned in-memory layout.

### [ADDED] `SheetSnapshot`

Values and row visibility facts for one Block tab.

```swift
struct SheetSnapshot: Sendable {
    let grid: SheetGrid
    let rowVisibility: [Int: SheetRowVisibility]
}

struct SheetRowVisibility: Sendable, Equatable {
    let hiddenByUser: Bool
    let hiddenByFilter: Bool

    var isVisible: Bool { !hiddenByUser && !hiddenByFilter }
}
```

Production snapshots must be built from Google Sheets data that includes both values and row metadata.
Rows hidden by user action or by filters are not Visible Writable Rows.

### [ADDED] `SheetLayout`

Immutable interpreted layout for one Block tab grid.

```swift
struct SheetLayout: Sendable {
    let weeks: [WeekLayout]

    func week(_ number: Int) throws -> WeekLayout
    func day(week: Int, day: Int) throws -> DayLayout
}
```

Week and Day lookup numbers are 1-based to match existing `PendingWrite.week` and `PendingWrite.day`.

### [ADDED] `WeekLayout`

Interpreted Week section.

```swift
struct WeekLayout: Sendable {
    let number: Int
    let headerRow: Int
    let roleHeaderRow: Int
    let dateRow: Int
    let endRow: Int
    let days: [DayLayout]
}
```

`endRow` is the next Week header row or the grid end, matching existing parser and writer behavior.

### [ADDED] `DayLayout`

Interpreted Day group within a Week.

```swift
struct DayLayout: Sendable {
    let number: Int
    let columns: DayColumns
    let exercises: [ExerciseLayout]

    func column(_ role: SheetColumnRole) throws -> Int
    func exercise(named name: String) throws -> ExerciseLayout
}
```

The existing `DayColumns` value may move into this file or remain shared if that produces the smallest
clear change. Either way, role columns are still discovered by header text inside the Day span.

### [ADDED] `ExerciseLayout`

Interpreted Exercise row block.

```swift
struct ExerciseLayout: Sendable {
    let name: String
    let anchorRow: Int
    let nextAnchorRow: Int
    let sessionEndRow: Int
    let headerNotesRole: HeaderNotesRole

    func setLogAddress() throws -> SheetCellAddress
    func lastSetRPEAddress() throws -> SheetCellAddress
}
```

`setLogAddress()` returns the row and column for the Exercise-level comma-separated Set Log list. It must
follow the Visible Writable Row behavior:

- Empty header Notes means the Exercise row is the Visible Writable Row.
- Header Notes containing the expected current comma-separated Set Log list means the Exercise row remains
  the Visible Writable Row for edits or deletes.
- Header Notes containing a Coach Note is protected; scan downward from the Exercise row to the next Visible
  Writable Row in the same Session.
- Hidden rows are skipped.
- The scan stops before `sessionEndRow`; it must not cross into the next Week or Session.
- If no Visible Writable Row exists inside the Session, produce a layout error.

`lastSetRPEAddress()` returns the Exercise anchor row and the dynamically resolved `Last set RPE`
column.

### [ADDED] `HeaderNotesRole`

Typed classification of the Exercise header Notes cell.

```swift
enum HeaderNotesRole: Sendable, Equatable {
    case empty
    case coachNote(String)
    case legacyLog(String)
    case setLogList(String)
    case skipList(String)
}
```

The role must preserve current semantics:

- Instruction-shaped non-empty header Notes are Coach Notes.
- Legacy result-shaped header Notes are Legacy Logs.
- A structured comma-separated Set Log list or skip list in the selected Visible Writable Row is current
  Set-level state, not a Legacy Log.
- Current Set Logs in the selected Visible Writable Row take precedence over Legacy Log completion behavior
  in parser output.

### [ADDED] `SheetColumnRole`

Column role lookup used by writer and parser callers.

```swift
enum SheetColumnRole: Sendable, Equatable {
    case sets
    case reps
    case percentOneRM
    case load
    case lastSetRPE
    case notes
}
```

### [ADDED] `SheetCellAddress`

Transient row and column result for interpreted targets.

```swift
struct SheetCellAddress: Sendable, Equatable {
    let row: Int
    let col: Int
}
```

This type must not be persisted. `SheetCellUpdate` can continue to add tab name and value on the write
planning side.

### [ADDED] `SheetLayoutError`

Typed low-level lookup and layout failures.

```swift
enum SheetLayoutError: Error, Equatable {
    case weekNotFound(Int)
    case dayNotFound(Int)
    case columnNotFound(SheetColumnRole)
    case exerciseNotFound(String)
    case visibleWritableRowNotFound(exerciseName: String)
    case unexpectedSetLogTargetValue(exerciseName: String, expected: String, actual: String)
}
```

The layout module must not provide user-facing recovery prose. `SheetWritePlanner` maps these errors to
the existing `SheetWriterError` behavior.

### [CHANGED] `SheetParser`

`SheetParser` consumes `SheetLayout` to iterate Week, Day, and Exercise row blocks. Its parsing contract
must accept row visibility metadata so it can ignore hidden Set Log rows:

```swift
struct SheetParser {
    func parse(snapshot: SheetSnapshot, tabName: String) -> ParsedBlock
}
```

Parser warning ownership remains unchanged. A temporary `parse(grid:tabName:)` compatibility wrapper is
acceptable only for tests that do not exercise hidden-row behavior.

### [CHANGED] `SheetWritePlanner`

`SheetWritePlanner` uses `SheetLayout` inside its snapshot instead of a writer-local duplicated index.
Its caller-facing methods keep the same planning responsibilities while accepting Sheet snapshots:

```swift
struct SheetWritePlanner: Sendable {
    func snapshot(for sheet: SheetSnapshot) -> SheetWritePlanningSnapshot
    func plan(_ request: SheetWriteRequest, in sheet: SheetSnapshot) throws -> SheetCellUpdate
    func plan(_ request: SheetWriteRequest, in snapshot: SheetWritePlanningSnapshot) throws -> SheetCellUpdate
    func target(for request: SheetWriteRequest, in snapshot: SheetWritePlanningSnapshot) throws -> SheetWriteTarget
}
```

Expected-current-value verification remains in `SheetWritePlanner`, not in `SheetLayoutInterpreter`.
Set-specific upserts and deletes edit the comma-separated Set Log list in the selected Visible Writable Row.

### [ADDED] Write Target Audit Diagnostics

The write path records a capped local diagnostic log for Developer Tools. It must include both successful
writes and conflicts, because successful pending writes are deleted after a batch succeeds.

Each audit entry should include:

- semantic target: Block, Week, Day, Exercise, Set, and column;
- chosen A1 target when one was selected;
- row scan details, including hidden rows skipped and why the selected row was writable;
- expected/current value check result;
- final status: planned, written, conflict, or retry.

Developer Tools must expose the rolling log separately from Pending Sheet Writes, with Copy Write Log and
Clear Write Log actions.

### [REMOVED] Duplicated Writer-Local Layout Index

`SheetWritePlanningIndex`, `SheetWriteWeekIndex`, `SheetWriteDayIndex`, and `SheetWriteExerciseAnchor`
should be deleted once `SheetWritePlanner` can plan from `SheetLayout`.

During migration, temporary compatibility wrappers are acceptable only if they reduce review risk and
are removed before the spec is complete.

## Migration Plan

### Phase 1: Characterize Shared Layout

- Change: Add `SheetLayoutInterpreter` and focused unit tests for interpreted Week/Day columns,
  Session boundaries, Exercise anchors, row visibility, header Notes roles, Visible Writable Row addresses,
  Last Set RPE addresses, and protected header conflicts.
- Compatibility: No production callers are required in this phase.
- Acceptance criteria: New layout tests pass and reflect current parser/writer behavior for existing
  edge cases.

### Phase 2: Parser Consumes Layout

- Change: Rewire `SheetParser` and `parseDay` internals to use `SheetLayout` for Week, Day, Exercise,
  `nextAnchor`, Session boundary, row visibility, Visible Writable Row, and header Notes role facts.
- Compatibility: `ParsedBlock`, `ParsedExercise`, `ParsedSet`, and parser warning output remain unchanged.
  A temporary `parse(grid:tabName:)` wrapper may remain only for tests that do not need row visibility.
- Acceptance criteria: Existing parser tests pass or are updated to the Visible Writable Row model, especially
  Set Log, Legacy Log, Coach Note, cadence, load splitting, and no-week warning tests.

### Phase 3: Writer Consumes Layout

- Change: Rewire `SheetWritePlanner` snapshots and target planning to use `SheetLayout` for target
  addresses and layout failures.
- Compatibility: `SheetWritePlanner` and `SheetWriterError` caller-facing API shape remains unchanged.
  `SyncCoordinator` continues to call `SheetWritePlanner`.
- Acceptance criteria: Writer and pending-write batch tests cover shifted role columns, shifted Exercise
  anchors, header-row Set Log writes, Coach Note downward scans to visible rows, hidden-row rejection,
  same-Session scan boundaries, unexpected current values, overlapping targets, and batch failure behavior.

### Phase 4: Write Target Audit Log

- Change: Persist a capped local write-target audit log and expose it in Developer Tools with Copy Write Log
  and Clear Write Log actions.
- Compatibility: Pending writes remain the source of retry/conflict state; the audit log is diagnostic only.
- Acceptance criteria: Successful writes and conflicts both produce audit entries with compact row scan
  details.

### Phase 5: Delete Duplicate Index and Consolidate Fixtures

- Change: Remove writer-local duplicated layout index types and promote only the repeated Sheet layout
  edge cases into named `Tests/Support` fixtures.
- Compatibility: Tests should become clearer without changing behavior under test.
- Acceptance criteria: No remaining production code independently scans Week/Day/Exercise layout outside
  `SheetLayoutInterpreter`, except training max parsing and other explicitly out-of-scope parsing logic.

## Deletion Criteria

- `SheetWritePlanningIndex`, `SheetWriteWeekIndex`, `SheetWriteDayIndex`, and `SheetWriteExerciseAnchor`
  no longer exist or are proven to be temporary wrappers slated for removal in the same change set.
- Parser and writer no longer each maintain separate Exercise anchor and `nextAnchor` discovery logic.
- Header Notes role classification exists in one production location.
- Existing parser, writer, and sync tests continue to pass after duplicate code is removed.

## Acceptance Criteria

- [ ] `WorkoutTracker/Parsing/SheetLayoutInterpreter.swift` exists and owns shared Sheet layout interpretation.
- [ ] `SheetParser` and `SheetWritePlanner` consume the shared interpreted layout.
- [ ] Dynamic role-column, Exercise-anchor, and row-visibility targeting remains based on the live Sheet snapshot.
- [ ] Parser and writer share the same Visible Writable Row selection rule for Set Logs.
- [ ] Hidden rows are ignored for Set Log reads and writes.
- [ ] Coach Notes, Legacy Logs, visible Set Log lists, and Last Set RPE targets preserve the updated behavior.
- [ ] Developer Tools exposes a capped write-target audit log with copy and clear actions.
- [ ] Pending writes still persist semantic targets only; raw cell addresses remain transient.
- [ ] Existing parser, writer, and batch-write tests pass.
- [ ] New focused layout tests cover the edge cases currently duplicated across parser and writer tests.

## Testing Strategy

Use TDD for each migration phase.

Layout tests should cover:

- Week and Day discovery from `Day N` headers.
- Role-column discovery when `Notes` and `Last set RPE` columns shift.
- Exercise anchor and `nextAnchor` discovery when rows shift.
- Header Notes role classification for empty, Coach Note, Legacy Log, Set Log list, and skip list.
- Visible Writable Row resolution for header-row writes and Coach Note downward scans.
- Last Set RPE address resolution to the Exercise anchor row.
- Hidden row exclusion using row visibility metadata.
- Same-Session scan boundaries so a last Exercise never targets the next Week or Session.
- Protected header Notes conflict when no Visible Writable Row exists before the Session boundary.

Verification for implementation should include:

- `swift test --filter SheetParserTests`
- `swift test --filter SheetParserLogTests`
- `swift test --filter SheetWriterTests`
- `swift test --filter SyncCoordinatorBatchWriteTests`
- Full `swift test`

`swift build` and `swiftlint lint --quiet` are required before marking implementation complete if Swift
source files are edited.

## Open Questions

- None. The module path decision is `WorkoutTracker/Parsing/SheetLayoutInterpreter.swift`.
