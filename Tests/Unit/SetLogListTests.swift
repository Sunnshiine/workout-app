import Testing

@testable import WorkoutTracker

@Test func setLogListCollapsesLoneEmptyCellToEmptyList() {
    #expect(SetLogList(cell: "").tokens == [])
    #expect(SetLogList(cell: "   ").tokens == [])
}

@Test func setLogListSplitsCommaSeparatedTokens() {
    #expect(SetLogList(cell: "185x5@8, skip, ").tokens == ["185x5@8", "skip", ""])
}

@Test func setLogListReadsTokenAtPosition() {
    let list = SetLogList(cell: "185x5@8, 195x5@9")

    #expect(list.token(at: 0) == "185x5@8")
    #expect(list.token(at: 1) == "195x5@9")
}

@Test func setLogListReadsEmptyPastEndOfList() {
    let list = SetLogList(cell: "185x5@8")

    #expect(list.token(at: 1) == "")
    #expect(SetLogList(cell: "").token(at: 0) == "")
}

@Test func setLogListWritePadsUpToPosition() {
    var list = SetLogList(cell: "")
    list.setToken("205x5@9", at: 2)

    #expect(list.tokens == ["", "", "205x5@9"])
}

@Test func setLogListWriteOverwritesInPlace() {
    var list = SetLogList(cell: "185x5@8, 195x5@9, skip")
    list.setToken("200x5@9", at: 1)

    #expect(list.tokens == ["185x5@8", "200x5@9", "skip"])
}

@Test func setLogListJoinsTrimmingTrailingEmpties() {
    var list = SetLogList(cell: "185x5@8, 195x5@9")
    list.setToken("", at: 1)

    #expect(list.cellValue == "185x5@8")
}

@Test func setLogListWriteThenReadRoundTrips() {
    var list = SetLogList(cell: "185x5@8")
    list.setToken("skip", at: 1)

    #expect(list.cellValue == "185x5@8, skip")
    #expect(SetLogList(cell: list.cellValue).token(at: 1) == "skip")
}
