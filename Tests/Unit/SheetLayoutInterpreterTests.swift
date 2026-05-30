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
    let grid = gridFromA1(
        [
            "C12": "Day 1", "S12": "Day 2",
            "D14": "Sets", "K14": "Notes",
            "C18": "Chest Fly", "D18": "2", "K18": "Keep elbows soft",
            "K19": "25x12@7",
            "K20": "20x10@8",
            "C25": "Bench Press", "D25": "1"
        ],
        rows: 32,
        cols: 30
    )

    let day = try #require(SheetLayoutInterpreter().interpret(grid).day(week: 1, day: 1))
    let anchor = try #require(day.exerciseAnchors.first)
    let headerNotes = anchor.headerNotes(in: grid, notesColumn: day.columns.notes)

    #expect(headerNotes.value == "Keep elbows soft")
    #expect(headerNotes.usesCompactHeaderSetOne == false)
    #expect(anchor.usesCompactHeaderSetOne(headerNotes: headerNotes) == false)
    #expect(headerNotes.hasProtectedValue)
    #expect(anchor.continuationSetRow(for: 0) == 18)
    #expect(anchor.continuationSetRow(for: 1) == 19)
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
