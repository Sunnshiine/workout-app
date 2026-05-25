import Testing

@testable import WorkoutTracker

@Test func locatesFourDayGroupsPerWeekSection() {
    let grid = gridFromA1(
        [
            "C12": "Day 1", "S12": "Day 2", "AI12": "Day 3", "AX12": "Day 4",
            "C37": "Day 1", "S37": "Day 2", "AI37": "Day 3", "AX37": "Day 4"
        ],
        rows: 40,
        cols: 60
    )

    let sections = locateWeekSections(in: grid)
    #expect(sections.count == 2)
    #expect(sections[0].headerRow == 11)  // row 12 (0-based 11)
    #expect(sections[0].dayStartCols == [2, 18, 34, 49])  // C,S,AI,AX (0-based)
    #expect(sections[0].roleHeaderRow == 13)  // header + 2
}
