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

    extension LocalWorkbook.Tab: Codable {
        private enum CodingKeys: String, CodingKey {
            case rows, cols, cells, hiddenRows
        }

        public init(from decoder: any Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            rows = try container.decodeIfPresent(Int.self, forKey: .rows) ?? 0
            cols = try container.decodeIfPresent(Int.self, forKey: .cols) ?? 0
            let rawCells = try container.decodeIfPresent([String: String].self, forKey: .cells) ?? [:]
            cells = try Dictionary(
                rawCells.map { key, value in
                    let reference = key.uppercased()
                    guard isA1CellReference(reference) else {
                        throw DecodingError.dataCorruptedError(
                            forKey: .cells,
                            in: container,
                            debugDescription: "cells keys are A1 references such as K15; got \"\(key)\""
                        )
                    }
                    return (reference, value)
                },
                uniquingKeysWith: { _, last in last }
            )
            let hidden = try container.decodeIfPresent([String: SheetRowVisibility].self, forKey: .hiddenRows) ?? [:]
            hiddenRows = try Dictionary(
                uniqueKeysWithValues: hidden.map { key, value in
                    guard let row = Int(key), row >= 1 else {
                        throw DecodingError.dataCorruptedError(
                            forKey: .hiddenRows,
                            in: container,
                            debugDescription: "hiddenRows keys are 1-based row numbers; got \"\(key)\""
                        )
                    }
                    return (row, value)
                }
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
        case malformedRange(String)
        case unsupportedValues(String)

        var description: String {
            switch self {
            case .unknownTab(let tab):
                "Unknown tab: \(tab)"
            case .writeFailed(let requestNumber):
                "Write request \(requestNumber) failed"
            case .malformedRange(let range):
                "Malformed A1 range: \(range)"
            case .unsupportedValues(let details):
                "Unsupported values: \(details)"
            }
        }
    }

    actor LocalWorkbookSheetsClient: SheetsClient {
        private let spreadsheetId: String
        private let title: String
        private var tabs: [String: SheetSnapshot]
        private let persistTo: URL?
        private let failedUpdateRequestNumbers: Set<Int>
        private var updateRequestCount = 0
        private(set) var recordedBatches: [[SheetValueRangeUpdate]] = []

        init(workbook: LocalWorkbook, persistTo: URL? = nil, failedUpdateRequestNumbers: Set<Int> = []) {
            self.spreadsheetId = workbook.spreadsheetId
            self.title = workbook.title
            self.tabs = workbook.snapshots
            self.persistTo = persistTo
            self.failedUpdateRequestNumbers = failedUpdateRequestNumbers
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
            self.tabs = tabs
            self.persistTo = nil
            self.failedUpdateRequestNumbers = failedUpdateRequestNumbers
        }

        var workbook: LocalWorkbook {
            LocalWorkbook(spreadsheetId: spreadsheetId, title: title, snapshots: tabs)
        }

        func listTabTitles(spreadsheetId: String) async throws -> [String] {
            tabs.keys.sorted()
        }

        func listSpreadsheets(pageToken: String?) async throws -> SpreadsheetListPage {
            SpreadsheetListPage(
                spreadsheets: [SpreadsheetFile(name: title, spreadsheetId: spreadsheetId, modifiedDate: .distantPast)],
                nextPageToken: nil
            )
        }

        func fetchTabSnapshot(spreadsheetId: String, tabName: String) async throws -> SheetSnapshot {
            guard let snapshot = tabs[tabName] else {
                throw LocalWorkbookSheetsClientError.unknownTab(tabName)
            }
            return snapshot
        }

        func updateCells(spreadsheetId: String, range: String, values: [[String]]) async throws {
            try await updateCells(
                spreadsheetId: spreadsheetId,
                updates: [SheetValueRangeUpdate(range: range, values: values)]
            )
        }

        func updateCells(spreadsheetId: String, updates: [SheetValueRangeUpdate]) async throws {
            guard !updates.isEmpty else { return }
            updateRequestCount += 1
            if failedUpdateRequestNumbers.contains(updateRequestCount) {
                throw LocalWorkbookSheetsClientError.writeFailed(updateRequestCount)
            }
            let staged = try Self.applying(updates, to: tabs)
            if let persistTo {
                try LocalWorkbook(spreadsheetId: self.spreadsheetId, title: title, snapshots: staged).write(to: persistTo)
            }
            recordedBatches.append(updates)
            tabs = staged
        }
    }

    extension LocalWorkbookSheetsClient {
        fileprivate struct ParsedRange {
            let tabName: String
            let startRow: Int
            let startCol: Int
            let rowCount: Int
            let colCount: Int
        }

        fileprivate static func applying(
            _ updates: [SheetValueRangeUpdate],
            to workbook: [String: SheetSnapshot]
        ) throws -> [String: SheetSnapshot] {
            var staged = workbook
            for update in updates {
                let range = try parseRange(update.range)
                guard let snapshot = staged[range.tabName] else {
                    throw LocalWorkbookSheetsClientError.unknownTab(range.tabName)
                }
                staged[range.tabName] = SheetSnapshot(
                    values: try applying(update.values, to: snapshot.values, range: range),
                    rowVisibility: snapshot.rowVisibility
                )
            }
            return staged
        }

        fileprivate static func applying(
            _ values: [[String]],
            to grid: SheetGrid,
            range: ParsedRange
        ) throws -> SheetGrid {
            guard values.count == range.rowCount else {
                throw LocalWorkbookSheetsClientError.unsupportedValues(
                    "Expected \(range.rowCount) row(s), got \(values.count)"
                )
            }
            guard values.allSatisfy({ $0.count == range.colCount }) else {
                throw LocalWorkbookSheetsClientError.unsupportedValues(
                    "Expected every row to contain \(range.colCount) value(s)"
                )
            }

            var updated = grid
            let requiredRows = range.startRow + range.rowCount
            if requiredRows > updated.count {
                updated.append(contentsOf: SheetGrid(repeating: [], count: requiredRows - updated.count))
            }

            for rowOffset in 0..<range.rowCount {
                let rowIndex = range.startRow + rowOffset
                let requiredCols = range.startCol + range.colCount
                if requiredCols > updated[rowIndex].count {
                    updated[rowIndex].append(
                        contentsOf: [String](repeating: "", count: requiredCols - updated[rowIndex].count)
                    )
                }

                for colOffset in 0..<range.colCount {
                    updated[rowIndex][range.startCol + colOffset] = values[rowOffset][colOffset]
                }
            }

            return updated
        }

        fileprivate static func parseRange(_ range: String) throws -> ParsedRange {
            guard let split = splitA1Range(range) else {
                throw LocalWorkbookSheetsClientError.malformedRange(range)
            }

            let references = split.reference.uppercased()
                .split(separator: ":", maxSplits: 1, omittingEmptySubsequences: false)
            guard
                let start = a1CellIndex(String(references[0])),
                let end = references.count == 2 ? a1CellIndex(String(references[1])) : start,
                end.row >= start.row,
                end.col >= start.col
            else {
                throw LocalWorkbookSheetsClientError.malformedRange(range)
            }

            return ParsedRange(
                tabName: split.tabName,
                startRow: start.row,
                startCol: start.col,
                rowCount: end.row - start.row + 1,
                colCount: end.col - start.col + 1
            )
        }
    }

#endif
