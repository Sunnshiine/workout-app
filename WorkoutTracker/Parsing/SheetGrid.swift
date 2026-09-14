import Foundation

typealias SheetGrid = [[String]]

/// A Sheet row hidden by the user or by a filter (ADR-0003: hidden rows are never write targets).
public struct SheetRowVisibility: Sendable, Equatable, Codable {
    public let hiddenByUser: Bool
    public let hiddenByFilter: Bool

    public init(hiddenByUser: Bool = false, hiddenByFilter: Bool = false) {
        self.hiddenByUser = hiddenByUser
        self.hiddenByFilter = hiddenByFilter
    }

    var isVisible: Bool {
        !hiddenByUser && !hiddenByFilter
    }
}

struct SheetSnapshot: Sendable, Equatable {
    let values: SheetGrid
    let rowVisibility: [Int: SheetRowVisibility]

    init(values: SheetGrid, rowVisibility: [Int: SheetRowVisibility] = [:]) {
        self.values = values
        self.rowVisibility = rowVisibility
    }

    func isRowVisible(_ row: Int) -> Bool {
        rowVisibility[row]?.isVisible ?? true
    }

    var sparseCells: [String: String] {
        var cells: [String: String] = [:]
        for (row, rowValues) in values.enumerated() {
            for (col, value) in rowValues.enumerated() where !value.isEmpty {
                cells[indexToA1(row: row, col: col)] = value
            }
        }
        return cells
    }

    var hiddenRowsByNumber: [Int: SheetRowVisibility] {
        Dictionary(uniqueKeysWithValues: rowVisibility.map { ($0.key + 1, $0.value) })
    }
}

public func isA1CellReference(_ reference: String) -> Bool {
    a1CellIndex(reference) != nil
}

/// The zero-based row and column an A1 cell reference names, or nil when it is not one ("K15" is (14, 10)).
///
/// Uppercase only: callers that accept user input fold case at their own boundary.
func a1CellIndex(_ reference: String) -> (row: Int, col: Int)? {
    guard let match = reference.wholeMatch(of: /([A-Z]+)([1-9][0-9]*)/), let rowNumber = Int(match.2) else {
        return nil
    }
    var colNumber = 0
    for byte in match.1.utf8 {
        colNumber = colNumber * 26 + Int(byte - 64)  // A=1
    }
    return (row: rowNumber - 1, col: colNumber - 1)
}

/// Splits an A1 range such as `'Coach''s Block'!K15:L16` into its tab name and its cell reference.
///
/// A quoted tab name may contain `!` and spells an apostrophe `''`; a bare one may contain neither.
func splitA1Range(_ range: String) -> (tabName: String, reference: String)? {
    if let quoted = range.wholeMatch(of: /'((?:[^']|'')*)'!(.+)/) {
        let tabName = String(quoted.1).replacingOccurrences(of: "''", with: "'")
        return tabName.isEmpty ? nil : (tabName, String(quoted.2))
    }
    guard let bare = range.wholeMatch(of: /([^'!]+)!(.+)/) else { return nil }
    return (tabName: String(bare.1), reference: String(bare.2))
}

extension Array where Element == [String] {
    func cell(row: Int, col: Int) -> String {
        guard row >= 0, row < count, col >= 0, col < self[row].count else { return "" }
        return self[row][col]
    }
}

func columnName(_ zeroBasedColumn: Int) -> String {
    let letters = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZ")
    var value = zeroBasedColumn + 1
    var result = ""
    while value > 0 {
        let remainder = (value - 1) % 26
        result.insert(letters[remainder], at: result.startIndex)
        value = (value - 1) / 26
    }
    return result
}

func indexToA1(row: Int, col: Int) -> String {
    "\(columnName(col))\(row + 1)"
}

func gridFromA1(_ cells: [String: String], rows: Int, cols: Int) -> SheetGrid {
    var grid = SheetGrid(repeating: [String](repeating: "", count: cols), count: rows)
    for (a1, value) in cells {
        guard let index = a1CellIndex(a1), index.row < rows, index.col < cols else { continue }
        grid[index.row][index.col] = value
    }
    return grid
}

func quotedSheetName(_ name: String) -> String {
    "'\(name.replacingOccurrences(of: "'", with: "''"))'"
}

func singleCellRange(tabName: String, row: Int, col: Int) -> String {
    "\(quotedSheetName(tabName))!\(indexToA1(row: row, col: col))"
}
