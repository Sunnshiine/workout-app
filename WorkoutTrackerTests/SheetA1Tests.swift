import Testing

@testable import WorkoutTracker

@Test func rendersA1FromZeroBasedIndexes() {
    #expect(indexToA1(row: 0, col: 0) == "A1")
    #expect(indexToA1(row: 15, col: 10) == "K16")
    #expect(indexToA1(row: 0, col: 26) == "AA1")
}

@Test func rendersQuotedSingleCellRange() {
    #expect(singleCellRange(tabName: "Block 27", row: 15, col: 10) == "'Block 27'!K16")
    #expect(singleCellRange(tabName: "Kevin's Block", row: 0, col: 0) == "'Kevin''s Block'!A1")
}
