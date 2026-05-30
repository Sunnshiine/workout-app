# Sheet Layout Interpreter Spec

## Goal

Create a shared Sheet layout interpretation module at `WorkoutTracker/Parsing/SheetLayoutInterpreter.swift`.
The module concentrates Week, Day, Exercise anchor, Set row, role-column, header Notes, and write-target
layout rules that are currently split between parsing and write planning.

The change is behavior-preserving. It should make Sheet-shape edge cases testable once, then let
`SheetParser` and `SheetWritePlanner` consume the same interpreted layout without weakening dynamic
cell targeting or local-first write safety.

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
header Notes classification, continuation-row Set Log parsing, and Legacy Log completion behavior.
`SheetWritePlanningIndex` separately rebuilds a write-side view of weeks, days, anchors, role columns,
compact header Set 1, continuation Set rows, Last Set RPE targets, and header Notes conflicts.

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
  Consequence: The layout module scans live `SheetGrid` contents for Day headers, role headers, and Exercise anchors. It must not persist or cache raw A1 addresses across syncs or app launches.

- Decision: Preserve Legacy Log semantics.
  Source: [ADR 0005](../adr/0005-legacy-logs.md).
  Consequence: Header Notes classification must distinguish Coach Note, Legacy Log, compact Set Log, compact skip, and empty header Notes.

- Decision: Preserve batched pending-write safety.
  Source: [ADR 0006](../adr/0006-batched-pending-sheet-writes.md).
  Consequence: `SheetWritePlanner` may reuse a freshly interpreted snapshot during one flush batch, but pending writes remain semantic and raw cell addresses remain transient planning results.

## Scope

### In

- A shared layout module for interpreting `SheetGrid` row and column structure.
- Behavior-preserving migration of parser and writer layout rules into that module.
- Typed layout facts for Week sections, Day role columns, Exercise anchors, header Notes role, Set row addresses, and Last Set RPE addresses.
- Characterization tests for the shared module using existing Sheet edge cases.
- Focused fixture improvements only where they reduce repeated raw A1 setup for layout edge cases.

### Out

- New user-facing logging behavior.
- Live Google Sheet exploration or source-sheet reanalysis.
- A broad test-suite redesign.
- A protocol seam for layout interpretation. There is only one real adapter, so a protocol would be speculative.
- Changes to Google Sheets API batching behavior.
- Changes to `PendingWrite` persistence shape.
- Automatic migration or rewriting of Legacy Logs.
- Moving parse warning or sync conflict message ownership into the layout module.

## Current Architecture

`SheetParser` currently builds parsed domain data directly from `SheetGrid`:

- `locateWeekSections(in:)` finds rows with `Day 1` through `Day 4` headers.
- `resolveDayColumns(in:section:dayIndex:)` scans each Day span for role headers such as `Sets`,
  `Reps`, `%1RM`, `Load`, `Last set RPE`, and `Notes`.
- `parseDay(in:section:dayIndex:endRow:)` discovers Exercise anchor rows by non-empty cells in the
  Day name column, then derives each Exercise's `nextAnchor`.
- Header Notes classification happens inside parser flow: empty, structured Set Log, skip marker,
  Legacy Log, or Coach Note.
- Set Log parsing reads continuation rows relative to the anchor row and `nextAnchor`.

`SheetWritePlanner` currently builds a separate write planning index:

- `SheetWritePlanningIndex` calls `locateWeekSections` and `resolveDayColumns`, then independently
  scans Exercise anchors.
- `target(for:in:)` resolves the Notes or Last Set RPE target row and column.
- Compact header Set 1 and protected header Notes behavior is implemented again on the write side.
- `plan(_:target:in:)` verifies the expected current value and produces a transient `SheetCellUpdate`.

`SyncCoordinator` depends on `SheetWritePlanner` for pending write flushes. It may reuse one planning
snapshot per Block tab and apply successful writes to that in-memory snapshot before planning later
queued writes.

## Target Architecture

`SheetLayoutInterpreter` becomes the single owner of Sheet layout interpretation. It reads a
`SheetGrid` and returns immutable layout values that parser and writer code can consume.

`SheetParser` remains responsible for producing `ParsedBlock`, `ParsedWeek`, `ParsedSession`,
`ParsedExercise`, and `ParsedSet`. It uses interpreted layout values instead of rediscovering Weeks,
Days, Exercise anchors, header Notes roles, and Set row boundaries itself.

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

Concrete value type that interprets a grid.

```swift
struct SheetLayoutInterpreter: Sendable {
    func layout(for grid: SheetGrid) -> SheetLayout
}
```

The interpreter must be deterministic and side-effect free. It must not perform network I/O, read live
Google Sheets, or store raw cell addresses outside the returned in-memory layout.

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
behavior-preserving change. Either way, role columns are still discovered by header text inside the Day
span.

### [ADDED] `ExerciseLayout`

Interpreted Exercise row block.

```swift
struct ExerciseLayout: Sendable {
    let name: String
    let anchorRow: Int
    let nextAnchorRow: Int
    let headerNotesRole: HeaderNotesRole

    func notesAddress(forSetIndex index: Int) throws -> SheetCellAddress
    func lastSetRPEAddress() throws -> SheetCellAddress
}
```

`notesAddress(forSetIndex:)` returns the row and column for a Set-level Notes write or read. It must
preserve the current compact-header behavior:

- Empty header Notes can represent compact Set 1.
- Header Notes containing a structured Set Log can represent compact Set 1.
- Header Notes containing `skip` can represent compact Set 1.
- Header Notes classified as Coach Note or Legacy Log are protected; Set Logs target continuation rows
  when safe, or produce a layout error when no safe row exists before the next Exercise anchor.

`lastSetRPEAddress()` returns the Exercise anchor row and the dynamically resolved `Last set RPE`
column.

### [ADDED] `HeaderNotesRole`

Typed classification of the Exercise header Notes cell.

```swift
enum HeaderNotesRole: Sendable, Equatable {
    case empty
    case coachNote(String)
    case legacyLog(String)
    case compactSetLog(SetLog)
    case compactSkip
}
```

The role must preserve current semantics:

- Instruction-shaped non-empty header Notes are Coach Notes.
- Legacy result-shaped header Notes are Legacy Logs.
- A single structured Set Log or `skip` in header Notes is Set 1 state in compact layout, not a Legacy Log.
- Structured continuation-row Set Logs take precedence over Legacy Log completion behavior in parser output.

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
    case setRowNotFound(exerciseName: String, setIndex: Int)
    case protectedHeaderNotesWithoutSafeSetRow(exerciseName: String, setIndex: Int)
}
```

The layout module must not provide user-facing recovery prose. `SheetWritePlanner` maps these errors to
the existing `SheetWriterError` behavior.

### [CHANGED] `SheetParser`

`SheetParser` consumes `SheetLayout` to iterate Week, Day, and Exercise row blocks. Its public parsing
contract remains unchanged:

```swift
struct SheetParser {
    func parse(grid: SheetGrid, tabName: String) -> ParsedBlock
}
```

Parser warning ownership remains unchanged.

### [CHANGED] `SheetWritePlanner`

`SheetWritePlanner` uses `SheetLayout` inside its snapshot instead of a writer-local duplicated index.
Its caller-facing methods remain unchanged:

```swift
struct SheetWritePlanner: Sendable {
    func snapshot(for grid: SheetGrid) -> SheetWritePlanningSnapshot
    func plan(_ request: SheetWriteRequest, in grid: SheetGrid) throws -> SheetCellUpdate
    func plan(_ request: SheetWriteRequest, in snapshot: SheetWritePlanningSnapshot) throws -> SheetCellUpdate
    func target(for request: SheetWriteRequest, in snapshot: SheetWritePlanningSnapshot) throws -> SheetWriteTarget
}
```

Expected-current-value verification remains in `SheetWritePlanner`, not in `SheetLayoutInterpreter`.

### [REMOVED] Duplicated Writer-Local Layout Index

`SheetWritePlanningIndex`, `SheetWriteWeekIndex`, `SheetWriteDayIndex`, and `SheetWriteExerciseAnchor`
should be deleted once `SheetWritePlanner` can plan from `SheetLayout`.

During migration, temporary compatibility wrappers are acceptable only if they reduce review risk and
are removed before the spec is complete.

## Migration Plan

### Phase 1: Characterize Shared Layout

- Change: Add `SheetLayoutInterpreter` and focused unit tests for interpreted Week/Day columns,
  Exercise anchors, header Notes roles, Set row addresses, Last Set RPE addresses, and protected header
  conflicts.
- Compatibility: No production callers are required in this phase.
- Acceptance criteria: New layout tests pass and reflect current parser/writer behavior for existing
  edge cases.

### Phase 2: Parser Consumes Layout

- Change: Rewire `SheetParser` and `parseDay` internals to use `SheetLayout` for Week, Day, Exercise,
  `nextAnchor`, and header Notes role facts.
- Compatibility: `SheetParser.parse(grid:tabName:)`, `ParsedBlock`, `ParsedExercise`, `ParsedSet`, and
  parser warning output remain unchanged.
- Acceptance criteria: Existing parser tests pass, especially Set Log, Legacy Log, Coach Note, compact
  header, cadence, load splitting, and no-week warning tests.

### Phase 3: Writer Consumes Layout

- Change: Rewire `SheetWritePlanner` snapshots and target planning to use `SheetLayout` for target
  addresses and layout failures.
- Compatibility: `SheetWritePlanner` and `SheetWriterError` caller-facing behavior remains unchanged.
  `SyncCoordinator` continues to call `SheetWritePlanner`.
- Acceptance criteria: Existing writer and pending-write batch tests pass, including shifted role
  columns, shifted Exercise anchors, compact header writes, protected header Notes, unexpected current
  values, overlapping targets, and batch failure behavior.

### Phase 4: Delete Duplicate Index and Consolidate Fixtures

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
- [ ] Dynamic role-column and Exercise-anchor targeting remains based on the live `SheetGrid`.
- [ ] Coach Notes, Legacy Logs, compact Set 1, continuation Set rows, and Last Set RPE targets preserve current behavior.
- [ ] Pending writes still persist semantic targets only; raw cell addresses remain transient.
- [ ] Existing parser, writer, and batch-write tests pass.
- [ ] New focused layout tests cover the edge cases currently duplicated across parser and writer tests.

## Testing Strategy

Use TDD for each migration phase.

Layout tests should cover:

- Week and Day discovery from `Day N` headers.
- Role-column discovery when `Notes` and `Last set RPE` columns shift.
- Exercise anchor and `nextAnchor` discovery when rows shift.
- Header Notes role classification for empty, Coach Note, Legacy Log, compact Set Log, and compact skip.
- Notes address resolution for continuation rows and compact header Set 1.
- Last Set RPE address resolution to the Exercise anchor row.
- Protected header Notes conflict when no safe continuation row exists before the next Exercise.

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
