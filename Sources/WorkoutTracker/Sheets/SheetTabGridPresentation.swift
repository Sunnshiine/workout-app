import Foundation

/// A Sheet tab cut into the sections the app reads: each Week's Days, each Day the rows and columns
/// of its own section that hold a value. Cells keep their Sheet letters and 1-based row numbers so
/// the athlete can find them in the spreadsheet, and hidden rows stay in, flagged.
struct SheetTabGridPresentation: Equatable, Sendable {
    struct Week: Equatable, Sendable, Identifiable {
        let number: Int
        let days: [Day]

        var id: Int { number }
    }

    struct Day: Equatable, Sendable, Identifiable {
        let number: Int
        /// The 0-based Sheet columns kept, in Sheet order.
        let columns: [Int]
        let rows: [Row]

        var id: Int { number }
    }

    struct Row: Equatable, Sendable, Identifiable {
        /// The row's 1-based number in the Sheet.
        let number: Int
        /// One value per kept column, `""` for an empty cell.
        let cells: [String]
        let isHidden: Bool

        var id: Int { number }
    }

    let tab: String
    let weeks: [Week]

    init(_ snapshot: SheetTabSnapshot) {
        let indices = snapshot.cells.compactMap { a1, value in value.isEmpty ? nil : a1CellIndex(a1) }
        let grid = gridFromA1(
            snapshot.cells,
            rows: (indices.map(\.row).max() ?? -1) + 1,
            cols: (indices.map(\.col).max() ?? -1) + 1
        )
        let rowVisibility = Dictionary(uniqueKeysWithValues: snapshot.hiddenRows.map { ($0.key - 1, $0.value) })
        let sheet = SheetSnapshot(values: grid, rowVisibility: rowVisibility)

        tab = snapshot.tab
        weeks = SheetLayoutInterpreter().interpret(sheet).weeks.map { week in
            Week(
                number: week.number,
                days: week.days.map { day in
                    Self.day(day, rows: week.headerRow..<week.endRow, in: sheet)
                }
            )
        }
    }

    private static func day(_ day: SheetLayoutDay, rows: Range<Int>, in sheet: SheetSnapshot) -> Day {
        let grid = sheet.values
        func holdsValue(_ row: Int, _ col: Int) -> Bool { !grid.cell(row: row, col: col).trimmed.isEmpty }

        let columns = day.columns.span.filter { col in rows.contains { holdsValue($0, col) } }
        return Day(
            number: day.number,
            columns: columns,
            rows: rows.filter { row in columns.contains { holdsValue(row, $0) } }.map { row in
                Row(
                    number: row + 1,
                    cells: columns.map { grid.cell(row: row, col: $0) },
                    isHidden: !sheet.isRowVisible(row)
                )
            }
        )
    }

    static func columnLetter(_ column: Int) -> String {
        columnName(column)
    }

    /// The A1 reference of the cell in 0-based Sheet `column` of the row numbered `row`, as "AI37".
    static func cellReference(row: Int, column: Int) -> String {
        indexToA1(row: row - 1, col: column)
    }
}
