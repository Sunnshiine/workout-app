import Testing

@testable import WorkoutTracker

@MainActor
final class HeldSheetsClient: SheetsClient {
    private(set) var tabTitleReads = 0
    private var tabSnapshotReads = 0
    private let titles: [String]
    private let grid: SheetGrid
    private let holdsTabSnapshot: Bool
    private let held: HeldCall

    init(titles: [String], grid: SheetGrid, holdsTabSnapshot: Bool = false) {
        self.titles = titles
        self.grid = grid
        self.holdsTabSnapshot = holdsTabSnapshot
        held = HeldCall(parks: holdsTabSnapshot ? 2 : 1)
    }

    func listTabTitles(spreadsheetId: String) async throws -> [String] {
        tabTitleReads += 1
        if tabTitleReads == 1 { await held.hold() }
        return titles
    }

    func listSpreadsheets(pageToken: String?) async throws -> SpreadsheetListPage {
        SpreadsheetListPage(spreadsheets: [], nextPageToken: nil)
    }

    func fetchTabSnapshot(spreadsheetId: String, tabName: String) async throws -> SheetSnapshot {
        tabSnapshotReads += 1
        if holdsTabSnapshot, tabSnapshotReads == 1 { await held.hold() }
        return SheetSnapshot(values: grid)
    }

    func write(_ cells: [SheetCellWrite], spreadsheetId: String) async throws {}

    func waitUntilHeld() async {
        await held.waitUntilHeld(orRecord: "the sync never reached the Sheet read this client holds")
    }

    func release() {
        held.release()
    }
}
