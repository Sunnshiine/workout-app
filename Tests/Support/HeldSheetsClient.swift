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

    func updateCells(spreadsheetId: String, range: String, values: [[String]]) async throws {}

    func waitUntilHeld() async {
        await held.waitUntilHeld(orRecord: "the sync never reached the Sheet read this client holds")
    }

    func release() {
        held.release()
    }
}

func replacementSquatGrid() -> SheetGrid {
    gridFromA1(
        [
            "C12": "Day 1", "S12": "Day 2", "AI12": "Day 3", "AX12": "Day 4",
            "D14": "Sets", "F14": "Reps", "H14": "Load", "K14": "Notes",
            "C15": "Replacement Squat", "D15": "1", "F15": "5", "H15": "RPE8"
        ],
        rows: 20,
        cols: 60
    )
}
