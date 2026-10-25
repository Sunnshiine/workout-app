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

    try await drive.write([SheetCellWrite(tabName: "Block 1", a1: "A1", value: "written")], spreadsheetId: "two")

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
        try await drive.write([SheetCellWrite(tabName: "Block 1", a1: "A1", value: "x")], spreadsheetId: "one")
    }
    #expect(try await drive.listTabTitles(spreadsheetId: "two") == ["Block 1"])
}

@Test func aHeldDriveWaitsBeforeEveryLaterTabList() async throws {
    let drive = LocalDrive([workbook("one", title: "First", marker: "1")])
    // The hold is a real sleep, and the test asserts only its floor, which load cannot break.
    // swiftlint:disable:next tests_wait_on_events_not_clocks
    let clock = ContinuousClock()

    await drive.holdTabListings(for: .milliseconds(200))
    // swiftlint:disable:next tests_wait_on_events_not_clocks
    let elapsed = try await clock.measure {
        _ = try await drive.listTabTitles(spreadsheetId: "one")
    }

    #expect(elapsed >= .milliseconds(200))
}
