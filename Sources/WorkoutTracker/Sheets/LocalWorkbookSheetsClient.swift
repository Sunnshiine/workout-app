#if OFFLINE_SHEET
    import Foundation

    /// An offline spreadsheet: the file the CLI keeps on disk and an agent can author by hand.
    ///
    /// Each tab is a sparse A1 map (`"K15": "185x5@8"`). `rows` and `cols` size the grid the parser
    /// sees and grow to fit any cell outside them; `hiddenRows` is keyed by the 1-based Sheet row
    /// number, the same numbering the A1 keys use.
    public struct LocalWorkbook: Codable, Equatable, Sendable {
        public struct Tab: Equatable, Sendable {
            public var rows: Int
            public var cols: Int
            public var cells: [String: String]
            public var hiddenRows: [Int: SheetRowVisibility]

            public init(rows: Int = 0, cols: Int = 0, cells: [String: String], hiddenRows: [Int: SheetRowVisibility] = [:]) {
                self.rows = rows
                self.cols = cols
                self.cells = cells
                self.hiddenRows = hiddenRows
            }
        }

        public var spreadsheetId: String
        public var title: String
        public var tabs: [String: Tab]

        public init(spreadsheetId: String, title: String, tabs: [String: Tab]) {
            self.spreadsheetId = spreadsheetId
            self.title = title
            self.tabs = tabs
        }

        public static func load(from url: URL) throws -> LocalWorkbook {
            try JSONDecoder().decode(LocalWorkbook.self, from: Data(contentsOf: url))
        }

        /// Writes the workbook atomically so a crash mid-write never leaves a torn file behind.
        public func write(to url: URL) throws {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
            try encoder.encode(self).write(to: url, options: .atomic)
        }
    }

    /// The A1 cell a `cells` key names, or nil when the key is not one.
    ///
    /// Case is folded, so a hand-authored `k15` and `K15` name the same cell.
    private func a1CellKey(_ key: String) -> String? {
        let reference = key.uppercased()
        return isA1CellReference(reference) ? reference : nil
    }

    /// The 1-based Sheet row a `hiddenRows` key names, or nil when the key is not one.
    private func sheetRowNumber(_ key: String) -> Int? {
        guard let row = Int(key), row >= 1 else { return nil }
        return row
    }

    extension KeyedDecodingContainer {
        /// Decodes a workbook section whose keys spell a Sheet location, rejecting the file when one does not.
        ///
        /// The workbook is hand-authorable, so an absent section is an empty table. Two keys naming
        /// one location collapse and the last wins, because folding case and parsing numbers both
        /// let distinct spellings land on the same location.
        func decodeTable<Location: Hashable, Value: Decodable>(
            forKey key: Key,
            locatedBy location: (String) -> Location?,
            keysAre expectation: String
        ) throws -> [Location: Value] {
            var table: [Location: Value] = [:]
            for (rawKey, value) in try decodeIfPresent([String: Value].self, forKey: key) ?? [:] {
                guard let location = location(rawKey) else {
                    throw DecodingError.dataCorruptedError(
                        forKey: key,
                        in: self,
                        debugDescription: "\(expectation); got \"\(rawKey)\""
                    )
                }
                table[location] = value
            }
            return table
        }
    }

    extension LocalWorkbook.Tab: Codable {
        private enum CodingKeys: String, CodingKey {
            case rows, cols, cells, hiddenRows
        }

        public init(from decoder: any Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            rows = try container.decodeIfPresent(Int.self, forKey: .rows) ?? 0
            cols = try container.decodeIfPresent(Int.self, forKey: .cols) ?? 0
            cells = try container.decodeTable(
                forKey: .cells,
                locatedBy: a1CellKey,
                keysAre: "cells keys are A1 references such as K15"
            )
            hiddenRows = try container.decodeTable(
                forKey: .hiddenRows,
                locatedBy: sheetRowNumber,
                keysAre: "hiddenRows keys are 1-based row numbers"
            )
        }

        // `[Int: SheetRowVisibility]` would encode as a flat array; keying by the row number as a string keeps
        // the file an object an agent can read and edit.
        public func encode(to encoder: any Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(rows, forKey: .rows)
            try container.encode(cols, forKey: .cols)
            try container.encode(cells, forKey: .cells)
            try container.encode(
                Dictionary(uniqueKeysWithValues: hiddenRows.map { (String($0.key), $0.value) }),
                forKey: .hiddenRows
            )
        }
    }

    extension LocalWorkbook.Tab {
        init(snapshot: SheetSnapshot) {
            self.init(
                rows: snapshot.values.count,
                cols: snapshot.values.map(\.count).max() ?? 0,
                cells: snapshot.sparseCells,
                hiddenRows: snapshot.hiddenRowsByNumber
            )
        }

        var snapshot: SheetSnapshot {
            var rowCount = rows
            var colCount = cols
            for a1 in cells.keys {
                guard let index = a1CellIndex(a1) else { continue }
                rowCount = max(rowCount, index.row + 1)
                colCount = max(colCount, index.col + 1)
            }
            return SheetSnapshot(
                values: gridFromA1(cells, rows: rowCount, cols: colCount),
                rowVisibility: Dictionary(uniqueKeysWithValues: hiddenRows.map { ($0.key - 1, $0.value) })
            )
        }
    }

    extension LocalWorkbook {
        init(spreadsheetId: String, title: String, snapshots: [String: SheetSnapshot]) {
            self.init(spreadsheetId: spreadsheetId, title: title, tabs: snapshots.mapValues(Tab.init(snapshot:)))
        }

        var snapshots: [String: SheetSnapshot] {
            tabs.mapValues(\.snapshot)
        }
    }

    enum LocalWorkbookSheetsClientError: Error, Equatable, Sendable, CustomStringConvertible {
        case unknownTab(String)
        case writeFailed(Int)

        var description: String {
            switch self {
            case .unknownTab(let tab):
                "Unknown tab: \(tab)"
            case .writeFailed(let requestNumber):
                "Write request \(requestNumber) failed"
            }
        }
    }

    actor LocalWorkbookSheetsClient: SheetsClient {
        private enum Storage {
            case memory([String: SheetSnapshot])
            /// The file is the only copy, read on every call, so an edit to it between two calls is
            /// a coach edit the next call reads, and a write lands on top of it.
            case file(URL)

            func tabs() throws -> [String: SheetSnapshot] {
                switch self {
                case .memory(let tabs): tabs
                case .file(let url): try LocalWorkbook.load(from: url).snapshots
                }
            }

            mutating func store(_ tabs: [String: SheetSnapshot], spreadsheetId: String, title: String) throws {
                switch self {
                case .memory: self = .memory(tabs)
                case .file(let url): try LocalWorkbook(spreadsheetId: spreadsheetId, title: title, snapshots: tabs).write(to: url)
                }
            }
        }

        private let spreadsheetId: String
        private let title: String
        private var storage: Storage
        private let failedUpdateRequestNumbers: Set<Int>
        private var updateRequestCount = 0
        private(set) var recordedBatches: [[SheetCellWrite]] = []

        init(workbook: LocalWorkbook, failedUpdateRequestNumbers: Set<Int> = []) {
            self.spreadsheetId = workbook.spreadsheetId
            self.title = workbook.title
            self.storage = .memory(workbook.snapshots)
            self.failedUpdateRequestNumbers = failedUpdateRequestNumbers
        }

        init(file: URL) throws {
            let workbook = try LocalWorkbook.load(from: file)
            self.spreadsheetId = workbook.spreadsheetId
            self.title = workbook.title
            self.storage = .file(file)
            self.failedUpdateRequestNumbers = []
        }

        init(
            spreadsheetId: String = "sid",
            tabs: [String: SheetGrid],
            failedUpdateRequestNumbers: Set<Int> = []
        ) {
            self.init(
                spreadsheetId: spreadsheetId,
                tabs: tabs.mapValues { SheetSnapshot(values: $0) },
                failedUpdateRequestNumbers: failedUpdateRequestNumbers
            )
        }

        init(
            spreadsheetId: String = "sid",
            tabs: [String: SheetSnapshot],
            failedUpdateRequestNumbers: Set<Int> = []
        ) {
            self.spreadsheetId = spreadsheetId
            self.title = "Local Workbook"
            self.storage = .memory(tabs)
            self.failedUpdateRequestNumbers = failedUpdateRequestNumbers
        }

        func listTabTitles(spreadsheetId: String) async throws -> [String] {
            try storage.tabs().keys.sorted()
        }

        func listSpreadsheets(pageToken: String?) async throws -> SpreadsheetListPage {
            SpreadsheetListPage(
                spreadsheets: [SpreadsheetFile(name: title, spreadsheetId: spreadsheetId, modifiedDate: .distantPast)],
                nextPageToken: nil
            )
        }

        func fetchTabSnapshot(spreadsheetId: String, tabName: String) async throws -> SheetSnapshot {
            guard let snapshot = try storage.tabs()[tabName] else {
                throw LocalWorkbookSheetsClientError.unknownTab(tabName)
            }
            return snapshot
        }

        func write(_ cells: [SheetCellWrite], spreadsheetId: String) async throws {
            guard !cells.isEmpty else { return }
            updateRequestCount += 1
            if failedUpdateRequestNumbers.contains(updateRequestCount) {
                throw LocalWorkbookSheetsClientError.writeFailed(updateRequestCount)
            }
            let staged = try Self.applying(cells, to: storage.tabs())
            try storage.store(staged, spreadsheetId: self.spreadsheetId, title: title)
            recordedBatches.append(cells)
        }
    }

    extension LocalWorkbookSheetsClient {
        /// The workbook with every cell written, or the first unknown tab's error and no cell
        /// written, so a batch lands whole or not at all (ADR-0006).
        fileprivate static func applying(
            _ cells: [SheetCellWrite],
            to workbook: [String: SheetSnapshot]
        ) throws -> [String: SheetSnapshot] {
            var staged = workbook
            for cell in cells {
                guard let snapshot = staged[cell.tabName] else {
                    throw LocalWorkbookSheetsClientError.unknownTab(cell.tabName)
                }
                var values = snapshot.values
                values.write([[cell.value]], atRow: cell.row, col: cell.col)
                staged[cell.tabName] = SheetSnapshot(values: values, rowVisibility: snapshot.rowVisibility)
            }
            return staged
        }
    }

#endif
