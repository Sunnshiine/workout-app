import Foundation

/// A Sheet tab laid out as the spreadsheet shows it: raw cell values under column letters and
/// beside 1-based row numbers, trimmed to the box that holds a value. Hidden rows stay in the grid,
/// flagged, so the athlete sees every row the coach wrote.
struct SheetTabGridPresentation: Equatable, Sendable {
    struct Row: Equatable, Sendable, Identifiable {
        /// The row's 1-based number in the Sheet.
        let number: Int
        /// One value per column, `""` for an empty cell.
        let cells: [String]
        let isHidden: Bool

        var id: Int { number }
    }

    let tab: String
    /// Column letters from A through the last column holding a value.
    let columns: [String]
    /// Rows 1 through the last row holding a value.
    let rows: [Row]
    /// Each Week's number to the 1-based row of its "Day N" header, read the way BlockBuilder
    /// reads the tab, so the Week numbers match the Block grid's.
    let weekHeaderRows: [Int: Int]

    init(_ snapshot: SheetTabSnapshot) {
        let indices = snapshot.cells.compactMap { a1, value in value.isEmpty ? nil : a1CellIndex(a1) }
        let rowCount = (indices.map(\.row).max() ?? -1) + 1
        let columnCount = (indices.map(\.col).max() ?? -1) + 1
        let grid = gridFromA1(snapshot.cells, rows: rowCount, cols: columnCount)
        let rowVisibility = Dictionary(uniqueKeysWithValues: snapshot.hiddenRows.map { ($0.key - 1, $0.value) })
        let sheet = SheetSnapshot(values: grid, rowVisibility: rowVisibility)

        tab = snapshot.tab
        columns = (0..<columnCount).map(columnName)
        rows = grid.enumerated().map { index, cells in
            Row(number: index + 1, cells: cells, isHidden: !sheet.isRowVisible(index))
        }
        weekHeaderRows = Dictionary(
            uniqueKeysWithValues: SheetLayoutInterpreter().interpret(sheet).weeks.map { ($0.number, $0.headerRow + 1) }
        )
    }

    /// The A1 reference of the cell at `column` (0-based) in the row numbered `row`, as "AI37".
    static func cellReference(row: Int, column: Int) -> String {
        indexToA1(row: row - 1, col: column)
    }
}
