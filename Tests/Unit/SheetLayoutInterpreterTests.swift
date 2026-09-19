import Testing

@testable import WorkoutTracker

@Test func layoutInterpreterDiscoversShiftedWeekAndDayGroups() throws {
    let grid = gridFromA1(
        [
            "D10": "Day 1", "N10": "Day 2", "X10": "Day 3", "AH10": "Day 4",
            "D30": "Day 1", "N30": "Day 2", "X30": "Day 3", "AH30": "Day 4"
        ],
        rows: 40,
        cols: 45
    )

    let layout = SheetLayoutInterpreter().interpret(grid)

    #expect(layout.weeks.count == 2)
    let firstWeek = try #require(layout.week(number: 1))
    #expect(firstWeek.number == 1)
    #expect(firstWeek.headerRow == 9)
    #expect(firstWeek.dateRow == 10)
    #expect(firstWeek.roleHeaderRow == 11)
    #expect(firstWeek.endRow == 29)
    #expect(firstWeek.days.map(\.number) == [1, 2, 3, 4])
    #expect(firstWeek.days.map(\.columns.name) == [3, 13, 23, 33])
    #expect(firstWeek.days[0].columns.span == 3..<13)
    #expect(firstWeek.days[3].columns.span == 33..<43)

    let secondWeek = try #require(layout.week(number: 2))
    #expect(secondWeek.headerRow == 29)
    #expect(secondWeek.endRow == grid.count)
}

@Test func layoutInterpreterDiscoversShiftedRoleColumns() throws {
    let grid = gridFromA1(
        [
            "C12": "Day 1", "S12": "Day 2",
            "E14": "Sets", "G14": "Reps", "H14": "%1RM", "J14": "Load",
            "L14": "Last set RPE", "N14": "Notes"
        ],
        rows: 20,
        cols: 30
    )

    let day = try #require(SheetLayoutInterpreter().interpret(grid).day(week: 1, day: 1))

    #expect(day.columns.name == 2)
    #expect(day.columns.sets == 4)
    #expect(day.columns.reps == 6)
    #expect(day.columns.percentOneRM == 7)
    #expect(day.columns.load == 9)
    #expect(day.columns.lastSetRPE == 11)
    #expect(day.columns.notes == 13)
}

@Test func layoutInterpreterDiscoversShiftedExerciseAnchorsAndNextBoundaries() throws {
    let grid = gridFromA1(
        [
            "C12": "Day 1", "S12": "Day 2",
            "D14": "Sets", "K14": "Notes",
            "C18": "Squat", "D18": "2",
            "C25": "Bench Press", "D25": "1"
        ],
        rows: 32,
        cols: 30
    )

    let day = try #require(SheetLayoutInterpreter().interpret(grid).day(week: 1, day: 1))

    #expect(day.exerciseAnchors.map(\.name) == ["Squat", "Bench Press"])
    #expect(day.exerciseAnchors.map(\.row) == [17, 24])
    #expect(day.exerciseAnchors.map(\.nextAnchorRow) == [24, grid.count])
}

@Test func layoutInterpreterDescribesProtectedHeaderAndContinuationRows() throws {
    let grid = coachNoteLayoutGrid()

    let day = try #require(SheetLayoutInterpreter().interpret(grid).day(week: 1, day: 1))
    let anchor = try #require(day.exerciseAnchors.first)

    #expect(anchor.headerNotesRole(in: grid, cols: day.columns) == .coachNote("Keep elbows soft"))
    #expect(anchor.continuationSetRow(for: 0) == 18)
    #expect(anchor.continuationSetRow(for: 1) == 19)
}

@Test func headerNotesRoleReadsSetLogContentAsSetLogsAtEverySetCount() {
    // An empty cell, a single Set-Log-list value, and a comma list bounded by the Set count whose
    // every entry is a Set-Log-list value all carry Set Logs. None of them is coach content.
    #expect(HeaderNotesRole(notesCell: "", setCount: 3) == .setLogList)
    #expect(HeaderNotesRole(notesCell: "skip", setCount: 1) == .setLogList)
    #expect(HeaderNotesRole(notesCell: "185x5@8", setCount: 3) == .setLogList)
    #expect(HeaderNotesRole(notesCell: "25x12@7, skip", setCount: 3) == .setLogList)
    #expect(HeaderNotesRole(notesCell: "185x5@8, 190x5@9", setCount: 2) == .setLogList)
}

@Test func headerNotesRoleStopsReadingSetLogsPastThePrescribedSetCount() {
    // A list longer than the Set count, or with an entry that is not a Set-Log-list value, is not
    // this Exercise's Set Logs; it falls back to the coach-content classification.
    #expect(HeaderNotesRole(notesCell: "25x12@7, skip, 30x10@8", setCount: 2) == .coachNote("25x12@7, skip, 30x10@8"))
    #expect(HeaderNotesRole(notesCell: "25x12@7, hold", setCount: 3) == .coachNote("25x12@7, hold"))
}

@Test func headerNotesRoleClassifiesResultShapedValuesAsLegacyLog() {
    #expect(HeaderNotesRole(notesCell: "25x12, 12", setCount: 2) == .legacyLog("25x12, 12"))
    #expect(HeaderNotesRole(notesCell: "70@10, 55", setCount: 2) == .legacyLog("70@10, 55"))
    #expect(HeaderNotesRole(notesCell: "55x8, 60x7@9.5", setCount: 2) == .legacyLog("55x8, 60x7@9.5"))
    #expect(HeaderNotesRole(notesCell: "70, 80, 90x6", setCount: 3) == .legacyLog("70, 80, 90x6"))
    #expect(HeaderNotesRole(notesCell: "70@10, 80", setCount: 2) == .legacyLog("70@10, 80"))
}

@Test func headerNotesRoleClassifiesInstructionShapedValuesAsCoachNote() {
    #expect(HeaderNotesRole(notesCell: "Start w/ 10 sec hold", setCount: 2) == .coachNote("Start w/ 10 sec hold"))
    #expect(HeaderNotesRole(notesCell: "Superset w/ curls", setCount: 2) == .coachNote("Superset w/ curls"))
    #expect(HeaderNotesRole(notesCell: "Keep elbows soft", setCount: 3) == .coachNote("Keep elbows soft"))
}

@Test func headerNotesRoleProtectsOnlyCoachAuthoredContentFromSetLogWrites() {
    // A Coach Note and a Legacy Log are both coach-authored: Set Logs must not be written into the
    // cell and it is never overwritten (ADR-0005). Everything else carries Set Logs, so the two
    // answers cannot disagree the way the former value-only and Set-count-aware predicates did.
    #expect(HeaderNotesRole(notesCell: "Keep elbows soft", setCount: 2).holdsSetLogs == false)
    #expect(HeaderNotesRole(notesCell: "70@10, 80", setCount: 2).holdsSetLogs == false)
    #expect(HeaderNotesRole(notesCell: "25x12, 12", setCount: 2).holdsSetLogs == false)
    #expect(HeaderNotesRole(notesCell: "", setCount: 2).holdsSetLogs == true)
    #expect(HeaderNotesRole(notesCell: "185x5@8", setCount: 2).holdsSetLogs == true)
    #expect(HeaderNotesRole(notesCell: "185x5@8, 190x5@9", setCount: 2).holdsSetLogs == true)
}

private func placement(
    _ grid: SheetGrid,
    exercise: String,
    setIndex: Int,
    rowVisibility: [Int: SheetRowVisibility] = [:]
) throws -> SetLogPlacementResolution {
    let snapshot = SheetSnapshot(values: grid, rowVisibility: rowVisibility)
    let day = try #require(SheetLayoutInterpreter().interpret(snapshot).day(week: 1, day: 1))
    let anchor = try #require(day.exerciseAnchors.first { $0.name == exercise })
    return anchor.setLogPlacement(for: setIndex, in: snapshot, cols: day.columns)
}

private func placed(_ resolution: SetLogPlacementResolution) throws -> SetLogPlacement {
    guard case .placed(let placement) = resolution else {
        Issue.record("Expected a resolved placement, got \(resolution)")
        throw PlacementTestError.notPlaced
    }
    return placement
}

private enum PlacementTestError: Error { case notPlaced }

@Test func setLogPlacementResolvesCompactHeaderListForKevinCompactTemplate() throws {
    // Kevin single-anchor compact: Set logs live comma-separated in the one header Notes cell.
    let grid = gridFromA1(
        [
            "C12": "Day 1", "S12": "Day 2",
            "D14": "Sets", "K14": "Notes",
            "C15": "Ab of Choice", "D15": "2", "K15": "25x12@7",
            "C18": "Bench"
        ],
        rows: 30,
        cols: 30
    )

    let setOne = try placed(placement(grid, exercise: "Ab of Choice", setIndex: 0))
    #expect(setOne.kind == .compactHeaderList)
    #expect(setOne.row == 14)  // anchor row (C15)
    #expect(setOne.col == 10)  // Notes column K
    #expect(setOne.listPosition == 0)

    let setTwo = try placed(placement(grid, exercise: "Ab of Choice", setIndex: 1))
    #expect(setTwo.kind == .compactHeaderList)
    #expect(setTwo.row == 14)
    #expect(setTwo.listPosition == 1)
}

@Test func setLogPlacementDropsListPositionForSingleCompactSetOne() throws {
    // A single prescribed Set writes the header cell whole — no comma list, so no list position.
    let grid = gridFromA1(
        [
            "C12": "Day 1", "S12": "Day 2",
            "D14": "Sets", "K14": "Notes",
            "C15": "Ab of Choice", "D15": "1",
            "C18": "Bench"
        ],
        rows: 30,
        cols: 30
    )

    let placement = try placed(placement(grid, exercise: "Ab of Choice", setIndex: 0))
    #expect(placement.kind == .compactHeaderList)
    #expect(placement.row == 14)
    #expect(placement.listPosition == nil)
}

@Test func setLogPlacementResolvesCompactListForBlankHeader() throws {
    // A blank header Notes cell is itself a compact Set-One: prescribed Sets aggregate in the one
    // anchor cell rather than spilling onto per-Set rows.
    let grid = gridFromA1(
        [
            "C12": "Day 1", "S12": "Day 2",
            "D14": "Sets", "K14": "Notes",
            "C15": "Squat", "D15": "2",
            "C20": "Bench"
        ],
        rows: 30,
        cols: 30
    )

    let setOne = try placed(placement(grid, exercise: "Squat", setIndex: 0))
    #expect(setOne.kind == .compactHeaderList)
    #expect(setOne.row == 14)  // anchor row
    #expect(setOne.col == 10)
    #expect(setOne.listPosition == 0)

    let setTwo = try placed(placement(grid, exercise: "Squat", setIndex: 1))
    #expect(setTwo.kind == .compactHeaderList)
    #expect(setTwo.row == 14)
    #expect(setTwo.listPosition == 1)
}

@Test func setLogPlacementSpillsOverflowSetOntoVisibleRow() throws {
    // An extra Set beyond the prescribed count has no slot in the compact header, so it lands on
    // its own visible row below the anchor — the visible Set-log row leaf.
    let grid = gridFromA1(
        [
            "C12": "Day 1", "S12": "Day 2",
            "D14": "Sets", "K14": "Notes",
            "C15": "Squat", "D15": "1",
            "C20": "Bench"
        ],
        rows: 30,
        cols: 30
    )

    let setOne = try placed(placement(grid, exercise: "Squat", setIndex: 0))
    #expect(setOne.kind == .compactHeaderList)
    #expect(setOne.row == 14)
    #expect(setOne.listPosition == nil)  // single prescribed Set: no comma list

    let overflow = try placed(placement(grid, exercise: "Squat", setIndex: 1))
    #expect(overflow.kind == .visibleSetLogRow)
    #expect(overflow.row == 15)  // first visible row past the anchor
    #expect(overflow.col == 10)
    #expect(overflow.listPosition == nil)
}

@Test func setLogPlacementRedirectsProtectedHeaderToVisibleWritableRow() throws {
    let grid = coachNoteLayoutGrid()  // Chest Fly anchor row 17, protected header, 2 sets

    let setOne = try placed(placement(grid, exercise: "Chest Fly", setIndex: 0))
    #expect(setOne.kind == .protectedHeaderVisibleWritableRow)
    #expect(setOne.row == 18)  // first Visible Writable Row below the anchor
    #expect(setOne.col == 10)
    #expect(setOne.listPosition == 0)

    let setTwo = try placed(placement(grid, exercise: "Chest Fly", setIndex: 1))
    #expect(setTwo.kind == .protectedHeaderVisibleWritableRow)
    #expect(setTwo.row == 18)  // aggregate list shares one Visible Writable Row cell
    #expect(setTwo.listPosition == 1)
}

@Test func setLogPlacementResolvesMultiLinePrescriptionLines() throws {
    // J. Alarcon per-row template: Comp BP is a 1-set line (row 16) then a 2-set line (row 17).
    let grid = gridFromA1(
        [
            "C12": "Day 1", "S12": "Day 2",
            "D14": "Sets", "F14": "Reps", "H14": "Load", "J14": "Notes",
            "C15": "Comp SQ", "D15": "1", "F15": "5",
            "D16": "1", "F16": "5",
            "C17": "Comp BP", "D17": "1", "F17": "5",
            "D18": "2", "F18": "7",
            "C19": "Hip Thrust", "D19": "2"
        ],
        rows: 26,
        cols: 30
    )

    let bpSetOne = try placed(placement(grid, exercise: "Comp BP", setIndex: 0))
    #expect(bpSetOne.kind == .multiLinePrescriptionLine)
    #expect(bpSetOne.row == 16)  // Comp BP's first line (C17)
    #expect(bpSetOne.col == 9)  // Notes column J
    #expect(bpSetOne.listPosition == 0)

    let bpSetTwo = try placed(placement(grid, exercise: "Comp BP", setIndex: 1))
    #expect(bpSetTwo.kind == .multiLinePrescriptionLine)
    #expect(bpSetTwo.row == 17)  // second line (row 18) holds Sets 2 and 3
    #expect(bpSetTwo.listPosition == 0)

    let bpSetThree = try placed(placement(grid, exercise: "Comp BP", setIndex: 2))
    #expect(bpSetThree.kind == .multiLinePrescriptionLine)
    #expect(bpSetThree.row == 17)
    #expect(bpSetThree.listPosition == 1)
}

@Test func setLogPlacementResolvesNotesColumnFromDuplicateRoleHeaders() throws {
    // A stray duplicate "Sets" header must not shift the resolved Notes column.
    let grid = gridFromA1(
        [
            "C12": "Day 1", "S12": "Day 2",
            "D14": "Sets", "E14": "Sets", "K14": "Notes",
            "C15": "Squat", "E15": "2",
            "C20": "Bench"
        ],
        rows: 30,
        cols: 30
    )

    let placement = try placed(placement(grid, exercise: "Squat", setIndex: 0))
    #expect(placement.kind == .compactHeaderList)
    #expect(placement.col == 10)  // Notes column K, unaffected by the duplicate Sets header
    #expect(placement.row == 14)  // anchor row
}

@Test func setLogPlacementBlocksProtectedHeaderWithoutWritableRow() throws {
    // Coach Note header with the next Exercise immediately below leaves no safe row: conflict.
    let grid = gridFromA1(
        [
            "C12": "Day 1", "S12": "Day 2",
            "D14": "Sets", "K14": "Notes",
            "C15": "Squat", "D15": "1", "K15": "Keep elbows soft",
            "C16": "Bench"
        ],
        rows: 30,
        cols: 30
    )

    #expect(try placement(grid, exercise: "Squat", setIndex: 0) == .protectedHeaderBlocksSetRow)
}

@Test func setLogPlacementReportsRowNotFoundWhenSetExceedsSpan() throws {
    let grid = gridFromA1(
        [
            "C12": "Day 1", "S12": "Day 2",
            "D14": "Sets", "K14": "Notes",
            "C15": "Squat", "D15": "1",
            "C16": "Bench"
        ],
        rows: 30,
        cols: 30
    )

    // Set 2 (index 1) has no visible row before the next Exercise, and the header is writable.
    #expect(try placement(grid, exercise: "Squat", setIndex: 1) == .setRowNotFound)
}

@Test func setLogPlacementReportsMissingNotesColumn() throws {
    let grid = gridFromA1(
        [
            "C12": "Day 1", "S12": "Day 2",
            "D14": "Sets",
            "C15": "Squat", "D15": "1",
            "C16": "Bench"
        ],
        rows: 30,
        cols: 30
    )

    #expect(try placement(grid, exercise: "Squat", setIndex: 0) == .notesColumnMissing)
}

@Test func layoutInterpreterReturnsNilForMissingWeekOrDayLookups() {
    let emptyLayout = SheetLayoutInterpreter().interpret(gridFromA1([:], rows: 5, cols: 5))
    #expect(emptyLayout.weeks.isEmpty)
    #expect(emptyLayout.week(number: 1) == nil)
    #expect(emptyLayout.day(week: 1, day: 1) == nil)

    let oneDayLayout = SheetLayoutInterpreter().interpret(
        gridFromA1(["C12": "Day 1"], rows: 20, cols: 20)
    )
    #expect(oneDayLayout.week(number: 2) == nil)
    #expect(oneDayLayout.day(week: 1, day: 2) == nil)
}
