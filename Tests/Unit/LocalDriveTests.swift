import Foundation
import Testing

@testable import WorkoutTracker

private func workbook(_ id: String, title: String, marker: String) -> LocalWorkbook {
    LocalWorkbook(spreadsheetId: id, title: title, tabs: ["Block 1": LocalWorkbook.Tab(cells: ["A1": marker])])
}

private let drive = LocalDrive([workbook("one", title: "First", marker: "1"), workbook("two", title: "Second", marker: "2")])

@Test func aDriveListsEveryWorkbookInOrderAndRoutesEachCallByItsId() async throws {
    let page = try await drive.listSpreadsheets(pageToken: nil)
    #expect(page.spreadsheets.map(\.name) == ["First", "Second"])
    #expect(page.nextPageToken == nil)

    #expect(try await drive.fetchTab(spreadsheetId: "one", tabName: "Block 1").cell(row: 0, col: 0) == "1")
    #expect(try await drive.fetchTab(spreadsheetId: "two", tabName: "Block 1").cell(row: 0, col: 0) == "2")
}

@Test func aWriteLandsInTheWorkbookItNamesOnly() async throws {
    let drive = LocalDrive([workbook("one", title: "First", marker: "1"), workbook("two", title: "Second", marker: "2")])

    try await drive.updateCells(spreadsheetId: "two", range: "'Block 1'!A1", values: [["written"]])

    #expect(try await drive.fetchTab(spreadsheetId: "one", tabName: "Block 1").cell(row: 0, col: 0) == "1")
    #expect(try await drive.fetchTab(spreadsheetId: "two", tabName: "Block 1").cell(row: 0, col: 0) == "written")
}

@Test func aSpreadsheetTheDriveDoesNotHoldAnswers404() async {
    await #expect(throws: SheetsError.http(404)) {
        try await drive.listTabTitles(spreadsheetId: "three")
    }
}

@Test func aDisconnectedSpreadsheetFailsEveryReadAndWriteAndLeavesTheOthersReachable() async throws {
    let drive = LocalDrive([workbook("one", title: "First", marker: "1"), workbook("two", title: "Second", marker: "2")])

    await drive.disconnect("one")

    await #expect(throws: URLError.self) { try await drive.listTabTitles(spreadsheetId: "one") }
    await #expect(throws: URLError.self) { try await drive.fetchTabSnapshot(spreadsheetId: "one", tabName: "Block 1") }
    await #expect(throws: URLError.self) {
        try await drive.updateCells(spreadsheetId: "one", range: "'Block 1'!A1", values: [["x"]])
    }
    #expect(try await drive.listTabTitles(spreadsheetId: "two") == ["Block 1"])
}

@Test func aHeldDriveWaitsBeforeEveryLaterTabList() async throws {
    let drive = LocalDrive([workbook("one", title: "First", marker: "1")])
    let clock = ContinuousClock()

    await drive.holdTabListings(for: .milliseconds(200))
    let elapsed = try await clock.measure {
        _ = try await drive.listTabTitles(spreadsheetId: "one")
    }

    #expect(elapsed >= .milliseconds(200))
}
