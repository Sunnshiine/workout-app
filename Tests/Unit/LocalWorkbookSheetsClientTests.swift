import Testing

@testable import WorkoutTracker

@Test func localWorkbookListsAndFetchesSeededTabs() async throws {
    let block27 = gridFromA1(["A1": "Block 27 marker"], rows: 2, cols: 2)
    let block26 = gridFromA1(["B2": "Block 26 marker"], rows: 3, cols: 3)
    let client = LocalWorkbookSheetsClient(
        tabs: [
            "Block 27": block27,
            "Block 26": block26
        ]
    )

    let titles = try await client.listTabTitles(spreadsheetId: "sid")
    let fetched = try await client.fetchTab(spreadsheetId: "sid", tabName: "Block 27")

    #expect(titles == ["Block 26", "Block 27"])
    #expect(fetched == block27)
}

@Test func localWorkbookSingleCellWritePersistsForLaterFetchAndGrowsGrid() async throws {
    let client = LocalWorkbookSheetsClient(
        tabs: ["Block 27": gridFromA1(["A1": "seed"], rows: 1, cols: 1)]
    )

    try await client.updateCells(
        spreadsheetId: "sid",
        range: "'Block 27'!C3",
        values: [["grown"]]
    )

    let fetched = try await client.fetchTab(spreadsheetId: "sid", tabName: "Block 27")
    #expect(fetched.cell(row: 0, col: 0) == "seed")
    #expect(fetched.cell(row: 2, col: 2) == "grown")
}

@Test func localWorkbookBlankWritePersistsEmptyString() async throws {
    let client = LocalWorkbookSheetsClient(
        tabs: ["Block 27": gridFromA1(["K15": "185x5@8"], rows: 20, cols: 12)]
    )

    try await client.updateCells(
        spreadsheetId: "sid",
        range: "'Block 27'!K15",
        values: [[""]]
    )

    let fetched = try await client.fetchTab(spreadsheetId: "sid", tabName: "Block 27")
    #expect(fetched.cell(row: 14, col: 10) == "")
}

@Test func localWorkbookParsesQuotedTabNameWithEscapedApostrophe() async throws {
    let client = LocalWorkbookSheetsClient(
        tabs: ["Coach's Block": gridFromA1([:], rows: 1, cols: 1)]
    )

    try await client.updateCells(
        spreadsheetId: "sid",
        range: "'Coach''s Block'!B2",
        values: [["quoted"]]
    )

    let fetched = try await client.fetchTab(spreadsheetId: "sid", tabName: "Coach's Block")
    #expect(fetched.cell(row: 1, col: 1) == "quoted")
}
