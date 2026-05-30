@testable import WorkoutTracker

enum LocalWorkbookSheetsClientError: Error, Equatable, Sendable, CustomStringConvertible {
    case unknownTab(String)
    case malformedRange(String)
    case unsupportedValues(String)

    var description: String {
        switch self {
        case .unknownTab(let tab):
            "Unknown tab: \(tab)"
        case .malformedRange(let range):
            "Malformed A1 range: \(range)"
        case .unsupportedValues(let details):
            "Unsupported values: \(details)"
        }
    }
}

actor LocalWorkbookSheetsClient: SheetsClient {
    private var tabs: [String: SheetGrid]
    private(set) var recordedBatches: [[SheetValueRangeUpdate]] = []

    init(spreadsheetId: String = "sid", tabs: [String: SheetGrid]) {
        self.tabs = tabs
    }

    func listTabTitles(spreadsheetId: String) async throws -> [String] {
        tabs.keys.sorted()
    }

    func fetchTab(spreadsheetId: String, tabName: String) async throws -> SheetGrid {
        guard let grid = tabs[tabName] else {
            throw LocalWorkbookSheetsClientError.unknownTab(tabName)
        }
        return grid
    }

    func updateCells(spreadsheetId: String, range: String, values: [[String]]) async throws {
        try await updateCells(
            spreadsheetId: spreadsheetId,
            updates: [SheetValueRangeUpdate(range: range, values: values)]
        )
    }

    func updateCells(spreadsheetId: String, updates: [SheetValueRangeUpdate]) async throws {
        let staged = try Self.applying(updates, to: tabs)
        recordedBatches.append(updates)
        tabs = staged
    }
}

private extension LocalWorkbookSheetsClient {
    struct ParsedRange {
        let tabName: String
        let startRow: Int
        let startCol: Int
        let rowCount: Int
        let colCount: Int
    }

    static func applying(
        _ updates: [SheetValueRangeUpdate],
        to workbook: [String: SheetGrid]
    ) throws -> [String: SheetGrid] {
        var staged = workbook
        for update in updates {
            let range = try parseRange(update.range)
            guard let grid = staged[range.tabName] else {
                throw LocalWorkbookSheetsClientError.unknownTab(range.tabName)
            }
            staged[range.tabName] = try applying(update.values, to: grid, range: range)
        }
        return staged
    }

    static func applying(
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

    static func parseRange(_ range: String) throws -> ParsedRange {
        let split = try splitA1Range(range)
        let references = split.reference
            .split(separator: ":", maxSplits: 1, omittingEmptySubsequences: false)
            .map(String.init)
        guard references.count == 1 || references.count == 2 else {
            throw LocalWorkbookSheetsClientError.malformedRange(range)
        }

        let start = try parseCellReference(references[0], sourceRange: range)
        let end: (row: Int, col: Int)
        if references.count == 2 {
            end = try parseCellReference(references[1], sourceRange: range)
        } else {
            end = start
        }
        guard end.row >= start.row, end.col >= start.col else {
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

    static func splitA1Range(_ range: String) throws -> (tabName: String, reference: String) {
        var inQuotedTab = false
        var index = range.startIndex
        while index < range.endIndex {
            let character = range[index]
            if character == "'" {
                let next = range.index(after: index)
                if inQuotedTab, next < range.endIndex, range[next] == "'" {
                    index = range.index(after: next)
                    continue
                }
                inQuotedTab.toggle()
            } else if character == "!", !inQuotedTab {
                let rawTabName = String(range[..<index])
                let referenceStart = range.index(after: index)
                let reference = String(range[referenceStart...])
                guard !rawTabName.isEmpty, !reference.isEmpty else {
                    throw LocalWorkbookSheetsClientError.malformedRange(range)
                }
                return (try unquotedTabName(rawTabName, sourceRange: range), reference)
            }
            index = range.index(after: index)
        }

        throw LocalWorkbookSheetsClientError.malformedRange(range)
    }

    static func unquotedTabName(_ raw: String, sourceRange: String) throws -> String {
        guard raw.hasPrefix("'") || raw.hasSuffix("'") else { return raw }
        guard raw.hasPrefix("'"), raw.hasSuffix("'"), raw.count >= 2 else {
            throw LocalWorkbookSheetsClientError.malformedRange(sourceRange)
        }

        let inner = raw.dropFirst().dropLast()
        return inner.replacingOccurrences(of: "''", with: "'")
    }

    static func parseCellReference(_ reference: String, sourceRange: String) throws -> (row: Int, col: Int) {
        let upper = reference.uppercased()
        var letters = ""
        var digits = ""

        for character in upper {
            if character.isLetter, digits.isEmpty {
                letters.append(character)
            } else if character.isNumber {
                digits.append(character)
            } else {
                throw LocalWorkbookSheetsClientError.malformedRange(sourceRange)
            }
        }

        guard !letters.isEmpty, !digits.isEmpty, let rowNumber = Int(digits), rowNumber > 0 else {
            throw LocalWorkbookSheetsClientError.malformedRange(sourceRange)
        }

        var colNumber = 0
        for byte in letters.utf8 {
            guard byte >= 65, byte <= 90 else {
                throw LocalWorkbookSheetsClientError.malformedRange(sourceRange)
            }
            colNumber = colNumber * 26 + Int(byte - 64)
        }

        return (row: rowNumber - 1, col: colNumber - 1)
    }
}
