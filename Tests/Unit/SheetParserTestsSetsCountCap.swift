import Testing

@testable import WorkoutTracker

private func backSquatSetCounts(setsCells: [String: String]) -> [Int] {
    let grid = gridFromA1(
        [
            "C12": "Day 1", "S12": "Day 2",
            "D14": "Sets", "F14": "Reps", "H14": "Load", "J14": "Notes",
            "C15": "Back Squat", "F15": "5", "H15": "RPE7", "F16": "5", "H16": "RPE8",
            "C19": "BW Pull Up", "D19": "2", "F19": "8", "H19": "BW"
        ].merging(setsCells) { _, typed in typed },
        rows: 24,
        cols: 30
    )
    let section = locateWeekSections(in: grid)[0]
    return parseDay(in: grid, section: section, headerIndex: 0).map(\.sets.count)
}

@Test(
    "A Sets count past the cap reads like a non-numeric Sets cell, so a typo cannot crash or hang sync",
    arguments: [
        ("99", 99),
        ("0", 1),
        ("100", 1),
        ("abc", 1),
        ("1000000", 1),
        ("5000000000", 1),
        ("9223372036854775807", 1),
        ("99999999999999999999", 1)
    ]
)
func anchorSetsCountPastTheCapFallsBackToOneSet(typed: String, expectedSets: Int) {
    #expect(backSquatSetCounts(setsCells: ["D15": typed]) == [expectedSets, 2])
}

@Test func aContinuationLineAfterAnOversizedAnchorSetsCountSumsWithoutOverflow() {
    #expect(backSquatSetCounts(setsCells: ["D15": "9223372036854775807", "D16": "1"]) == [2, 2])
}

@Test func aContinuationRowWhoseSetsCountIsPastTheCapIsNotAPrescriptionLine() {
    #expect(backSquatSetCounts(setsCells: ["D15": "3", "D16": "100"]) == [3, 2])
    #expect(backSquatSetCounts(setsCells: ["D15": "3", "D16": "99"]) == [102, 2])
}
