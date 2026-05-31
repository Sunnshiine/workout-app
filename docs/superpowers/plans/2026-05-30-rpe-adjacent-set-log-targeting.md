# RPE-Adjacent Set Log Targeting Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make Set Log reads and writes use the column immediately right of `Last set RPE`, while Coach Notes and Legacy Logs continue to come from the `Notes` role column.

**Architecture:** Extend `SheetLayoutInterpreter` so each Day exposes both `notes` and `setLog` columns. Then update parser and writer call sites to read Coach Note/Legacy Log content from `notes` and Set Log state from `setLog`; `SyncCoordinator` remains behind `SheetWritePlanner` and does not gain layout ownership.

**Tech Stack:** Swift 6, Swift Testing, SwiftData in-memory containers, `LocalWorkbookSheetsClient`, `swift test`, SwiftLint.

---

## Assumptions

- `PendingWriteColumn.notes` keeps its raw value for persisted compatibility, but now means "Set Log target" in planner code.
- A Day without `Last set RPE` has no safe Set Log column; writer planning for `.notes` must fail with `.columnNotFound("Set Log")`.
- If `setLog == notes`, existing compact-header and Coach Note behavior remains valid for the shared physical cell.
- If `setLog != notes`, `Notes` is only the Coach Note/Legacy Log source; Set Log state is read and written from the RPE-adjacent `setLog` column.
- Before implementation, preserve the current dirty tree. Create an isolated worktree for execution if this branch cannot be committed cleanly.

## File Structure

- Modify `WorkoutTracker/Parsing/SheetLayoutInterpreter.swift`
  - Add `DayColumns.setLog`.
  - Derive it from `lastSetRPE + 1` inside the Day span.
- Modify `WorkoutTracker/Parsing/SheetParser.swift`
  - Keep Coach Note/Legacy Log classification on `columns.notes`.
  - Read compact header Set Logs and continuation-row Set Logs from `columns.setLog`.
- Modify `WorkoutTracker/Sheets/SheetWriter.swift`
  - Resolve `.notes` writes through `columns.setLog`.
  - Use the Set Log header cell, not the Coach Notes cell, for compact/protected Set Log planning.
- Modify `Tests/Unit/SheetLayoutInterpreterTests.swift`
  - Add split and adjacent Day layout coverage for `setLog`.
- Modify `Tests/Unit/SheetParserLogTests.swift`
  - Add split-column parser coverage.
- Modify `Tests/Unit/SheetWriterTests.swift`
  - Keep adjacent-column regressions green and add split-column writer coverage.
- Modify `Tests/Unit/SyncCoordinatorLocalWorkbookRoundTripTests.swift`
  - Add a read-after-write round-trip proving visible RPE-adjacent Set Log cells parse back into logged Sets.
- Modify `Tests/Support/SheetGridFixture.swift`
  - Add a focused split-column local workbook fixture.
- Modify `CONTEXT.md`, `AGENTS.md`, `CLAUDE.md`, `docs/adr/0001-sheet-as-backend-local-first.md`, and `docs/adr/0003-dynamic-cell-targeting.md`
  - Replace universal "Set Logs live in Notes" wording with the RPE-adjacent Set Log column rule.

---

### Task 1: Layout Exposes RPE-Adjacent Set Log Column

**Files:**
- Modify: `Tests/Unit/SheetLayoutInterpreterTests.swift`
- Modify: `WorkoutTracker/Parsing/SheetLayoutInterpreter.swift`

- [ ] **Step 1: Add failing layout tests**

Append these tests to `Tests/Unit/SheetLayoutInterpreterTests.swift`:

```swift
@Test func layoutInterpreterDerivesSetLogColumnFromLastSetRPE() throws {
    let grid = gridFromA1(
        [
            "C12": "Day 1", "S12": "Day 2",
            "D14": "Sets", "I14": "Last set RPE", "K14": "Notes",
            "T14": "Sets", "Y14": "Last set RPE", "Z14": "Notes"
        ],
        rows: 20,
        cols: 32
    )

    let layout = SheetLayoutInterpreter().interpret(grid)
    let day1 = try #require(layout.day(week: 1, day: 1))
    let day2 = try #require(layout.day(week: 1, day: 2))

    #expect(day1.columns.lastSetRPE == 8)
    #expect(day1.columns.setLog == 9)
    #expect(day1.columns.notes == 10)
    #expect(day2.columns.lastSetRPE == 24)
    #expect(day2.columns.setLog == 25)
    #expect(day2.columns.notes == 25)
}

@Test func layoutInterpreterDoesNotInventSetLogColumnWithoutSafeRPEAdjacentCell() throws {
    let missingRPEGrid = gridFromA1(
        [
            "C12": "Day 1", "S12": "Day 2",
            "D14": "Sets", "K14": "Notes"
        ],
        rows: 20,
        cols: 30
    )
    let missingRPEDay = try #require(SheetLayoutInterpreter().interpret(missingRPEGrid).day(week: 1, day: 1))
    #expect(missingRPEDay.columns.lastSetRPE == nil)
    #expect(missingRPEDay.columns.setLog == nil)
    #expect(missingRPEDay.columns.notes == 10)

    let outOfSpanGrid = gridFromA1(
        [
            "C12": "Day 1", "E12": "Day 2",
            "D14": "Last set RPE"
        ],
        rows: 20,
        cols: 10
    )
    let outOfSpanDay = try #require(SheetLayoutInterpreter().interpret(outOfSpanGrid).day(week: 1, day: 1))
    #expect(outOfSpanDay.columns.lastSetRPE == 3)
    #expect(outOfSpanDay.columns.setLog == nil)
}
```

- [ ] **Step 2: Run layout tests and verify failure**

Run:

```bash
swift test --filter SheetLayoutInterpreterTests
```

Expected: FAIL because `DayColumns` has no `setLog` member.

- [ ] **Step 3: Add `setLog` to `DayColumns`**

In `WorkoutTracker/Parsing/SheetLayoutInterpreter.swift`, replace `DayColumns` with:

```swift
struct DayColumns: Sendable {
    let name: Int
    let sets: Int?
    let reps: Int?
    let percentOneRM: Int?
    let load: Int?
    let lastSetRPE: Int?
    let setLog: Int?
    let notes: Int?
    let span: Range<Int>  // [dayStart, nextDayStart)
}
```

- [ ] **Step 4: Derive `setLog` in `resolveDayColumns`**

In `resolveDayColumns(in:section:dayIndex:)`, replace the `return DayColumns(...)` block with:

```swift
    let lastSetRPE = find("Last set RPE")
    let setLog = lastSetRPE.flatMap { column -> Int? in
        let adjacent = column + 1
        return span.contains(adjacent) ? adjacent : nil
    }

    return DayColumns(
        name: start,
        sets: find("Sets"),
        reps: find("Reps"),
        percentOneRM: find("%1RM"),
        load: find("Load"),
        lastSetRPE: lastSetRPE,
        setLog: setLog,
        notes: find("Notes"),
        span: span
    )
```

- [ ] **Step 5: Run layout tests and verify pass**

Run:

```bash
swift test --filter SheetLayoutInterpreterTests
```

Expected: PASS.

- [ ] **Step 6: Commit layout change**

Run:

```bash
git add Tests/Unit/SheetLayoutInterpreterTests.swift WorkoutTracker/Parsing/SheetLayoutInterpreter.swift
git commit -m "feat: derive set log column from last set rpe"
```

Expected: commit succeeds.

---

### Task 2: Parser Reads Logs From Set Log Column And Notes From Notes Column

**Files:**
- Modify: `Tests/Unit/SheetParserLogTests.swift`
- Modify: `WorkoutTracker/Parsing/SheetParser.swift`

- [ ] **Step 1: Add failing split-column parser tests**

Append these tests to `Tests/Unit/SheetParserLogTests.swift`:

```swift
@Test func parsesRPEAdjacentSetLogsWhileCoachNotesComeFromNotesColumn() throws {
    let grid = gridFromA1(
        [
            "C12": "Day 1", "S12": "Day 2",
            "D14": "Sets", "F14": "Reps", "H14": "Load", "I14": "Last set RPE", "K14": "Notes",
            "C15": "Squat", "D15": "2", "F15": "5", "H15": "RPE 8",
            "J15": "185x5@8", "K15": "Coach note",
            "J16": "195x5@9"
        ],
        rows: 24,
        cols: 30
    )
    let section = locateWeekSections(in: grid)[0]

    let exercises = parseDay(in: grid, section: section, dayIndex: 0, endRow: grid.count)

    #expect(exercises[0].coachNote == "Coach note")
    #expect(exercises[0].legacyLog == nil)
    #expect(exercises[0].sets[0].state == .logged)
    #expect(exercises[0].sets[0].setLog?.formatted == "185x5@8")
    #expect(exercises[0].sets[1].state == .logged)
    #expect(exercises[0].sets[1].setLog?.formatted == "195x5@9")
}

@Test func rpeAdjacentStructuredSetLogsTakePrecedenceOverNotesLegacyLog() throws {
    let grid = gridFromA1(
        [
            "C12": "Day 1", "S12": "Day 2",
            "D14": "Sets", "F14": "Reps", "H14": "Load", "I14": "Last set RPE", "K14": "Notes",
            "C15": "Standing Calve Raises", "D15": "2", "F15": "12", "H15": "RPE 9",
            "J15": "35x12@9", "K15": "25x12, 12",
            "J16": "40x12@9"
        ],
        rows: 22,
        cols: 30
    )
    let section = locateWeekSections(in: grid)[0]

    let exercises = parseDay(in: grid, section: section, dayIndex: 0, endRow: grid.count)

    #expect(exercises[0].coachNote == nil)
    #expect(exercises[0].legacyLog == "25x12, 12")
    #expect(exercises[0].sets.map { $0.setLog?.formatted } == ["35x12@9", "40x12@9"])
    #expect(exercises[0].sets.map(\.state) == [.logged, .logged])
}
```

- [ ] **Step 2: Run parser log tests and verify failure**

Run:

```bash
swift test --filter SheetParserLogTests
```

Expected: FAIL because the parser still reads Set Logs from `columns.notes`.

- [ ] **Step 3: Update `ParsedSetContext`**

In `WorkoutTracker/Parsing/SheetParser.swift`, replace `ParsedSetContext` with:

```swift
private struct ParsedSetContext {
    let setCount: Int
    let anchor: SheetLayoutExerciseAnchor
    let setLogColumn: Int?
    let grid: SheetGrid
    let headerSetLog: String
    let headerSetLogValues: [String]?
    let compactHeaderSetOne: Bool
    let reps: String
    let repsValues: [String]
    let load: String
    let loadValues: [String]
    let percentOneRM: String
}
```

- [ ] **Step 4: Read continuation logs from `setLogColumn`**

In `parsedSets(_:)`, replace the current `rawLog` decision block with:

```swift
        let rawLog: String
        if context.compactHeaderSetOne, let values = context.headerSetLogValues, i < values.count {
            rawLog = values[i]
        } else if context.compactHeaderSetOne, i == 0 {
            rawLog = context.headerSetLog
        } else {
            let logRow = context.anchor.setLogRow(
                for: i,
                compactHeaderSetOne: context.compactHeaderSetOne
            )
            rawLog = logRow.map { context.grid.cellOrEmpty($0, context.setLogColumn) } ?? ""
        }
```

- [ ] **Step 5: Split Coach Notes from Set Log header parsing**

In `parsedExercise(grid:day:anchor:)`, replace the header-note and `sets` construction block from `let headerNotes = ...` through the `completionSets(...)` call with:

```swift
    let coachNotes = anchor.headerNotes(in: grid, notesColumn: cols.notes)
    let setLogHeader = anchor.headerNotes(in: grid, notesColumn: cols.setLog)
    let setLogHeaderValue = setLogHeader.value
    let setCount = anchor.prescribedSetCount(in: grid, setsColumn: cols.sets)
    let headerSetLogValues = headerSetLogValues(from: setLogHeaderValue, setCount: setCount)
    let compactHeaderSetOne = headerSetLogValues != nil || anchor.usesCompactHeaderSetOne(headerNotes: setLogHeader)
    let legacyLog = coachNotes.isLegacyLog ? coachNotes.value : nil
    let sets = completionSets(
        parsedSets(
            ParsedSetContext(
                setCount: setCount,
                anchor: anchor,
                setLogColumn: cols.setLog,
                grid: grid,
                headerSetLog: setLogHeaderValue,
                headerSetLogValues: headerSetLogValues,
                compactHeaderSetOne: compactHeaderSetOne,
                reps: reps,
                repsValues: reps.components(separatedBy: ",").map { $0.trimmingCharacters(in: .whitespaces) },
                load: load,
                loadValues: splitLoadValues(load),
                percentOneRM: grid.cellOrEmpty(anchorRow, cols.percentOneRM)
            )
        ),
        legacyLog: legacyLog
    )
```

Then replace the returned `coachNote` expression with:

```swift
        coachNote: coachNotes.isCoachNote ? coachNotes.value : nil,
```

Keep `legacyLog: legacyLog` unchanged.

- [ ] **Step 6: Run parser log tests and verify pass**

Run:

```bash
swift test --filter SheetParserLogTests
```

Expected: PASS.

- [ ] **Step 7: Run parser regression tests**

Run:

```bash
swift test --filter SheetParserTests
```

Expected: PASS.

- [ ] **Step 8: Commit parser change**

Run:

```bash
git add Tests/Unit/SheetParserLogTests.swift WorkoutTracker/Parsing/SheetParser.swift
git commit -m "feat: parse set logs from rpe-adjacent column"
```

Expected: commit succeeds.

---

### Task 3: Writer Plans Set Log Writes To Set Log Column

**Files:**
- Modify: `Tests/Unit/SheetWriterTests.swift`
- Modify: `WorkoutTracker/Sheets/SheetWriter.swift`

- [ ] **Step 1: Keep the default writer fixture on an adjacent layout**

In `Tests/Unit/SheetWriterTests.swift`, replace the base header map in `writerFixture(_:)` with:

```swift
            [
                "C12": "Day 1", "S12": "Day 2",
                "D14": "Sets", "F14": "Reps", "H14": "Load", "J14": "Last set RPE", "K14": "Notes"
            ].merging(cells) { _, new in new },
```

This keeps existing `K` Notes expectations as adjacent-layout regressions because `setLog == notes == K`.

- [ ] **Step 2: Update the default Last Set RPE expectation**

In `writesLastSetRPEToAnchorRow`, replace:

```swift
    #expect(update.range == "'Block 27'!I15")
```

with:

```swift
    #expect(update.range == "'Block 27'!J15")
```

- [ ] **Step 3: Add failing split-column writer tests**

Append these tests to `Tests/Unit/SheetWriterTests.swift`:

```swift
@Test func writesSplitLayoutSetOneToRPEAdjacentHeaderWhenNotesHasCoachNote() throws {
    let grid = gridFromA1(
        [
            "C12": "Day 1", "S12": "Day 2",
            "D14": "Sets", "F14": "Reps", "H14": "Load", "I14": "Last set RPE", "K14": "Notes",
            "C15": "Squat", "D15": "1", "K15": "Coach note"
        ],
        rows: 30,
        cols: 30
    )

    let update = try SheetWritePlanner().plan(
        SheetWriteRequest(
            blockTab: "Block 27",
            week: 1,
            day: 1,
            exerciseName: "Squat",
            setIndex: 0,
            column: .notes,
            operation: .upsert,
            valueToWrite: "185x5@8",
            expectedCurrentValue: ""
        ),
        in: grid
    )

    #expect(update.range == "'Block 27'!J15")
    #expect(update.value == "185x5@8")
}

@Test func writesSplitLayoutSetLogBelowProtectedSetLogHeader() throws {
    let grid = gridFromA1(
        [
            "C12": "Day 1", "S12": "Day 2",
            "D14": "Sets", "F14": "Reps", "H14": "Load", "I14": "Last set RPE", "K14": "Notes",
            "C15": "Squat", "D15": "1", "J15": "coach edited", "K15": "Coach note",
            "C17": "Bench", "D17": "1"
        ],
        rows: 30,
        cols: 30
    )

    let update = try SheetWritePlanner().plan(
        SheetWriteRequest(
            blockTab: "Block 27",
            week: 1,
            day: 1,
            exerciseName: "Squat",
            setIndex: 0,
            column: .notes,
            operation: .upsert,
            valueToWrite: "185x5@8",
            expectedCurrentValue: ""
        ),
        in: grid
    )

    #expect(update.range == "'Block 27'!J16")
    #expect(update.value == "185x5@8")
}

@Test func refusesSetLogWriteWhenLastSetRPEColumnIsMissing() throws {
    let grid = gridFromA1(
        [
            "C12": "Day 1", "S12": "Day 2",
            "D14": "Sets", "F14": "Reps", "H14": "Load", "K14": "Notes",
            "C15": "Squat", "D15": "1", "K15": "Coach note"
        ],
        rows: 30,
        cols: 30
    )

    do {
        _ = try SheetWritePlanner().plan(
            SheetWriteRequest(
                blockTab: "Block 27",
                week: 1,
                day: 1,
                exerciseName: "Squat",
                setIndex: 0,
                column: .notes,
                operation: .upsert,
                valueToWrite: "185x5@8",
                expectedCurrentValue: ""
            ),
            in: grid
        )
        Issue.record("Expected missing Set Log column")
    } catch let error as SheetWriterError {
        #expect(error == .columnNotFound("Set Log"))
    } catch {
        Issue.record("Expected SheetWriterError, got \(error)")
    }
}
```

- [ ] **Step 4: Update shifted-column writer regression**

Replace `resolvesShiftedNotesAndRPEColumnsFromRoleHeaders` with this version:

```swift
@Test func resolvesShiftedRPEAdjacentSetLogAndRPEColumnsFromRoleHeaders() throws {
    let grid = gridFromA1(
        [
            "C12": "Day 1", "S12": "Day 2",
            "D14": "Sets", "E14": "Notes", "G14": "Last set RPE",
            "C15": "Squat", "D15": "2", "E15": "Coach note"
        ],
        rows: 30,
        cols: 30
    )
    let planner = SheetWritePlanner()

    let notesUpdate = try planner.plan(
        SheetWriteRequest(
            blockTab: "Block 27",
            week: 1,
            day: 1,
            exerciseName: "Squat",
            setIndex: 0,
            column: .notes,
            operation: .upsert,
            valueToWrite: "185x5@8",
            expectedCurrentValue: ""
        ),
        in: grid
    )
    let rpeUpdate = try planner.plan(
        SheetWriteRequest(
            blockTab: "Block 27",
            week: 1,
            day: 1,
            exerciseName: "Squat",
            setIndex: 1,
            column: .lastSetRPE,
            operation: .upsert,
            valueToWrite: "9",
            expectedCurrentValue: ""
        ),
        in: grid
    )

    #expect(notesUpdate.range == "'Block 27'!H15")
    #expect(rpeUpdate.range == "'Block 27'!G15")
}
```

- [ ] **Step 5: Run writer tests and verify failure**

Run:

```bash
swift test --filter SheetWriterTests
```

Expected: FAIL because `.notes` still resolves through `DayColumns.notes`.

- [ ] **Step 6: Resolve `.notes` to `setLog`**

In `WorkoutTracker/Sheets/SheetWriter.swift`, replace `resolveColumn(_ column:cols:)` with:

```swift
    private func resolveColumn(_ column: PendingWriteColumn, cols: DayColumns) throws -> Int {
        switch column {
        case .notes:
            guard let setLog = cols.setLog else { throw SheetWriterError.columnNotFound("Set Log") }
            return setLog
        case .lastSetRPE:
            guard let rpe = cols.lastSetRPE else { throw SheetWriterError.columnNotFound("Last set RPE") }
            return rpe
        }
    }
```

- [ ] **Step 7: Use Set Log header for planning**

In `resolveTarget(for:layout:grid:)`, replace:

```swift
        let headerNotes = anchor.headerNotes(in: grid, notesColumn: day.columns.notes)
        let setCount = anchor.prescribedSetCount(in: grid, setsColumn: day.columns.sets)
        let compactHeaderSetOne =
            anchor.usesCompactHeaderSetOne(headerNotes: headerNotes)
            || isCompactAggregateHeader(headerNotes.value, setCount: setCount)
```

with:

```swift
        let setLogHeader = anchor.headerNotes(in: grid, notesColumn: day.columns.setLog)
        let setCount = anchor.prescribedSetCount(in: grid, setsColumn: day.columns.sets)
        let compactHeaderSetOne =
            anchor.usesCompactHeaderSetOne(headerNotes: setLogHeader)
            || isCompactAggregateHeader(setLogHeader.value, setCount: setCount)
```

Then replace the missing-row protected check:

```swift
            if request.column == .notes, headerNotes.hasProtectedValue {
```

with:

```swift
            if request.column == .notes, setLogHeader.hasProtectedValue {
```

- [ ] **Step 8: Use Set Log header for compact aggregate writes**

In `compactAggregateHeaderValue(for:target:actual:in:)`, replace the guard condition:

```swift
            day.columns.notes == target.col,
```

with:

```swift
            day.columns.setLog == target.col,
```

Then replace:

```swift
        let headerNotes = anchor.headerNotes(in: snapshot.grid, notesColumn: day.columns.notes)
```

with:

```swift
        let headerNotes = anchor.headerNotes(in: snapshot.grid, notesColumn: day.columns.setLog)
```

- [ ] **Step 9: Run writer tests and verify pass**

Run:

```bash
swift test --filter SheetWriterTests
```

Expected: PASS.

- [ ] **Step 10: Run compact layout tests**

Run:

```bash
swift test --filter SheetCompactLayoutTests
```

Expected: PASS. These tests protect compact aggregate behavior after `.notes` becomes the semantic Set Log target.

- [ ] **Step 11: Commit writer change**

Run:

```bash
git add Tests/Unit/SheetWriterTests.swift WorkoutTracker/Sheets/SheetWriter.swift
git commit -m "feat: write set logs to rpe-adjacent column"
```

Expected: commit succeeds.

---

### Task 4: Sync Round Trip Proves Visible Set Log Cells Parse Back

**Files:**
- Modify: `Tests/Support/SheetGridFixture.swift`
- Modify: `Tests/Unit/SyncCoordinatorLocalWorkbookRoundTripTests.swift`
- Run: `Tests/Unit/SyncCoordinatorBatchWriteTests.swift`

- [ ] **Step 1: Add a focused split-column round-trip fixture**

Append this fixture to `Tests/Support/SheetGridFixture.swift`:

```swift
/// Day 1 split layout where Last Set RPE is followed by an athlete Set Log
/// column, then the Coach Notes column. The coach note must stay in Notes while
/// the Set Log and Last Set RPE write to the RPE-adjacent cells.
func rpeAdjacentCoachNoteRoundTripGrid() -> SheetGrid {
    gridFromA1(
        [
            "C12": "Day 1", "S12": "Day 2",
            "D14": "Sets", "F14": "Reps", "H14": "Load", "I14": "Last set RPE", "K14": "Notes",
            "C15": "Squat", "D15": "1", "F15": "5", "H15": "RPE 8", "K15": "Coach note",
            "C18": "Bench Press", "D18": "1"
        ],
        rows: 24,
        cols: 30
    )
}
```

- [ ] **Step 2: Add a failing local workbook round-trip test**

Append this test to `Tests/Unit/SyncCoordinatorLocalWorkbookRoundTripTests.swift`:

```swift
@MainActor
@Test func localWorkbookRoundTripFlushWritesRPEAdjacentSetLogAndParsesDomainState() async throws {
    let container = try makeLocalWorkbookRoundTripContainer()
    let context = container.mainContext
    let writes = [
        localWorkbookPendingWrite(
            createdAt: 1,
            exerciseName: "Squat",
            setIndex: 0,
            valueToWrite: "185x5@8"
        ),
        localWorkbookPendingWrite(
            createdAt: 2,
            exerciseName: "Squat",
            setIndex: 0,
            column: .lastSetRPE,
            valueToWrite: "8"
        )
    ]
    for write in writes {
        context.insert(write)
    }
    try context.save()

    let client = LocalWorkbookSheetsClient(
        tabs: ["Block 27": rpeAdjacentCoachNoteRoundTripGrid()]
    )
    let sync = SyncCoordinator(client: client, context: context)

    await sync.flushPending(spreadsheetId: "sid")

    let updated = try await client.fetchTab(spreadsheetId: "sid", tabName: "Block 27")
    let parsed = SheetParser().parse(grid: updated, tabName: "Block 27")
    let exercise = try #require(
        parsed.block.weeks.first?.days.first?.exercises.first {
            $0.name == "Squat"
        }
    )
    let set = try #require(exercise.sets.first)
    let batches = await client.recordedBatches

    #expect(updated.cell(row: 14, col: 9) == "185x5@8")
    #expect(updated.cell(row: 14, col: 10) == "Coach note")
    #expect(updated.cell(row: 14, col: 8) == "8")
    #expect(exercise.coachNote == "Coach note")
    #expect(set.state == .logged)
    #expect(set.setLog?.formatted == "185x5@8")
    #expect(parsed.warnings.isEmpty)
    #expect(try context.fetch(FetchDescriptor<PendingWrite>()).isEmpty)
    #expect(sync.state == .idle)
    #expect(batches.count == 1)
    #expect(batches[0].map(\.range) == ["'Block 27'!J15", "'Block 27'!I15"])
}
```

- [ ] **Step 3: Run local workbook round-trip tests**

Run:

```bash
swift test --filter SyncCoordinatorLocalWorkbookRoundTripTests
```

Expected: PASS if Tasks 1-3 are complete. If this fails, inspect whether the planner targets `K15` instead of `J15` or parser still reads from `K15`.

- [ ] **Step 4: Run batch-write conflict regressions**

Run:

```bash
swift test --filter SyncCoordinatorBatchWriteTests
```

Expected: PASS. This confirms Set Log conflicts still block dependent Exercise writes and paired final Last Set RPE writes.

- [ ] **Step 5: Commit sync round-trip coverage**

Run:

```bash
git add Tests/Support/SheetGridFixture.swift Tests/Unit/SyncCoordinatorLocalWorkbookRoundTripTests.swift
git commit -m "test: cover rpe-adjacent set log round trip"
```

Expected: commit succeeds.

---

### Task 5: Update Domain And ADR Wording

**Files:**
- Modify: `CONTEXT.md`
- Modify: `AGENTS.md`
- Modify: `CLAUDE.md`
- Modify: `docs/adr/0001-sheet-as-backend-local-first.md`
- Modify: `docs/adr/0003-dynamic-cell-targeting.md`

- [ ] **Step 1: Update `CONTEXT.md` logging terms**

In `CONTEXT.md`, replace the `Set Log`, `Last Set RPE`, and `Coach Note` paragraphs with:

```markdown
**Set Log**: The athlete's record for a single Set, in the format `{weight}x{reps}@{RPE}` (e.g. "185x7@6"). `{weight}` is either a number in lbs or the literal "BW" for bodyweight sets (e.g. "BWx12@7"); BW is pre-filled when the coach prescribes bodyweight but always overridable with a number for weighted variations. Written per-set into the athlete Set Log column, resolved per Day as the column immediately right of `Last set RPE`. In Days where that column is also `Notes`, compact Exercise layouts may write Set 1 to the Exercise header cell only when that cell is empty or already contains the expected app-written Set 1 value. In Days where `Notes` is a separate column, Coach Notes still live in `Notes` and athlete logs live in the RPE-adjacent Set Log column. Avoid: actual load, log entry.

**Last Set RPE**: The RPE the athlete reports for the final Set of an Exercise. Stored in the dynamically resolved `Last set RPE` column — the app extracts it from the last Set Log and writes it there automatically. Avoid: actual RPE.

**Coach Note**: Instruction-shaped text the coach places in the `Notes` role column on the Exercise header row — e.g. "Start w/ 10 sec hold, proceed to rep range" or "Superset w/...". Read-only to the athlete. Never overwritten by the app. When `Notes` and the athlete Set Log column are the same physical column, an empty header cell can be used for Set 1; any non-empty instruction-shaped value keeps the header reserved as a Coach Note. Avoid: set log, legacy log, athlete note.
```

- [ ] **Step 2: Update critical write workflow guidance in both agent docs**

In both `AGENTS.md` and `CLAUDE.md`, replace the three bullets under `## Critical Sheet Write Workflows` with:

```markdown
- Logging a Set Log must write the RPE-adjacent Set Log column, and logging the final Set must write Last Set RPE only with its paired Set Log write. These are the highest-risk user workflows because the Sheet is the source of truth.
- Preserve both supported Set Log layouts: compact multi-set logs may aggregate into the header Set Log cell when it is safe, while coach-note or AMRAP header content must be protected and Set Logs must go to continuation rows in the Set Log column.
- Before changing `WorkoutStore`, `SyncCoordinator`, `SheetWriter`, `SheetLayoutInterpreter`, or pending-write ordering, run `swift test --filter SyncCoordinatorBatchWriteTests` and keep the coach-note/RPE, RPE-adjacent, and compact aggregate regressions green.
```

After editing, verify the files remain byte-identical:

```bash
cmp -s AGENTS.md CLAUDE.md
```

Expected: exit code 0.

- [ ] **Step 3: Update ADR 0001 write-target wording**

In `docs/adr/0001-sheet-as-backend-local-first.md`, replace the sentence beginning `This keeps the coach's workflow untouched` through the end of the paragraph with:

```markdown
This keeps the coach's workflow untouched (coach edits Sheet; athlete sees changes on next sync) and avoids building a dedicated backend for a single-athlete app. Local-first protects against gym connectivity loss without requiring conflict-resolution infrastructure: the app only writes new Set Log data to verified-safe Set Log cells. The Set Log column is resolved per Day as the column immediately right of `Last set RPE`; the `Notes` role column remains the Coach Note and Legacy Log source. Continuation rows remain the common target when the Set Log header cell is protected; compact Exercise layouts may use an empty Set Log header cell for Set 1, but any non-empty unexpected value is protected from overwrite.
```

- [ ] **Step 4: Update ADR 0003 dynamic targeting wording**

In `docs/adr/0003-dynamic-cell-targeting.md`, replace the two bullets under `We derive every write target dynamically...` with:

```markdown
- **Column**: scan the day's column group for the header labelled `Last set RPE`. Last Set RPE writes use that column. Set Log writes use the column immediately to its right when that adjacent column remains inside the Day group. The header labelled `Notes` is still scanned separately as the Coach Note and Legacy Log source. Never hardcode a column letter.
- **Row**: scan the day's column group for the exercise name, then resolve the target Set row relative to that anchor. In compact layouts where the Exercise header row is also Set 1, an empty Set Log header cell is writable for Set 1, and Set 2 starts on the first continuation row or aggregates into the header according to the existing compact behavior. If the Set Log header cell is non-empty and does not match the expected app-written value, it is treated as protected content and Set Logs fall back to safe continuation rows or conflict. Coach Notes in a separate `Notes` column do not block writes to an empty RPE-adjacent Set Log cell.
```

- [ ] **Step 5: Search for stale universal Notes-column claims**

Run:

```bash
rg -n "Set Logs? (must |always |usually |go |live |target|writes?|written).*Notes|Notes column \\(J\\)|column J|verified-safe Notes cells|header Notes cell" CONTEXT.md AGENTS.md CLAUDE.md docs WorkoutTracker Tests -g '*.md' -g '*.swift'
```

Expected: remaining hits are either historic specs, tests for adjacent layouts, or wording that explicitly says `Notes` is the Coach Note/Legacy Log role. Update any current production docs or comments that still claim Set Logs universally write to `Notes`.

- [ ] **Step 6: Run docs diff check**

Run:

```bash
git diff --check
```

Expected: PASS.

- [ ] **Step 7: Commit docs update**

Run:

```bash
git add CONTEXT.md AGENTS.md CLAUDE.md docs/adr/0001-sheet-as-backend-local-first.md docs/adr/0003-dynamic-cell-targeting.md
git commit -m "docs: document rpe-adjacent set log targeting"
```

Expected: commit succeeds.

---

### Task 6: Final Verification

**Files:**
- Verify all modified Swift, tests, and docs.

- [ ] **Step 1: Run focused layout/parser/writer tests**

Run:

```bash
swift test --filter SheetLayoutInterpreterTests
swift test --filter SheetParserLogTests
swift test --filter SheetParserTests
swift test --filter SheetWriterTests
swift test --filter SheetCompactLayoutTests
```

Expected: every command exits 0.

- [ ] **Step 2: Run sync tests**

Run:

```bash
swift test --filter SyncCoordinatorLocalWorkbookRoundTripTests
swift test --filter SyncCoordinatorBatchWriteTests
```

Expected: every command exits 0.

- [ ] **Step 3: Run the full Swift package test suite**

Run:

```bash
swift test
```

Expected: PASS.

- [ ] **Step 4: Run SwiftLint**

Run:

```bash
swiftlint lint --quiet
```

Expected: PASS, allowing only pre-existing warnings if the branch already has them and no new warnings were introduced.

- [ ] **Step 5: Verify AGENTS and CLAUDE match**

Run:

```bash
cmp -s AGENTS.md CLAUDE.md
```

Expected: exit code 0.

- [ ] **Step 6: Inspect final diff**

Run:

```bash
git diff --stat
git diff --check
```

Expected: diff stat includes only planned files; `git diff --check` exits 0.

- [ ] **Step 7: Final commit if previous task commits were skipped**

Run only if the earlier task commits were intentionally skipped:

```bash
git add WorkoutTracker/Parsing/SheetLayoutInterpreter.swift WorkoutTracker/Parsing/SheetParser.swift WorkoutTracker/Sheets/SheetWriter.swift Tests/Unit/SheetLayoutInterpreterTests.swift Tests/Unit/SheetParserLogTests.swift Tests/Unit/SheetWriterTests.swift Tests/Unit/SyncCoordinatorLocalWorkbookRoundTripTests.swift Tests/Support/SheetGridFixture.swift CONTEXT.md AGENTS.md CLAUDE.md docs/adr/0001-sheet-as-backend-local-first.md docs/adr/0003-dynamic-cell-targeting.md
git commit -m "feat: target set logs beside last set rpe"
```

Expected: commit succeeds.

---

## Self-Review Notes

- Spec coverage: Tasks 1-4 cover the added `setLog` contract, split parser/writer behavior, missing-column safe failure, local workbook read-after-write confidence, and final-RPE pairing through existing batch tests. Task 5 covers deletion of stale documentation assumptions.
- Placeholder scan: The plan intentionally includes exact file paths, snippets, commands, and expected outcomes for every code-changing task.
- Type consistency: The plan uses one added property name, `DayColumns.setLog`, and the existing `PendingWriteColumn.notes` case remains unchanged for compatibility.
