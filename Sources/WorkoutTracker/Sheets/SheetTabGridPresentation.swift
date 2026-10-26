import Foundation

/// What a Day's column holds, which sets how wide it reads.
enum SheetTabColumnRole: Sendable {
    case name, notes, value
}

/// A Sheet tab cut into the sections the app reads: each Week's Days, each Day the rows and columns
/// of its own section that hold a value. A Day's `Day N` header, its date, and its role headers
/// ("Sets", "Reps") lift out of the rows into the Day's title and column labels. Cells keep their
/// Sheet letters and 1-based row numbers so the athlete can find them in the spreadsheet, and
/// hidden rows stay in, flagged.
struct SheetTabGridPresentation: Equatable, Sendable {
    struct Week: Equatable, Sendable, Identifiable {
        let number: Int
        let days: [Day]

        var id: Int { number }
    }

    struct Day: Equatable, Sendable, Identifiable {
        let number: Int
        /// The `Day N` header cell as the coach typed it.
        let title: String
        /// The cell under the header, as the coach typed it.
        let date: String
        let columns: [Column]
        let rows: [Row]

        var id: Int { number }
    }

    struct Column: Equatable, Sendable, Identifiable {
        /// The 0-based Sheet column.
        let index: Int
        /// The Day's role header in this column, `""` when it has none.
        let label: String
        let role: SheetTabColumnRole

        var id: Int { index }
        var letter: String { columnName(index) }
    }

    struct Row: Equatable, Sendable, Identifiable {
        /// The row's 1-based number in the Sheet.
        let number: Int
        /// One value per kept column, `""` for an empty cell.
        let cells: [String]
        let isHidden: Bool
        /// The row names an Exercise rather than continuing the one above.
        let startsExercise: Bool

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
            Week(number: week.number, days: week.days.map { Self.day($0, of: week, in: sheet) })
        }
    }

    private static func day(_ day: SheetLayoutDay, of week: SheetLayoutWeek, in sheet: SheetSnapshot) -> Day {
        let grid = sheet.values
        let rows = week.headerRow..<week.endRow
        let nameColumn = day.columns.name
        func holdsValue(_ row: Int, _ col: Int) -> Bool { !grid.cell(row: row, col: col).trimmed.isEmpty }
        func isLifted(_ row: Int, _ col: Int) -> Bool {
            row == week.roleHeaderRow || (col == nameColumn && (row == week.headerRow || row == week.dateRow))
        }

        let columns = day.columns.span.filter { col in rows.contains { holdsValue($0, col) } }
        let exerciseRows = Set(
            anchorRows(in: grid, cols: day.columns, firstRow: week.roleHeaderRow + 1, upper: min(week.endRow, grid.count))
        )
        return Day(
            number: day.number,
            title: grid.cell(row: week.headerRow, col: nameColumn).trimmed,
            date: grid.cell(row: week.dateRow, col: nameColumn).trimmed,
            columns: columns.map { col in
                Column(
                    index: col,
                    label: grid.cell(row: week.roleHeaderRow, col: col).trimmed,
                    role: col == nameColumn ? .name : col == day.columns.notes ? .notes : .value
                )
            },
            rows: rows.filter { row in columns.contains { holdsValue(row, $0) && !isLifted(row, $0) } }.map { row in
                Row(
                    number: row + 1,
                    cells: columns.map { grid.cell(row: row, col: $0) },
                    isHidden: !sheet.isRowVisible(row),
                    startsExercise: exerciseRows.contains(row)
                )
            }
        )
    }

    /// The A1 reference of the cell in 0-based Sheet `column` of the row numbered `row`, as "AI37".
    static func cellReference(row: Int, column: Int) -> String {
        indexToA1(row: row - 1, col: column)
    }
}
