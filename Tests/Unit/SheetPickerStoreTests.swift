import Foundation
import Testing

@testable import WorkoutTracker

@MainActor
@Test func sheetPickerLoadsRecentSpreadsheets() async throws {
    let client = StubPickerClient(
        pages: [
            SpreadsheetListPage(
                spreadsheets: [
                    SpreadsheetFile(
                        name: "Training Log",
                        spreadsheetId: "sheet-1",
                        modifiedDate: Date(timeIntervalSince1970: 1_779_840_000)
                    )
                ],
                nextPageToken: "older"
            )
        ]
    )
    let settings = SettingsStore(defaults: try makeDefaults())
    let store = SheetPickerStore(client: client, settings: settings)

    await store.loadInitial()

    #expect(store.spreadsheets.map(\.name) == ["Training Log"])
    #expect(store.canLoadMore == true)
    #expect(store.listErrorMessage == nil)
}

@MainActor
@Test func sheetPickerLoadMoreAppendsNextPage() async throws {
    let currentPage = SpreadsheetListPage(
        spreadsheets: [
            SpreadsheetFile(name: "Current", spreadsheetId: "sheet-1", modifiedDate: .distantPast)
        ],
        nextPageToken: "older"
    )
    let olderPage = SpreadsheetListPage(
        spreadsheets: [
            SpreadsheetFile(name: "Older", spreadsheetId: "sheet-2", modifiedDate: .distantPast)
        ],
        nextPageToken: nil
    )
    let client = StubPickerClient(pages: [currentPage, olderPage])
    let settings = SettingsStore(defaults: try makeDefaults())
    let store = SheetPickerStore(client: client, settings: settings)

    await store.loadInitial()
    await store.loadMore()

    #expect(store.spreadsheets.map(\.name) == ["Current", "Older"])
    #expect(client.requestedPageTokens.count == 2)
    #expect(client.requestedPageTokens[1] == "older")
    #expect(store.canLoadMore == false)
}

@MainActor
@Test func sheetPickerCommitsSelectionWhenSheetHasBlockTab() async throws {
    let file = SpreadsheetFile(name: "Training Log", spreadsheetId: "sheet-1", modifiedDate: .distantPast)
    let client = StubPickerClient(pages: [], tabTitles: ["Overview", "Block - 27"])
    let settings = SettingsStore(defaults: try makeDefaults())
    let store = SheetPickerStore(client: client, settings: settings)

    await store.select(file).value

    #expect(client.validatedSpreadsheetIds == ["sheet-1"])
    #expect(settings.spreadsheetId == "sheet-1")
    #expect(settings.spreadsheetTitle == "Training Log")
    #expect(store.rowError(for: file) == nil)
}

@MainActor
@Test func sheetPickerRunsCustomSelectionAfterBlockTabValidation() async throws {
    let file = SpreadsheetFile(name: "Training Log", spreadsheetId: "sheet-1", modifiedDate: .distantPast)
    let client = StubPickerClient(pages: [], tabTitles: ["Overview", "Block - 27"])
    let settings = SettingsStore(defaults: try makeDefaults())
    var selected: [SpreadsheetFile] = []
    let store = SheetPickerStore(client: client, settings: settings) { spreadsheet in
        selected.append(spreadsheet)
    }

    await store.select(file).value

    #expect(client.validatedSpreadsheetIds == ["sheet-1"])
    #expect(selected == [file])
    #expect(settings.spreadsheetId == nil)
    #expect(settings.spreadsheetTitle == nil)
    #expect(store.rowError(for: file) == nil)
}

@MainActor
@Test func sheetPickerDoesNotRunCustomSelectionAfterCancellation() async throws {
    let file = SpreadsheetFile(name: "Training Log", spreadsheetId: "sheet-1", modifiedDate: .distantPast)
    let client = ControlledValidationClient()
    let settings = SettingsStore(defaults: try makeDefaults())
    var selected: [SpreadsheetFile] = []
    let store = SheetPickerStore(client: client, settings: settings) { spreadsheet in
        selected.append(spreadsheet)
    }

    let task = store.select(file)
    await client.waitForRequest(spreadsheetId: "sheet-1")
    store.cancelSelection()
    await client.complete(spreadsheetId: "sheet-1", titles: ["Block 27"])
    await task.value

    #expect(selected.isEmpty)
    #expect(settings.spreadsheetId == nil)
    #expect(settings.spreadsheetTitle == nil)
}

@MainActor
@Test func sheetPickerShowsInlineErrorWhenSheetHasNoBlockTabs() async throws {
    let file = SpreadsheetFile(name: "Budget", spreadsheetId: "sheet-1", modifiedDate: .distantPast)
    let client = StubPickerClient(pages: [], tabTitles: ["Overview", "RPE Chart"])
    let settings = SettingsStore(defaults: try makeDefaults())
    let store = SheetPickerStore(client: client, settings: settings)

    await store.select(file).value

    #expect(settings.spreadsheetId == nil)
    #expect(store.rowError(for: file) == "No training blocks found in this sheet")
}

@MainActor
@Test func sheetPickerReportsDriveListFailure() async throws {
    let client = StubPickerClient(pages: [], listError: SheetsError.http(403))
    let settings = SettingsStore(defaults: try makeDefaults())
    let store = SheetPickerStore(client: client, settings: settings)

    await store.loadInitial()

    #expect(store.spreadsheets.isEmpty)
    #expect(store.listErrorMessage == "Couldn't load sheets")
    #expect(store.isLoadingList == false)
}

@MainActor
@Test func sheetPickerShowsRowErrorWhenValidationRequestFails() async throws {
    let file = SpreadsheetFile(name: "Training Log", spreadsheetId: "sheet-1", modifiedDate: .distantPast)
    let client = StubPickerClient(pages: [], tabError: SheetsError.http(404))
    let settings = SettingsStore(defaults: try makeDefaults())
    let store = SheetPickerStore(client: client, settings: settings)

    await store.select(file).value

    #expect(settings.spreadsheetId == nil)
    #expect(store.rowError(for: file) == "Couldn't validate this sheet")
}

@MainActor
@Test func sheetPickerKeepsLatestSelectionWhenEarlierValidationFinishesLast() async throws {
    let first = SpreadsheetFile(name: "First Sheet", spreadsheetId: "sheet-1", modifiedDate: .distantPast)
    let second = SpreadsheetFile(name: "Second Sheet", spreadsheetId: "sheet-2", modifiedDate: .distantPast)
    let client = ControlledValidationClient()
    let settings = SettingsStore(defaults: try makeDefaults())
    let store = SheetPickerStore(client: client, settings: settings)

    let firstTask = store.select(first)
    #expect(store.validatingSpreadsheetId == "sheet-1")
    let secondTask = store.select(second)
    #expect(store.validatingSpreadsheetId == "sheet-2")
    await client.waitForRequest(spreadsheetId: "sheet-2")

    await client.complete(spreadsheetId: "sheet-2", titles: ["Block 27"])
    await secondTask.value
    #expect(settings.spreadsheetId == "sheet-2")
    #expect(settings.spreadsheetTitle == "Second Sheet")

    await client.waitForRequest(spreadsheetId: "sheet-1")
    await client.complete(spreadsheetId: "sheet-1", titles: ["Block 26"])
    await firstTask.value
    #expect(settings.spreadsheetId == "sheet-2")
    #expect(settings.spreadsheetTitle == "Second Sheet")
}

@MainActor
@Test func sheetPickerDoesNotCommitSelectionCancelledForURLFallback() async throws {
    let file = SpreadsheetFile(name: "Training Log", spreadsheetId: "sheet-1", modifiedDate: .distantPast)
    let client = ControlledValidationClient()
    let settings = SettingsStore(defaults: try makeDefaults())
    let store = SheetPickerStore(client: client, settings: settings)

    let task = store.select(file)
    #expect(store.validatingSpreadsheetId == "sheet-1")
    store.cancelSelection()
    #expect(store.validatingSpreadsheetId == nil)
    settings.setSheetURL("https://docs.google.com/spreadsheets/d/pasted-sheet/edit")

    await client.waitForRequest(spreadsheetId: "sheet-1")
    await client.complete(spreadsheetId: "sheet-1", titles: ["Block 27"])
    await task.value

    #expect(settings.spreadsheetId == "pasted-sheet")
    #expect(settings.spreadsheetTitle == nil)
}

private func makeDefaults() throws -> UserDefaults {
    try #require(UserDefaults(suiteName: "test.\(UUID())"))
}

private final class StubPickerClient: SheetsClient, @unchecked Sendable {
    private let pages: [SpreadsheetListPage]
    private let tabTitles: [String]
    private let listError: Error?
    private let tabError: Error?
    private(set) var requestedPageTokens: [String?] = []
    private(set) var validatedSpreadsheetIds: [String] = []

    init(pages: [SpreadsheetListPage], tabTitles: [String] = [], listError: Error? = nil, tabError: Error? = nil) {
        self.pages = pages
        self.tabTitles = tabTitles
        self.listError = listError
        self.tabError = tabError
    }

    func listTabTitles(spreadsheetId: String) async throws -> [String] {
        if let tabError {
            throw tabError
        }
        validatedSpreadsheetIds.append(spreadsheetId)
        return tabTitles
    }

    func listSpreadsheets(pageToken: String?) async throws -> SpreadsheetListPage {
        if let listError {
            throw listError
        }
        requestedPageTokens.append(pageToken)
        return pages[requestedPageTokens.count - 1]
    }

    func fetchTab(spreadsheetId: String, tabName: String) async throws -> SheetGrid {
        []
    }

    func updateCells(spreadsheetId: String, range: String, values: [[String]]) async throws {}
}

private final class ControlledValidationClient: SheetsClient, @unchecked Sendable {
    private let coordinator = ControlledValidationCoordinator()

    func listTabTitles(spreadsheetId: String) async throws -> [String] {
        try await coordinator.listTabTitles(spreadsheetId: spreadsheetId)
    }

    func listSpreadsheets(pageToken: String?) async throws -> SpreadsheetListPage {
        SpreadsheetListPage(spreadsheets: [], nextPageToken: nil)
    }

    func fetchTab(spreadsheetId: String, tabName: String) async throws -> SheetGrid {
        []
    }

    func updateCells(spreadsheetId: String, range: String, values: [[String]]) async throws {}

    func waitForRequest(spreadsheetId: String) async {
        await coordinator.waitForRequest(spreadsheetId: spreadsheetId)
    }

    func complete(spreadsheetId: String, titles: [String]) async {
        await coordinator.complete(spreadsheetId: spreadsheetId, titles: titles)
    }
}

private actor ControlledValidationCoordinator {
    private var continuations: [String: CheckedContinuation<[String], Error>] = [:]

    func listTabTitles(spreadsheetId: String) async throws -> [String] {
        try await withCheckedThrowingContinuation { continuation in
            continuations[spreadsheetId] = continuation
        }
    }

    func waitForRequest(spreadsheetId: String) async {
        while continuations[spreadsheetId] == nil {
            await Task.yield()
        }
    }

    func complete(spreadsheetId: String, titles: [String]) {
        continuations.removeValue(forKey: spreadsheetId)?.resume(returning: titles)
    }
}
