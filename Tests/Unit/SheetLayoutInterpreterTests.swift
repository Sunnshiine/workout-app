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

    let layout = SheetLayoutInterpreter().interpret(SheetSnapshot(values: grid))

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

    let day = try #require(SheetLayoutInterpreter().interpret(SheetSnapshot(values: grid)).day(at: SessionAddress(week: 1, day: 1)))

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

    let day = try #require(SheetLayoutInterpreter().interpret(SheetSnapshot(values: grid)).day(at: SessionAddress(week: 1, day: 1)))

    #expect(day.exerciseAnchors.map(\.name) == ["Squat", "Bench Press"])
    #expect(day.exerciseAnchors.map(\.row) == [17, 24])
    #expect(day.exerciseAnchors.map(\.nextAnchorRow) == [24, grid.count])
}

@Test func layoutInterpreterSkipsRetiredExerciseRowsHiddenInTheSheet() throws {
    let snapshot = SheetSnapshot(
        values: gridFromA1(
            [
                "C12": "Day 1", "S12": "Day 2",
                "D14": "Sets", "F14": "Reps", "K14": "Notes",
                "C15": "Back Squat", "D15": "3", "F15": "5",
                "C17": "0:1:0 Hamstring Curl", "D17": "2", "F17": "10",
                "C19": "2-3:1:0 BB RDL", "D19": "2", "F19": "8"
            ],
            rows: 32,
            cols: 30
        ),
        rowVisibility: [16: SheetRowVisibility(hiddenByUser: true)]
    )

    let day = try #require(SheetLayoutInterpreter().interpret(snapshot).day(at: SessionAddress(week: 1, day: 1)))

    #expect(day.exerciseAnchors.map(\.name) == ["Back Squat", "2-3:1:0 BB RDL"])
    #expect(day.exerciseAnchors.map(\.row) == [14, 18])
    // Back Squat stops at the hidden row rather than swallowing it: the retired movement's block
    // still ends the block above it.
    #expect(day.exerciseAnchors.map(\.nextAnchorRow) == [16, 32])

    let backSquat = try #require(day.exerciseAnchors.first)
    #expect(
        backSquat.prescriptionLines(in: snapshot, setsColumn: day.columns.sets)
            == [PrescriptionLine(row: 14, setCount: 3, firstSetIndex: 0)]
    )
}

/// A coach who retires a multi-line movement may hide only its anchor row. Its continuation rows
/// stay visible, and they must go with it instead of becoming extra Sets of the Exercise above.
@Test func layoutInterpreterDoesNotAbsorbAHiddenExercisesVisibleContinuationRows() throws {
    let snapshot = SheetSnapshot(
        values: gridFromA1(
            [
                "C12": "Day 1", "S12": "Day 2",
                "D14": "Sets", "F14": "Reps", "K14": "Notes",
                "C15": "Back Squat", "D15": "3", "F15": "5",
                "C17": "0:1:0 Hamstring Curl", "D17": "2", "F17": "10",
                "D18": "2", "F18": "10",
                "C19": "2-3:1:0 BB RDL", "D19": "2", "F19": "8"
            ],
            rows: 32,
            cols: 30
        ),
        rowVisibility: [16: SheetRowVisibility(hiddenByUser: true)]
    )

    let day = try #require(SheetLayoutInterpreter().interpret(snapshot).day(at: SessionAddress(week: 1, day: 1)))
    let backSquat = try #require(day.exerciseAnchors.first)

    #expect(day.exerciseAnchors.map(\.name) == ["Back Squat", "2-3:1:0 BB RDL"])
    #expect(
        backSquat.prescriptionLines(in: snapshot, setsColumn: day.columns.sets)
            == [PrescriptionLine(row: 14, setCount: 3, firstSetIndex: 0)]
    )
}

@Test func layoutInterpreterSkipsFilterHiddenExerciseRowsTheSameWayAsUserHiddenOnes() throws {
    let cells = [
        "C12": "Day 1", "S12": "Day 2",
        "D14": "Sets", "K14": "Notes",
        "C15": "Back Squat", "D15": "3",
        "C17": "0:1:0 Hamstring Curl", "D17": "2"
    ]
    let grid = gridFromA1(cells, rows: 32, cols: 30)

    for hidden in [SheetRowVisibility(hiddenByUser: true), SheetRowVisibility(hiddenByFilter: true)] {
        let snapshot = SheetSnapshot(values: grid, rowVisibility: [16: hidden])
        let day = try #require(SheetLayoutInterpreter().interpret(snapshot).day(at: SessionAddress(week: 1, day: 1)))
        #expect(day.exerciseAnchors.map(\.name) == ["Back Squat"])
    }
}

@Test func layoutInterpreterDescribesProtectedHeaderAndContinuationRows() throws {
    let grid = coachNoteLayoutGrid()

    let day = try #require(SheetLayoutInterpreter().interpret(SheetSnapshot(values: grid)).day(at: SessionAddress(week: 1, day: 1)))
    let anchor = try #require(day.exerciseAnchors.first)

    #expect(anchor.headerNotesRole(in: grid, cols: day.columns) == .coachNote("Keep elbows soft"))
    let continuationRows = anchor.visibleSetLogRows(
        headerHoldsSetLogs: false,
        in: SheetSnapshot(values: grid)
    )
    #expect(continuationRows.prefix(2) == [18, 19])
}

@Test func headerNotesRoleReadsSetLogContentAsSetLogsAtEverySetCount() {
    #expect(HeaderNotesRole(notesCell: "", setCount: 3) == .setLogList)
    #expect(HeaderNotesRole(notesCell: "skip", setCount: 1) == .setLogList)
    #expect(HeaderNotesRole(notesCell: "185x5@8", setCount: 3) == .setLogList)
    #expect(HeaderNotesRole(notesCell: "25x12@7, skip", setCount: 3) == .setLogList)
    #expect(HeaderNotesRole(notesCell: "185x5@8, 190x5@9", setCount: 2) == .setLogList)
}

@Test func headerNotesRoleStopsReadingSetLogsPastThePrescribedSetCount() {
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
    #expect(HeaderNotesRole(notesCell: "Keep elbows soft", setCount: 2).holdsSetLogs == false)
    #expect(HeaderNotesRole(notesCell: "70@10, 80", setCount: 2).holdsSetLogs == false)
    #expect(HeaderNotesRole(notesCell: "25x12, 12", setCount: 2).holdsSetLogs == false)
    #expect(HeaderNotesRole(notesCell: "", setCount: 2).holdsSetLogs == true)
    #expect(HeaderNotesRole(notesCell: "185x5@8", setCount: 2).holdsSetLogs == true)
    #expect(HeaderNotesRole(notesCell: "185x5@8, 190x5@9", setCount: 2).holdsSetLogs == true)
}

@Test func layoutInterpreterReturnsNilForMissingWeekOrDayLookups() {
    let emptyLayout = SheetLayoutInterpreter().interpret(SheetSnapshot(values: gridFromA1([:], rows: 5, cols: 5)))
    #expect(emptyLayout.weeks.isEmpty)
    #expect(emptyLayout.week(number: 1) == nil)
    #expect(emptyLayout.day(at: SessionAddress(week: 1, day: 1)) == nil)

    let oneDayLayout = SheetLayoutInterpreter().interpret(
        SheetSnapshot(values: gridFromA1(["C12": "Day 1"], rows: 20, cols: 20))
    )
    #expect(oneDayLayout.week(number: 2) == nil)
    #expect(oneDayLayout.day(at: SessionAddress(week: 1, day: 2)) == nil)
}

@Test func layoutInterpreterNumbersADayByItsHeaderNotItsPosition() {
    let grid = gridFromA1(
        ["S12": "Day 2", "T14": "Sets", "AA14": "Notes", "S15": "Squat", "T15": "2"],
        rows: 20,
        cols: 40
    )

    let layout = SheetLayoutInterpreter().interpret(SheetSnapshot(values: grid))

    #expect(layout.weeks.count == 1)
    #expect(layout.week(number: 1)?.days.map(\.number) == [2])
    #expect(layout.day(at: SessionAddress(week: 1, day: 1)) == nil)
    #expect(layout.day(at: SessionAddress(week: 1, day: 2))?.columns.name == 18)
    #expect(layout.day(at: SessionAddress(week: 1, day: 2))?.columns.notes == 26)
    #expect(layout.day(at: SessionAddress(week: 1, day: 2))?.exerciseAnchors.map(\.name) == ["Squat"])
}

@Test func layoutInterpreterKeepsTheNumberOfADayAfterAGap() {
    let grid = gridFromA1(["C12": "Day 1", "S12": "Day 3"], rows: 20, cols: 40)

    let layout = SheetLayoutInterpreter().interpret(SheetSnapshot(values: grid))

    #expect(layout.week(number: 1)?.days.map(\.number) == [1, 3])
    #expect(layout.day(at: SessionAddress(week: 1, day: 2)) == nil)
    #expect(layout.day(at: SessionAddress(week: 1, day: 3))?.columns.span == 18..<34)
    #expect(layout.week(number: 1)?.ignoredDayHeaders == [])
}

@Test func layoutInterpreterNumbersSwappedDayHeadersByTheirText() {
    let grid = gridFromA1(["C12": "Day 2", "S12": "Day 1"], rows: 20, cols: 40)

    let layout = SheetLayoutInterpreter().interpret(SheetSnapshot(values: grid))

    #expect(layout.week(number: 1)?.days.map(\.number) == [1, 2])
    #expect(layout.week(number: 1)?.days.map(\.columns.span) == [18..<34, 2..<18])
    #expect(layout.day(at: SessionAddress(week: 1, day: 1))?.columns.span == 18..<34)
    #expect(layout.day(at: SessionAddress(week: 1, day: 2))?.columns.span == 2..<18)
}

@Test func layoutInterpreterReadsAZeroPaddedDayNumber() {
    let grid = gridFromA1(["C12": "Day 01", "S12": "Day 007"], rows: 20, cols: 40)

    let layout = SheetLayoutInterpreter().interpret(SheetSnapshot(values: grid))

    #expect(layout.week(number: 1)?.days.map(\.number) == [1, 7])
    #expect(layout.day(at: SessionAddress(week: 1, day: 7))?.columns.name == 18)
    #expect(layout.week(number: 1)?.ignoredDayHeaders == [])
}

@Test func layoutInterpreterMakesNoSessionOfADuplicatedDayNumber() {
    let grid = gridFromA1(
        [
            "C12": "Day 1", "S12": "Day 1", "AI12": "Day 3",
            "K14": "Notes", "AA14": "Notes", "AQ14": "Notes",
            "C37": "Day 1", "S37": "Day 2"
        ],
        rows: 45,
        cols: 55
    )

    let layout = SheetLayoutInterpreter().interpret(SheetSnapshot(values: grid))

    #expect(layout.weeks.map(\.number) == [1, 2])
    #expect(layout.weeks.map { $0.days.map(\.number) } == [[3], [1, 2]])
    #expect(layout.day(at: SessionAddress(week: 1, day: 1)) == nil)
    #expect(layout.day(at: SessionAddress(week: 1, day: 3))?.columns.span == 34..<50)
    #expect(layout.day(at: SessionAddress(week: 1, day: 3))?.columns.notes == 42)
    #expect(layout.weeks.map(\.ignoredDayHeaders) == [[.repeated(dayNumber: 1)], []])
}

@Test func layoutInterpreterMakesNoSessionOfADayNumberOutsideTheWeek() {
    let grid = gridFromA1(
        ["C12": "Day 0", "S12": "Day 007", "AI12": "Day 8", "AX12": "Day 99999999999999999999"],
        rows: 20,
        cols: 70
    )

    let layout = SheetLayoutInterpreter().interpret(SheetSnapshot(values: grid))

    #expect(layout.week(number: 1)?.days.map(\.number) == [7])
    #expect(layout.day(at: SessionAddress(week: 1, day: 7))?.columns.span == 18..<34)
    #expect(
        layout.week(number: 1)?.ignoredDayHeaders == [
            .outsideWeek(header: "Day 0"),
            .outsideWeek(header: "Day 8"),
            .outsideWeek(header: "Day 99999999999999999999")
        ]
    )
}
