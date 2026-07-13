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
    var snapshot: SheetSnapshot
    let layout: SheetLayout

    var grid: SheetGrid {
        snapshot.values
    }
}

struct SheetWritePlanner: Sendable {
    private let layoutBuilder: @Sendable (SheetSnapshot) -> SheetLayout

    init(
        layoutBuilder: @escaping @Sendable (SheetSnapshot) -> SheetLayout = { SheetLayoutInterpreter().interpret($0) }
    ) {
        self.layoutBuilder = layoutBuilder
    }

    init(layoutBuilder: @escaping @Sendable (SheetGrid) -> SheetLayout) {
        self.layoutBuilder = { snapshot in layoutBuilder(snapshot.values) }
    }

    func snapshot(for grid: SheetGrid) -> SheetWritePlanningSnapshot {
        snapshot(for: SheetSnapshot(values: grid))
    }

    func snapshot(for snapshot: SheetSnapshot) -> SheetWritePlanningSnapshot {
        SheetWritePlanningSnapshot(snapshot: snapshot, layout: layoutBuilder(snapshot))
    }

    func plan(_ request: SheetWriteRequest, in grid: SheetGrid) throws -> SheetCellUpdate {
        try plan(request, in: snapshot(for: grid))
    }

    func plan(_ request: SheetWriteRequest, in snapshot: SheetWritePlanningSnapshot) throws -> SheetCellUpdate {
        let target = try target(for: request, in: snapshot)
        return try plan(request, target: target, in: snapshot)
    }

    func target(for request: SheetWriteRequest, in snapshot: SheetWritePlanningSnapshot) throws -> SheetWriteTarget {
        let (row, col) = try resolveTarget(for: request, in: snapshot)
        return SheetWriteTarget(tabName: request.blockTab, row: row, col: col)
    }

    func plan(
        _ request: SheetWriteRequest,
        target: SheetWriteTarget,
        in snapshot: SheetWritePlanningSnapshot
    ) throws -> SheetCellUpdate {
        let actual = snapshot.grid.cell(row: target.row, col: target.col).trimmed
        if let multiLineValue = try multiLineNotesValue(
            for: request,
            target: target,
            actual: actual,
            in: snapshot
        ) {
            return SheetCellUpdate(
                tabName: target.tabName,
                row: target.row,
                col: target.col,
                value: multiLineValue
            )
        }

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
        let updatedSnapshot = SheetSnapshot(
            values: applying(update, to: snapshot.grid),
            rowVisibility: snapshot.snapshot.rowVisibility
        )
        return SheetWritePlanningSnapshot(snapshot: updatedSnapshot, layout: snapshot.layout)
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
        in snapshot: SheetWritePlanningSnapshot
    ) throws -> (row: Int, col: Int) {
        let layout = snapshot.layout

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
            guard snapshot.snapshot.isRowVisible(anchor.row) else {
                throw SheetWriterError.setRowNotFound(exerciseName: request.exerciseName, setIndex: request.setIndex)
            }
            return (anchor.row, col)
        }

        let lines = anchor.prescriptionLines(in: snapshot.grid, setsColumn: day.columns.sets)
        if lines.isMultiLine {
            guard let line = lines.line(containing: request.setIndex) else {
                throw SheetWriterError.setRowNotFound(exerciseName: request.exerciseName, setIndex: request.setIndex)
            }
            return (line.row, col)
        }

        return try resolveNotesTarget(for: request, day: day, anchor: anchor, col: col, in: snapshot)
    }

    private func resolveNotesTarget(
        for request: SheetWriteRequest,
        day: SheetLayoutDay,
        anchor: SheetLayoutExerciseAnchor,
        col: Int,
        in snapshot: SheetWritePlanningSnapshot
    ) throws -> (row: Int, col: Int) {
        let headerNotes = anchor.headerNotes(in: snapshot.grid, notesColumn: day.columns.notes)
        let setCount = anchor.prescribedSetCount(in: snapshot.grid, setsColumn: day.columns.sets)
        let compactHeaderSetOne =
            anchor.usesCompactHeaderSetOne(headerNotes: headerNotes, setCount: setCount)

        if compactHeaderSetOne, request.setIndex < setCount {
            return try resolveCompactNotesTarget(
                for: request,
                anchor: anchor,
                col: col,
                in: snapshot
            )
        }

        if anchor.isHeaderProtectedFromSetLogWrites(headerNotes: headerNotes, setCount: setCount),
            request.setIndex < setCount
        {
            guard let targetRow = anchor.firstVisibleWritableRow(in: snapshot.snapshot) else {
                throw SheetWriterError.headerNotesBlockSetRow(
                    exerciseName: request.exerciseName,
                    setIndex: request.setIndex
                )
            }
            return (targetRow, col)
        }

        guard
            let setRow = anchor.visibleSetLogRow(
                for: request.setIndex,
                compactHeaderSetOne: compactHeaderSetOne,
                in: snapshot.snapshot
            )
        else {
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

    private func resolveCompactNotesTarget(
        for request: SheetWriteRequest,
        anchor: SheetLayoutExerciseAnchor,
        col: Int,
        in snapshot: SheetWritePlanningSnapshot
    ) throws -> (row: Int, col: Int) {
        guard snapshot.snapshot.isRowVisible(anchor.row) else {
            throw SheetWriterError.setRowNotFound(exerciseName: request.exerciseName, setIndex: request.setIndex)
        }
        return (anchor.row, col)
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

    /// Per-line Set-Log value for coach J. Alarcon's multi-line template. Each Prescription
    /// Line keeps its Sets' logs comma-separated in its own Notes cell; the Set's position in
    /// that list is its offset within the Line. Returns nil for single-line (Kevin) Exercises,
    /// leaving the existing single-anchor logic in charge.
    private func multiLineNotesValue(
        for request: SheetWriteRequest,
        target: SheetWriteTarget,
        actual: String,
        in snapshot: SheetWritePlanningSnapshot
    ) throws -> String? {
        guard
            request.column == .notes,
            let day = snapshot.layout.day(week: request.week, day: request.day),
            day.columns.notes == target.col,
            let anchor = day.exerciseAnchors.first(where: { $0.name == request.exerciseName })
        else { return nil }

        let lines = anchor.prescriptionLines(in: snapshot.grid, setsColumn: day.columns.sets)
        guard
            lines.isMultiLine,
            let line = lines.line(containing: request.setIndex),
            line.row == target.row,
            let position = line.position(of: request.setIndex)
        else { return nil }

        var list = SetLogList(cell: actual)
        guard list.token(at: position) == request.expectedCurrentValue else {
            throw SheetWriterError.unexpectedCurrentValue(
                expected: request.expectedCurrentValue,
                actual: list.token(at: position)
            )
        }
        list.setToken(request.operation == .delete ? "" : (request.valueToWrite ?? ""), at: position)
        return list.cellValue
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
            let anchor = day.exerciseAnchors.first(where: { $0.name == request.exerciseName })
        else { return nil }

        let headerNotes = anchor.headerNotes(in: snapshot.grid, notesColumn: day.columns.notes)
        let setCount = anchor.prescribedSetCount(in: snapshot.grid, setsColumn: day.columns.sets)
        let usesHeaderTarget =
            anchor.row == target.row
            && anchor.usesCompactHeaderSetOne(headerNotes: headerNotes, setCount: setCount)
        let usesVisibleWritableTarget =
            anchor.row != target.row
            && anchor.isHeaderProtectedFromSetLogWrites(headerNotes: headerNotes, setCount: setCount)
        guard
            setCount > 1,
            request.setIndex < setCount,
            usesHeaderTarget || usesVisibleWritableTarget
        else { return nil }

        var list = SetLogList(cell: actual)
        if usesVisibleWritableTarget, !actual.isEmpty, !list.tokens.allSatisfy(SetLogToken.isSetLogListValue) {
            throw SheetWriterError.unexpectedCurrentValue(expected: request.expectedCurrentValue, actual: actual)
        }

        let currentSetValue = list.token(at: request.setIndex)
        guard currentSetValue == request.expectedCurrentValue else {
            throw SheetWriterError.unexpectedCurrentValue(
                expected: request.expectedCurrentValue,
                actual: currentSetValue
            )
        }

        list.setToken(request.operation == .delete ? "" : (request.valueToWrite ?? ""), at: request.setIndex)
        return list.cellValue
    }
}
