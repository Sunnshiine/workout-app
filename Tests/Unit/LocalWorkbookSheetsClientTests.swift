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

@Test func localWorkbookPreservesSeededRowVisibilityAcrossWrites() async throws {
    let client = LocalWorkbookSheetsClient(
        tabs: [
            "Block 27": SheetSnapshot(
                values: gridFromA1(["A1": "seed"], rows: 2, cols: 2),
                rowVisibility: [
                    0: SheetRowVisibility(hiddenByUser: true),
                    1: SheetRowVisibility(hiddenByFilter: true)
                ]
            )
        ]
    )

    try await client.updateCells(
        spreadsheetId: "sid",
        range: "'Block 27'!B2",
        values: [["changed"]]
    )

    let snapshot = try await client.fetchTabSnapshot(spreadsheetId: "sid", tabName: "Block 27")
    let valuesOnly = try await client.fetchTab(spreadsheetId: "sid", tabName: "Block 27")
    #expect(snapshot.values.cell(row: 1, col: 1) == "changed")
    #expect(snapshot.isRowVisible(0) == false)
    #expect(snapshot.isRowVisible(1) == false)
    #expect(snapshot.isRowVisible(2) == true)
    #expect(valuesOnly.cell(row: 1, col: 1) == "changed")
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

@Test func localWorkbookBatchWriteCommitsEveryUpdateAndRecordsTheBatch() async throws {
    let client = LocalWorkbookSheetsClient(
        tabs: [
            "Block 27": gridFromA1(
                [
                    "A1": "old A",
                    "B1": "old B"
                ],
                rows: 1,
                cols: 2
            )
        ]
    )

    try await client.updateCells(
        spreadsheetId: "sid",
        updates: [
            SheetValueRangeUpdate(range: "'Block 27'!A1", values: [["new A"]]),
            SheetValueRangeUpdate(range: "'Block 27'!B1", values: [["new B"]])
        ]
    )

    let fetched = try await client.fetchTab(spreadsheetId: "sid", tabName: "Block 27")
    let batches = await client.recordedBatches

    #expect(fetched.cell(row: 0, col: 0) == "new A")
    #expect(fetched.cell(row: 0, col: 1) == "new B")
    #expect(batches.count == 1)
    #expect(batches[0].map(\.range) == ["'Block 27'!A1", "'Block 27'!B1"])
}

@Test func localWorkbookEmptyBatchWriteIsNoOpAndUnrecorded() async throws {
    let original = gridFromA1(["A1": "original"], rows: 1, cols: 1)
    let client = LocalWorkbookSheetsClient(tabs: ["Block 27": original])

    try await client.updateCells(spreadsheetId: "sid", updates: [])

    let fetched = try await client.fetchTab(spreadsheetId: "sid", tabName: "Block 27")
    #expect(fetched == original)
    #expect(await client.recordedBatches.isEmpty)
}

@Test func localWorkbookRectangularWritePersistsEveryCell() async throws {
    let client = LocalWorkbookSheetsClient(
        tabs: ["Block 27": gridFromA1([:], rows: 1, cols: 1)]
    )

    try await client.updateCells(
        spreadsheetId: "sid",
        range: "'Block 27'!B2:C3",
        values: [
            ["B2", "C2"],
            ["B3", "C3"]
        ]
    )

    let fetched = try await client.fetchTab(spreadsheetId: "sid", tabName: "Block 27")
    #expect(fetched.cell(row: 1, col: 1) == "B2")
    #expect(fetched.cell(row: 1, col: 2) == "C2")
    #expect(fetched.cell(row: 2, col: 1) == "B3")
    #expect(fetched.cell(row: 2, col: 2) == "C3")
}

@Test func localWorkbookFailedBatchLeavesWorkbookUnchangedAndUnrecorded() async throws {
    let original = gridFromA1(["A1": "original"], rows: 1, cols: 1)
    let client = LocalWorkbookSheetsClient(tabs: ["Block 27": original])

    await #expect(throws: LocalWorkbookSheetsClientError.unknownTab("Missing")) {
        try await client.updateCells(
            spreadsheetId: "sid",
            updates: [
                SheetValueRangeUpdate(range: "'Block 27'!A1", values: [["changed"]]),
                SheetValueRangeUpdate(range: "'Missing'!A1", values: [["should throw"]])
            ]
        )
    }

    let fetched = try await client.fetchTab(spreadsheetId: "sid", tabName: "Block 27")
    let batches = await client.recordedBatches
    #expect(fetched == original)
    #expect(batches.isEmpty)
}

@Test func localWorkbookRejectsValueDimensionsWithoutMutatingWorkbook() async throws {
    let original = gridFromA1(["A1": "original"], rows: 1, cols: 1)
    let client = LocalWorkbookSheetsClient(tabs: ["Block 27": original])

    await #expect(
        throws: LocalWorkbookSheetsClientError.unsupportedValues("Expected every row to contain 2 value(s)")
    ) {
        try await client.updateCells(
            spreadsheetId: "sid",
            range: "'Block 27'!A1:B1",
            values: [["only one value"]]
        )
    }

    let fetched = try await client.fetchTab(spreadsheetId: "sid", tabName: "Block 27")
    let batches = await client.recordedBatches
    #expect(fetched == original)
    #expect(batches.isEmpty)
}

@Test func localWorkbookRejectsMalformedRangeWithoutMutatingWorkbook() async throws {
    let original = gridFromA1(["A1": "original"], rows: 1, cols: 1)
    let client = LocalWorkbookSheetsClient(tabs: ["Block 27": original])

    await #expect(throws: LocalWorkbookSheetsClientError.malformedRange("Block 27")) {
        try await client.updateCells(
            spreadsheetId: "sid",
            range: "Block 27",
            values: [["changed"]]
        )
    }

    let fetched = try await client.fetchTab(spreadsheetId: "sid", tabName: "Block 27")
    #expect(fetched == original)
    #expect(await client.recordedBatches.isEmpty)
}
