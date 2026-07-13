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
    let headerNotes = anchor.headerNotes(in: grid, notesColumn: day.columns.notes)

    #expect(headerNotes.value == "Keep elbows soft")
    let setCount = anchor.prescribedSetCount(in: grid, setsColumn: day.columns.sets)
    #expect(headerNotes.usesCompactHeaderSetOne == false)
    #expect(anchor.usesCompactHeaderSetOne(headerNotes: headerNotes, setCount: setCount) == false)
    #expect(headerNotes.hasProtectedValue)
    #expect(anchor.continuationSetRow(for: 0) == 18)
    #expect(anchor.continuationSetRow(for: 1) == 19)
}

@Test func anchorCompactHeaderSetOneDecisionFoldsInTheAggregateHalf() {
    let anchor = SheetLayoutExerciseAnchor(name: "Squat", row: 3, nextAnchorRow: 8)

    func decision(_ value: String, setCount: Int) -> Bool {
        anchor.usesCompactHeaderSetOne(headerNotes: SheetLayoutHeaderNotes(value: value), setCount: setCount)
    }

    // The single Set-count-aware query must return the same answer the five former inline
    // `usesCompactHeaderSetOne(headerNotes:) || isCompactAggregateHeader(value, setCount:)` sites did.
    func expectedFold(_ value: String, setCount: Int) -> Bool {
        let headerNotes = SheetLayoutHeaderNotes(value: value)
        return headerNotes.usesCompactHeaderSetOne
            || SetLogToken.isCompactAggregateHeader(value, setCount: setCount)
    }

    // Header-only half: empty and single Set-Log-list values are compact Set-One.
    #expect(decision("", setCount: 3) == expectedFold("", setCount: 3))
    #expect(decision("185x5@8", setCount: 3) == expectedFold("185x5@8", setCount: 3))
    #expect(decision("185x5@8", setCount: 3) == true)

    // Coach note: neither half fires.
    #expect(decision("Keep elbows soft", setCount: 3) == false)

    // Aggregate half: a comma list bounded by the Set count of Set-Log-list values is compact.
    #expect(decision("25x12@7, skip", setCount: 3) == true)
    #expect(decision("25x12@7, skip", setCount: 3) == expectedFold("25x12@7, skip", setCount: 3))

    // Aggregate boundary: a list longer than the Set count is not compact.
    #expect(decision("25x12@7, skip, 30x10@8", setCount: 2) == false)

    // Aggregate boundary: an entry that is not a Set-Log-list value is not compact.
    #expect(decision("25x12@7, hold", setCount: 3) == false)
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

@Test func headerNotesClassifiesResultShapedValuesAsLegacyLog() {
    #expect(SheetLayoutHeaderNotes(value: "25x12, 12").isLegacyLog == true)
    #expect(SheetLayoutHeaderNotes(value: "70@10, 55").isLegacyLog == true)
    #expect(SheetLayoutHeaderNotes(value: "55x8, 60x7@9.5").isLegacyLog == true)
    #expect(SheetLayoutHeaderNotes(value: "70, 80, 90x6").isLegacyLog == true)
    #expect(SheetLayoutHeaderNotes(value: "BWx12@7").isLegacyLog == false)  // single valid SetLog → compact
}

@Test func headerNotesDoesNotClassifyInstructionShapedNotesAsLegacyLog() {
    #expect(SheetLayoutHeaderNotes(value: "Start w/ 10 sec hold").isLegacyLog == false)
    #expect(SheetLayoutHeaderNotes(value: "Superset w/ curls").isLegacyLog == false)
    #expect(SheetLayoutHeaderNotes(value: "Keep elbows soft").isLegacyLog == false)
}

@Test func headerNotesDoesNotClassifyCompactValuesAsLegacyLog() {
    #expect(SheetLayoutHeaderNotes(value: "").isLegacyLog == false)
    #expect(SheetLayoutHeaderNotes(value: "skip").isLegacyLog == false)
    #expect(SheetLayoutHeaderNotes(value: "185x5@8").isLegacyLog == false)
}

@Test func headerNotesIsCoachNoteForInstructionShapedProtectedValues() {
    #expect(SheetLayoutHeaderNotes(value: "Start w/ 10 sec hold").isCoachNote == true)
    #expect(SheetLayoutHeaderNotes(value: "Superset w/ curls").isCoachNote == true)
    #expect(SheetLayoutHeaderNotes(value: "").isCoachNote == false)
    #expect(SheetLayoutHeaderNotes(value: "25x12, 12").isCoachNote == false)
    #expect(SheetLayoutHeaderNotes(value: "185x5@8").isCoachNote == false)
}
