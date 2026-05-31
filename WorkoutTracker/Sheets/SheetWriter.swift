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
    case headerNotesBlockSetRow(exerciseName: String, setIndex: Int)
    case unexpectedCurrentValue(expected: String, actual: String)

    var errorDescription: String? {
        switch self {
        case .weekNotFound(let week): return "Week \(week) was not found in the sheet"
        case .dayNotFound(let day): return "Day \(day) was not found in the sheet"
        case .columnNotFound(let column): return "\(column) column was not found"
        case .exerciseNotFound(let name): return "\(name) was not found in the sheet"
        case .setRowNotFound(let name, let index): return "Set \(index + 1) row was not found for \(name)"
        case .headerNotesBlockSetRow(let name, let index):
            return """
                Set \(index + 1) for \(name) cannot be written because existing header Notes prevent writing there, \
                and no safe Set row exists before the next Exercise. Add a row in the Sheet, clear or migrate the \
                existing header note, then sync again.
                """
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

    var target: SheetWriteTarget {
        SheetWriteTarget(tabName: tabName, row: row, col: col)
    }

    var range: String {
        singleCellRange(tabName: tabName, row: row, col: col)
    }
}

struct SheetWriteTarget: Sendable, Equatable {
    let tabName: String
    let row: Int
    let col: Int
}

struct SheetWriter: Sendable {
    private let client: any SheetsClient

    init(client: any SheetsClient) {
        self.client = client
    }

    func write(_ update: SheetCellUpdate, spreadsheetId: String) async throws {
        try await client.updateCells(spreadsheetId: spreadsheetId, range: update.range, values: [[update.value]])
    }

    func write(_ updates: [SheetCellUpdate], spreadsheetId: String) async throws {
        guard !updates.isEmpty else { return }
        try await client.updateCells(
            spreadsheetId: spreadsheetId,
            updates: updates.map { SheetValueRangeUpdate(range: $0.range, values: [[$0.value]]) }
        )
    }
}

struct SheetWritePlanningSnapshot: Sendable {
    var grid: SheetGrid
    let layout: SheetLayout
}

struct SheetWritePlanner: Sendable {
    private let layoutBuilder: @Sendable (SheetGrid) -> SheetLayout

    init(layoutBuilder: @escaping @Sendable (SheetGrid) -> SheetLayout = { SheetLayoutInterpreter().interpret($0) }) {
        self.layoutBuilder = layoutBuilder
    }

    func snapshot(for grid: SheetGrid) -> SheetWritePlanningSnapshot {
        SheetWritePlanningSnapshot(grid: grid, layout: layoutBuilder(grid))
    }

    func plan(_ request: SheetWriteRequest, in grid: SheetGrid) throws -> SheetCellUpdate {
        try plan(request, in: snapshot(for: grid))
    }

    func plan(_ request: SheetWriteRequest, in snapshot: SheetWritePlanningSnapshot) throws -> SheetCellUpdate {
        let target = try target(for: request, in: snapshot)
        return try plan(request, target: target, in: snapshot)
    }

    func target(for request: SheetWriteRequest, in snapshot: SheetWritePlanningSnapshot) throws -> SheetWriteTarget {
        let (row, col) = try resolveTarget(for: request, layout: snapshot.layout, grid: snapshot.grid)
        return SheetWriteTarget(tabName: request.blockTab, row: row, col: col)
    }

    func plan(
        _ request: SheetWriteRequest,
        target: SheetWriteTarget,
        in snapshot: SheetWritePlanningSnapshot
    ) throws -> SheetCellUpdate {
        let actual = snapshot.grid.cell(row: target.row, col: target.col).trimmed
        if let aggregateValue = try compactAggregateHeaderValue(
            for: request,
            target: target,
            actual: actual,
            in: snapshot
        ) {
            return SheetCellUpdate(
                tabName: target.tabName,
                row: target.row,
                col: target.col,
                value: aggregateValue
            )
        }

        guard actual == request.expectedCurrentValue else {
            throw SheetWriterError.unexpectedCurrentValue(expected: request.expectedCurrentValue, actual: actual)
        }

        return SheetCellUpdate(
            tabName: target.tabName,
            row: target.row,
            col: target.col,
            value: request.operation == .delete ? "" : (request.valueToWrite ?? "")
        )
    }

    func applying(_ update: SheetCellUpdate, to snapshot: SheetWritePlanningSnapshot) -> SheetWritePlanningSnapshot {
        SheetWritePlanningSnapshot(grid: applying(update, to: snapshot.grid), layout: snapshot.layout)
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

    private func resolveTarget(
        for request: SheetWriteRequest,
        layout: SheetLayout,
        grid: SheetGrid
    ) throws -> (row: Int, col: Int) {
        guard layout.week(number: request.week) != nil else {
            throw SheetWriterError.weekNotFound(request.week)
        }
        guard let day = layout.day(week: request.week, day: request.day) else {
            throw SheetWriterError.dayNotFound(request.day)
        }
        let col = try resolveColumn(request.column, cols: day.columns)

        guard let anchor = day.exerciseAnchors.first(where: { $0.name == request.exerciseName }) else {
            throw SheetWriterError.exerciseNotFound(request.exerciseName)
        }

        if request.column == .lastSetRPE {
            return (anchor.row, col)
        }

        let headerNotes = anchor.headerNotes(in: grid, notesColumn: day.columns.notes)
        let setCount = anchor.prescribedSetCount(in: grid, setsColumn: day.columns.sets)
        let compactHeaderSetOne =
            anchor.usesCompactHeaderSetOne(headerNotes: headerNotes)
            || isCompactAggregateHeader(headerNotes.value, setCount: setCount)
        if request.column == .notes {
            if compactHeaderSetOne, request.setIndex < setCount {
                if request.setIndex > 0,
                    let continuationRow = anchor.setLogRow(
                        for: request.setIndex,
                        compactHeaderSetOne: compactHeaderSetOne
                    ) {
                    let continuationValue = grid.cell(row: continuationRow, col: col).trimmed
                    if !continuationValue.isEmpty {
                        return (continuationRow, col)
                    }
                }
                return (anchor.row, col)
            }
        }

        guard let setRow = anchor.setLogRow(for: request.setIndex, compactHeaderSetOne: compactHeaderSetOne) else {
            if request.column == .notes, headerNotes.hasProtectedValue {
                throw SheetWriterError.headerNotesBlockSetRow(
                    exerciseName: request.exerciseName,
                    setIndex: request.setIndex
                )
            }
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

    private func compactAggregateHeaderValue(
        for request: SheetWriteRequest,
        target: SheetWriteTarget,
        actual: String,
        in snapshot: SheetWritePlanningSnapshot
    ) throws -> String? {
        guard
            request.column == .notes,
            let day = snapshot.layout.day(week: request.week, day: request.day),
            day.columns.notes == target.col,
            let anchor = day.exerciseAnchors.first(where: { $0.name == request.exerciseName }),
            anchor.row == target.row
        else { return nil }

        let headerNotes = anchor.headerNotes(in: snapshot.grid, notesColumn: day.columns.notes)
        let setCount = anchor.prescribedSetCount(in: snapshot.grid, setsColumn: day.columns.sets)
        guard
            setCount > 1,
            request.setIndex < setCount,
            anchor.usesCompactHeaderSetOne(headerNotes: headerNotes)
                || isCompactAggregateHeader(headerNotes.value, setCount: setCount)
        else { return nil }

        var values = splitSheetNotesList(actual)
        if values.count == 1, values[0].isEmpty {
            values = []
        }
        while values.count <= request.setIndex {
            values.append("")
        }

        let currentSetValue = values[request.setIndex]
        guard currentSetValue == request.expectedCurrentValue else {
            throw SheetWriterError.unexpectedCurrentValue(
                expected: request.expectedCurrentValue,
                actual: currentSetValue
            )
        }

        values[request.setIndex] = request.operation == .delete ? "" : (request.valueToWrite ?? "")
        return joinedSheetNotesList(values)
    }

    private func isCompactAggregateHeader(_ value: String, setCount: Int) -> Bool {
        let values = splitSheetNotesList(value)
        guard values.count > 1, values.count <= setCount else { return false }
        return values.allSatisfy { value in
            value.isEmpty
                || value.caseInsensitiveCompare("skip") == .orderedSame
                || SetLog(formatted: value) != nil
        }
    }
}
