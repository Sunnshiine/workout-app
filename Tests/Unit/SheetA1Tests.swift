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

@Test func parsesA1CellReferencesToZeroBasedIndexes() throws {
    #expect(try #require(a1CellIndex("A1")) == (row: 0, col: 0))
    #expect(try #require(a1CellIndex("K15")) == (row: 14, col: 10))
    #expect(try #require(a1CellIndex("AA100")) == (row: 99, col: 26))
}

@Test func rejectsReferencesThatAreNotASingleA1Cell() {
    for reference in ["", "15", "K", "K0", "K015", "K15 ", "K-1", "k15", "1K5", "A1:B2"] {
        #expect(a1CellIndex(reference) == nil, "\(reference)")
    }
}
