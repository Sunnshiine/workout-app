#if OFFLINE_SHEET
    import Foundation

    /// Several local workbooks behind one Sheets client, the way one Google account holds several
    /// spreadsheets: every call goes to the workbook its spreadsheet id names, and the sheet picker
    /// lists them all.
    ///
    /// Two faults stand in for the network a phone loses, each armed by a call so a caller can let a
    /// first sync through before it bites. `disconnect(_:)` makes every later read and write of one
    /// spreadsheet fail as a dropped connection does, which `SyncCoordinator` reports as Offline and
    /// which leaves a log queued. `holdTabListings(for:)` makes every later tab list wait first, so a
    /// sync stays in flight, and counts each listing it held in `heldTabListings`. The UI fixture
    /// arms both after its boot sync (`UITestFixture.boot`).
    actor LocalDrive: SheetsClient {
        private let workbooks: [String: LocalWorkbookSheetsClient]
        private let files: [SpreadsheetFile]
        private var disconnected: Set<String> = []
        private var tabListingHold: Duration?
        private(set) var heldTabListings = 0

        /// The picker lists `workbooks` in this order. Every file reads as last modified on the
        /// reference date, a fixed instant like the fixture's other dates.
        init(_ workbooks: [LocalWorkbook]) {
            self.workbooks = Dictionary(
                workbooks.map { ($0.spreadsheetId, LocalWorkbookSheetsClient(workbook: $0)) },
                uniquingKeysWith: { _, second in second }
            )
            files = workbooks.map {
                SpreadsheetFile(name: $0.title, spreadsheetId: $0.spreadsheetId, modifiedDate: Date(timeIntervalSinceReferenceDate: 0))
            }
        }

        func disconnect(_ spreadsheetId: String) {
            disconnected.insert(spreadsheetId)
        }

        func holdTabListings(for duration: Duration) {
            tabListingHold = duration
        }

        func listTabTitles(spreadsheetId: String) async throws -> [String] {
            if let tabListingHold {
                heldTabListings += 1
                try await Task.sleep(for: tabListingHold)
            }
            return try await workbook(spreadsheetId).listTabTitles(spreadsheetId: spreadsheetId)
        }

        func listSpreadsheets(pageToken: String?) async throws -> SpreadsheetListPage {
            SpreadsheetListPage(spreadsheets: files, nextPageToken: nil)
        }

        func fetchTabSnapshot(spreadsheetId: String, tabName: String) async throws -> SheetSnapshot {
            try await workbook(spreadsheetId).fetchTabSnapshot(spreadsheetId: spreadsheetId, tabName: tabName)
        }

        func write(_ cells: [SheetCellWrite], spreadsheetId: String) async throws {
            try await workbook(spreadsheetId).write(cells, spreadsheetId: spreadsheetId)
        }

        /// Google answers 404 for a spreadsheet the account cannot see.
        private func workbook(_ spreadsheetId: String) throws -> LocalWorkbookSheetsClient {
            guard !disconnected.contains(spreadsheetId) else {
                throw URLError(.notConnectedToInternet)
            }
            guard let workbook = workbooks[spreadsheetId] else {
                throw SheetsError.http(404)
            }
            return workbook
        }
    }
#endif
