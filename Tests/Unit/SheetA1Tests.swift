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

@Test func splitsARangeIntoItsTabNameAndCellReference() throws {
    let bare = try #require(splitA1Range("Block 27!K15"))
    #expect(bare.tabName == "Block 27")
    #expect(bare.reference == "K15")

    let escapedApostrophe = try #require(splitA1Range("'Coach''s Block'!B2:C3"))
    #expect(escapedApostrophe.tabName == "Coach's Block")
    #expect(escapedApostrophe.reference == "B2:C3")

    let bangInTabName = try #require(splitA1Range("'Week 1!2'!A1"))
    #expect(bangInTabName.tabName == "Week 1!2")
    #expect(bangInTabName.reference == "A1")
}

@Test func rejectsRangesMissingATabNameOrAReference() {
    for range in ["Block 27", "!A1", "Block 27!", "''!A1", "'unterminated!A1", "Coach's Block!A1"] {
        #expect(splitA1Range(range) == nil, "\(range)")
    }
}

@Test func splitsBackTheRangeSingleCellRangeMints() throws {
    let split = try #require(splitA1Range(singleCellRange(tabName: "Kevin's Block", row: 15, col: 10)))

    #expect(split.tabName == "Kevin's Block")
    #expect(try #require(a1CellIndex(split.reference)) == (row: 15, col: 10))
}
