import Foundation

struct SheetWriteRequest: Sendable, Equatable {
    var blockTab: String
    var week: Int
    var day: Int
    var exerciseName: String
    var setIndex: Int
    var column: PendingWriteColumn
    var operation: PendingWriteOperation
    var valueToWrite: String?
    var expectedCurrentValue: String

    @MainActor
    init(_ write: PendingWrite) {
        self.init(
            blockTab: write.blockTab,
            week: write.week,
            day: write.day,
            exerciseName: write.exerciseName,
            setIndex: write.setIndex,
            column: write.column,
            operation: write.operation,
            valueToWrite: write.valueToWrite,
            expectedCurrentValue: write.expectedCurrentValue
        )
    }

    init(
        blockTab: String,
        week: Int,
        day: Int,
        exerciseName: String,
        setIndex: Int,
        column: PendingWriteColumn,
        operation: PendingWriteOperation,
        valueToWrite: String?,
        expectedCurrentValue: String
    ) {
        self.blockTab = blockTab
        self.week = week
        self.day = day
        self.exerciseName = exerciseName
        self.setIndex = setIndex
        self.column = column
        self.operation = operation
        self.valueToWrite = valueToWrite
        self.expectedCurrentValue = expectedCurrentValue
    }
}

enum SheetWriterError: Error, Equatable, LocalizedError {
    case weekNotFound(Int)
    case dayNotFound(Int)
    case columnNotFound(String)
    case exerciseNotFound(String)
    case setRowNotFound(exerciseName: String, setIndex: Int)
    case unexpectedCurrentValue(expected: String, actual: String)

    var errorDescription: String? {
        switch self {
        case .weekNotFound(let week): return "Week \(week) was not found in the sheet"
        case .dayNotFound(let day): return "Day \(day) was not found in the sheet"
        case .columnNotFound(let column): return "\(column) column was not found"
        case .exerciseNotFound(let name): return "\(name) was not found in the sheet"
        case .setRowNotFound(let name, let index): return "Set \(index + 1) row was not found for \(name)"
        case .unexpectedCurrentValue(let expected, let actual):
            return "Expected '\(expected)', found '\(actual)'"
        }
    }
}

struct SheetCellUpdate: Sendable, Equatable {
    var tabName: String
    var row: Int
    var col: Int
    var value: String

    var range: String {
        singleCellRange(tabName: tabName, row: row, col: col)
    }
}

struct SheetWriter: Sendable {
    private let client: any SheetsClient

    init(client: any SheetsClient) {
        self.client = client
    }

    func write(_ update: SheetCellUpdate, spreadsheetId: String) async throws {
        try await client.updateCells(spreadsheetId: spreadsheetId, range: update.range, values: [[update.value]])
    }
}

struct SheetWritePlanningSnapshot: Sendable {
    var grid: SheetGrid
    let index: SheetWritePlanningIndex
}

struct SheetWritePlanningIndex: Sendable {
    private let weeks: [SheetWriteWeekIndex]

    init(grid: SheetGrid) {
        let sections = locateWeekSections(in: grid)
        self.weeks = sections.enumerated().map { index, section in
            let endRow = index + 1 < sections.count ? sections[index + 1].headerRow : grid.count
            let days = section.dayStartCols.indices.map { dayIndex in
                let columns = resolveDayColumns(in: grid, section: section, dayIndex: dayIndex)
                let firstExerciseRow = section.roleHeaderRow + 1
                let anchors = (firstExerciseRow..<endRow).compactMap { row -> SheetWriteExerciseAnchor? in
                    let name = grid.cell(row: row, col: columns.name).trimmed
                    guard !name.isEmpty else { return nil }
                    return SheetWriteExerciseAnchor(name: name, row: row)
                }
                return SheetWriteDayIndex(columns: columns, anchors: anchors)
            }
            return SheetWriteWeekIndex(endRow: endRow, days: Array(days))
        }
    }

    func target(for request: SheetWriteRequest, in grid: SheetGrid) throws -> (row: Int, col: Int) {
        guard request.week > 0, request.week <= weeks.count else {
            throw SheetWriterError.weekNotFound(request.week)
        }
        let week = weeks[request.week - 1]
        guard request.day > 0, request.day <= week.days.count else {
            throw SheetWriterError.dayNotFound(request.day)
        }
        let day = week.days[request.day - 1]
        let col = try resolveColumn(request.column, cols: day.columns)

        guard
            let anchorIndex = day.anchors.firstIndex(where: { $0.name == request.exerciseName })
        else {
            throw SheetWriterError.exerciseNotFound(request.exerciseName)
        }

        let anchor = day.anchors[anchorIndex]
        if request.column == .lastSetRPE {
            return (anchor.row, col)
        }

        let nextAnchor = anchorIndex + 1 < day.anchors.count ? day.anchors[anchorIndex + 1].row : week.endRow
        let setRow = anchor.row + request.setIndex + 1
        guard setRow < nextAnchor else {
            throw SheetWriterError.setRowNotFound(exerciseName: request.exerciseName, setIndex: request.setIndex)
        }
        return (setRow, col)
    }

    private func resolveColumn(_ column: PendingWriteColumn, cols: DayColumns) throws -> Int {
        switch column {
        case .notes:
            guard let notes = cols.notes else { throw SheetWriterError.columnNotFound("Notes") }
            return notes
        case .lastSetRPE:
            guard let rpe = cols.lastSetRPE else { throw SheetWriterError.columnNotFound("Last set RPE") }
            return rpe
        }
    }
}

private struct SheetWriteWeekIndex: Sendable {
    let endRow: Int
    let days: [SheetWriteDayIndex]
}

private struct SheetWriteDayIndex: Sendable {
    let columns: DayColumns
    let anchors: [SheetWriteExerciseAnchor]
}

private struct SheetWriteExerciseAnchor: Sendable {
    let name: String
    let row: Int
}

struct SheetWritePlanner: Sendable {
    private let indexBuilder: @Sendable (SheetGrid) -> SheetWritePlanningIndex

    init(indexBuilder: @escaping @Sendable (SheetGrid) -> SheetWritePlanningIndex = { SheetWritePlanningIndex(grid: $0) }) {
        self.indexBuilder = indexBuilder
    }

    func snapshot(for grid: SheetGrid) -> SheetWritePlanningSnapshot {
        SheetWritePlanningSnapshot(grid: grid, index: indexBuilder(grid))
    }

    func plan(_ request: SheetWriteRequest, in grid: SheetGrid) throws -> SheetCellUpdate {
        try plan(request, in: snapshot(for: grid))
    }

    func plan(_ request: SheetWriteRequest, in snapshot: SheetWritePlanningSnapshot) throws -> SheetCellUpdate {
        let target = try snapshot.index.target(for: request, in: snapshot.grid)
        let actual = snapshot.grid.cell(row: target.row, col: target.col).trimmed
        guard actual == request.expectedCurrentValue else {
            throw SheetWriterError.unexpectedCurrentValue(expected: request.expectedCurrentValue, actual: actual)
        }

        return SheetCellUpdate(
            tabName: request.blockTab,
            row: target.row,
            col: target.col,
            value: request.operation == .delete ? "" : (request.valueToWrite ?? "")
        )
    }

    func applying(_ update: SheetCellUpdate, to snapshot: SheetWritePlanningSnapshot) -> SheetWritePlanningSnapshot {
        SheetWritePlanningSnapshot(grid: applying(update, to: snapshot.grid), index: snapshot.index)
    }

    func applying(_ update: SheetCellUpdate, to grid: SheetGrid) -> SheetGrid {
        var updated = grid
        if update.row >= updated.count {
            updated.append(contentsOf: SheetGrid(repeating: [], count: update.row - updated.count + 1))
        }
        if update.col >= updated[update.row].count {
            updated[update.row].append(contentsOf: [String](repeating: "", count: update.col - updated[update.row].count + 1))
        }
        updated[update.row][update.col] = update.value
        return updated
    }
}
