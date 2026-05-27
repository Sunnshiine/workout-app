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

struct SheetWritePlanner: Sendable {
    func plan(_ request: SheetWriteRequest, in grid: SheetGrid) throws -> SheetCellUpdate {
        let target = try resolveTarget(for: request, in: grid)
        let actual = grid.cell(row: target.row, col: target.col).trimmed
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

    private func resolveTarget(
        for request: SheetWriteRequest,
        in grid: SheetGrid
    ) throws -> (row: Int, col: Int) {
        let sections = locateWeekSections(in: grid)
        guard request.week > 0, request.week <= sections.count else {
            throw SheetWriterError.weekNotFound(request.week)
        }
        let section = sections[request.week - 1]
        guard request.day > 0, request.day <= section.dayStartCols.count else {
            throw SheetWriterError.dayNotFound(request.day)
        }
        let dayIndex = request.day - 1
        let cols = resolveDayColumns(in: grid, section: section, dayIndex: dayIndex)
        let col = try resolveColumn(request.column, cols: cols)

        let endRow = nextSectionStart(after: request.week - 1, sections: sections, grid: grid)
        let firstExerciseRow = section.roleHeaderRow + 1
        let anchorRows = (firstExerciseRow..<endRow).filter {
            !grid.cell(row: $0, col: cols.name).trimmed.isEmpty
        }
        guard
            let anchorIndex = anchorRows.firstIndex(where: {
                grid.cell(row: $0, col: cols.name).trimmed == request.exerciseName
            })
        else {
            throw SheetWriterError.exerciseNotFound(request.exerciseName)
        }

        let anchorRow = anchorRows[anchorIndex]
        if request.column == .lastSetRPE {
            return (anchorRow, col)
        }

        let nextAnchor = anchorIndex + 1 < anchorRows.count ? anchorRows[anchorIndex + 1] : endRow
        let setRow = anchorRow + request.setIndex + 1
        guard setRow < nextAnchor else {
            throw SheetWriterError.setRowNotFound(exerciseName: request.exerciseName, setIndex: request.setIndex)
        }
        return (setRow, col)
    }

    private func nextSectionStart(after index: Int, sections: [WeekSection], grid: SheetGrid) -> Int {
        index + 1 < sections.count ? sections[index + 1].headerRow : grid.count
    }
}
