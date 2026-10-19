import Testing

@testable import WorkoutTracker

private let dayOneHeaders: [String: String] = [
    "C12": "Day 1", "D14": "Sets", "F14": "Reps", "G14": "%1RM", "H14": "Load", "I14": "Last set RPE",
    "K14": "Notes"
]

@Test func layoutInterpreterReachesTheNotesOfALastDayWiderThanTheFirst() throws {
    let grid = gridFromA1(
        dayOneHeaders.merging([
            "S12": "Day 2", "T14": "Sets", "V14": "Reps", "W14": "%1RM", "X14": "Load", "Y14": "Last set RPE",
            "Z14": "Tempo", "AI14": "Notes", "AM14": "Notes",
            "S15": "Bench Press", "T15": "3", "V15": "5", "AI15": "315x5@7", "AM15": "Coach: deload next week"
        ]) { $1 },
        rows: 20,
        cols: 60
    )

    let layout = SheetLayoutInterpreter().interpret(SheetSnapshot(values: grid))
    let parsed = SheetParser().parse(grid: grid, tabName: "Block 27")

    let dayTwo = try #require(layout.day(at: SessionAddress(week: 1, day: 2)))
    #expect(dayTwo.columns.notes == 34)  // AI
    #expect(dayTwo.columns.lastSetRPE == 24)  // Y
    #expect(dayTwo.columns.span == 18..<35)
    #expect(layout.day(at: SessionAddress(week: 1, day: 1))?.columns.span == 2..<18)
    let bench = try #require(parsed.block.weeks.first?.days.last?.exercises.first)
    #expect(bench.sets[0].state == .logged)
    #expect(bench.sets[0].setLog?.formatted == "315x5@7")
}

@Test func layoutInterpreterReachesTheNotesOfAOneDayWeekWiderThanSixteenColumns() throws {
    let grid = gridFromA1(
        ["C12": "Day 1", "D14": "Sets", "F14": "Reps", "I14": "Last set RPE", "W14": "Notes"],
        rows: 20,
        cols: 40
    )

    let day = try #require(SheetLayoutInterpreter().interpret(SheetSnapshot(values: grid)).day(at: SessionAddress(week: 1, day: 1)))

    #expect(day.columns.notes == 22)  // W
    #expect(day.columns.span == 2..<23)
}

@Test func layoutInterpreterIgnoresANotesHeaderPastALastDayThatHasItsOwn() throws {
    let grid = gridFromA1(
        dayOneHeaders.merging([
            "S12": "Day 2", "T14": "Sets", "AA14": "Notes",
            "S15": "Bench Press", "T15": "3",
            "AM14": "Notes", "AM15": "Coach: deload next week"
        ]) { $1 },
        rows: 20,
        cols: 60
    )

    let dayTwo = try #require(SheetLayoutInterpreter().interpret(SheetSnapshot(values: grid)).day(at: SessionAddress(week: 1, day: 2)))

    #expect(dayTwo.columns.notes == 26)  // AA
    #expect(dayTwo.columns.span == 18..<34)
}

@Test func layoutInterpreterLeavesAMiddleDayWithoutARoleItLacks() throws {
    let grid = gridFromA1(
        [
            "C12": "Day 1", "D14": "Sets", "K14": "Notes",
            "S12": "Day 2", "T14": "Sets", "Y14": "Last set RPE", "AA14": "Notes"
        ],
        rows: 20,
        cols: 40
    )

    let dayOne = try #require(SheetLayoutInterpreter().interpret(SheetSnapshot(values: grid)).day(at: SessionAddress(week: 1, day: 1)))

    #expect(dayOne.columns.lastSetRPE == nil)
    #expect(dayOne.columns.span == 2..<18)
}

@Test func layoutInterpreterKeepsTheFirstDayWidthForALastDayNarrowerThanIt() throws {
    let grid = gridFromA1(
        [
            "C12": "Day 1", "D14": "Sets", "K14": "Notes",
            "M12": "Day 2", "N14": "Sets", "Q14": "Notes", "Y14": "Notes"
        ],
        rows: 20,
        cols: 40
    )

    let dayTwo = try #require(SheetLayoutInterpreter().interpret(SheetSnapshot(values: grid)).day(at: SessionAddress(week: 1, day: 2)))

    #expect(dayTwo.columns.notes == 16)  // Q
    #expect(dayTwo.columns.span == 12..<22)
}
