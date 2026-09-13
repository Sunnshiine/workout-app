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

    /// Every non-empty cell keyed by A1 reference: the shape an agent reads and edits.
    var sparseCells: [String: String] {
        var cells: [String: String] = [:]
        for (row, rowValues) in values.enumerated() {
            for (col, value) in rowValues.enumerated() where !value.isEmpty {
                cells[indexToA1(row: row, col: col)] = value
            }
        }
        return cells
    }

    /// Hidden rows keyed by their 1-based Sheet row number, the numbering A1 references use.
    var hiddenRowsByNumber: [Int: SheetRowVisibility] {
        Dictionary(uniqueKeysWithValues: rowVisibility.map { ($0.key + 1, $0.value) })
    }
}

/// `true` for a well-formed single-cell A1 reference such as `K15` or `AI37`.
func isA1CellReference(_ reference: String) -> Bool {
    reference.wholeMatch(of: /[A-Z]+[1-9][0-9]*/) != nil
}

extension Array where Element == [String] {
    func cell(row: Int, col: Int) -> String {
        guard row >= 0, row < count, col >= 0, col < self[row].count else { return "" }
        return self[row][col]
    }
}

func a1ToIndex(_ a1: String) -> (row: Int, col: Int) {
    let reference = a1.uppercased()
    var col = 0
    var idx = reference.startIndex
    while idx < reference.endIndex, reference[idx].isLetter {
        guard let asciiValue = reference[idx].asciiValue else { break }
        col = col * 26 + Int(asciiValue - 64)  // A=1
        idx = reference.index(after: idx)
    }
    let row = Int(reference[idx...]) ?? 1
    return (row - 1, col - 1)
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

/// A rectangular grid from a sparse A1 map; cells outside `rows` x `cols` and malformed keys are dropped.
func gridFromA1(_ cells: [String: String], rows: Int, cols: Int) -> SheetGrid {
    var grid = SheetGrid(repeating: [String](repeating: "", count: cols), count: rows)
    for (a1, value) in cells {
        let index = a1ToIndex(a1)
        if index.row >= 0, index.col >= 0, index.row < rows, index.col < cols {
            grid[index.row][index.col] = value
        }
    }
    return grid
}

func quotedSheetName(_ name: String) -> String {
    "'\(name.replacingOccurrences(of: "'", with: "''"))'"
}

func singleCellRange(tabName: String, row: Int, col: Int) -> String {
    "\(quotedSheetName(tabName))!\(indexToA1(row: row, col: col))"
}
