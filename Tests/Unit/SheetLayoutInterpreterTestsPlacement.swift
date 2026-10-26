import Testing

@testable import WorkoutTracker

private func placement(
    _ grid: SheetGrid,
    exercise: String,
    setIndex: Int,
    rowVisibility: [Int: SheetRowVisibility] = [:]
) throws -> SetLogPlacementResolution {
    let snapshot = SheetSnapshot(values: grid, rowVisibility: rowVisibility)
    let day = try #require(SheetLayoutInterpreter().interpret(snapshot).day(at: SessionAddress(week: 1, day: 1)))
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
    #expect(setOne.kind == .occupiedHeaderVisibleWritableRow)
    #expect(setOne.row == 18)  // first Visible Writable Row below the anchor
    #expect(setOne.col == 10)
    #expect(setOne.listPosition == 0)

    let setTwo = try placed(placement(grid, exercise: "Chest Fly", setIndex: 1))
    #expect(setTwo.kind == .occupiedHeaderVisibleWritableRow)
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

/// Comp SQ is a 1-Set anchor Line (row 15) whose Notes cell holds `line0Notes`, then a 2-Set Line
/// (row 16) whose Notes cell holds `line1Notes`. Rows 17 and 18 are spare rows and Bench Press
/// starts on row 19.
private func coachNoteLineGrid(line0Notes: String = "Brace hard, controlled descent", line1Notes: String = "") -> SheetGrid {
    gridFromA1(
        [
            "C12": "Day 1", "S12": "Day 2",
            "D14": "Sets", "F14": "Reps", "H14": "Load", "J14": "Notes",
            "C15": "Comp SQ", "D15": "1", "F15": "5", "J15": line0Notes,
            "D16": "2", "F16": "5", "J16": line1Notes,
            "C19": "Bench Press", "D19": "2"
        ],
        rows: 26,
        cols: 30
    )
}

@Test func setLogPlacementRedirectsACoachNoteLineToTheExercisesFirstSpareRow() throws {
    let grid = coachNoteLineGrid()

    let setOne = try placed(placement(grid, exercise: "Comp SQ", setIndex: 0))
    #expect(setOne.kind == .protectedLineVisibleWritableRow)
    #expect(setOne.row == 16)  // row 17, the first visible row in the span that is not a Line
    #expect(setOne.col == 9)
    #expect(setOne.listPosition == nil)  // a 1-Set Line addresses the cell whole

    let setTwo = try placed(placement(grid, exercise: "Comp SQ", setIndex: 1))
    #expect(setTwo.kind == .multiLinePrescriptionLine)
    #expect(setTwo.row == 15)  // the unprotected Line keeps its own Notes cell
    #expect(setTwo.listPosition == 0)
}

@Test func setLogPlacementSkipsAHiddenSpareRowForACoachNoteLine() throws {
    let resolution = try placement(
        coachNoteLineGrid(),
        exercise: "Comp SQ",
        setIndex: 0,
        rowVisibility: [16: SheetRowVisibility(hiddenByUser: true)]
    )

    #expect(try placed(resolution).row == 17)
}

@Test func setLogPlacementGivesEachCoachNoteLineItsOwnSpareRow() throws {
    let grid = coachNoteLineGrid(line1Notes: "Drop 10%, same bar speed")

    let lineZero = try placed(placement(grid, exercise: "Comp SQ", setIndex: 0))
    #expect(lineZero.row == 16)

    let lineOneSetOne = try placed(placement(grid, exercise: "Comp SQ", setIndex: 1))
    let lineOneSetTwo = try placed(placement(grid, exercise: "Comp SQ", setIndex: 2))
    #expect(lineOneSetOne.kind == .protectedLineVisibleWritableRow)
    #expect(lineOneSetOne.row == 17)
    #expect(lineOneSetOne.listPosition == 0)
    #expect(lineOneSetTwo.row == 17)
    #expect(lineOneSetTwo.listPosition == 1)
}

@Test func setLogPlacementBlocksACoachNoteLineWithoutASpareRow() throws {
    let resolution = try placement(
        coachNoteLineGrid(),
        exercise: "Comp SQ",
        setIndex: 0,
        rowVisibility: [16: SheetRowVisibility(hiddenByUser: true), 17: SheetRowVisibility(hiddenByFilter: true)]
    )

    #expect(resolution == .occupiedHeaderBlocksSetRow)
}

@Test func setLogPlacementKeepsALegacyLogLineOnItsOwnNotesCell() throws {
    // A Legacy Log is completion evidence, not a Coach Note: its Line is not redirected, so the
    // writer's value check refuses the write instead of logging the Line a second time elsewhere.
    let placement = try placed(placement(coachNoteLineGrid(line0Notes: "70@10, 80"), exercise: "Comp SQ", setIndex: 0))

    #expect(placement.kind == .multiLinePrescriptionLine)
    #expect(placement.row == 14)
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

    #expect(try placement(grid, exercise: "Squat", setIndex: 0) == .occupiedHeaderBlocksSetRow)
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
