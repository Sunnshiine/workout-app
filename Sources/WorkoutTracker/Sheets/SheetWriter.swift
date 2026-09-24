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

    /// The value this write lands in its cell: a delete clears it, an upsert writes its value.
    var writtenValue: String {
        operation == .delete ? "" : (valueToWrite ?? "")
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

enum SheetWriteAddressing: Sendable {
    case weekNotFound
    case dayNotFound
    case columnNotFound(header: String)
    case exerciseNotFound
    case lastSetRPE(anchor: SheetLayoutExerciseAnchor, col: Int)
    case setLog(anchor: SheetLayoutExerciseAnchor, SetLogPlacementResolution)

    func addressedCell(for request: SheetWriteRequest) throws -> (row: Int, col: Int) {
        switch self {
        case .weekNotFound:
            throw SheetWriterError.weekNotFound(request.week)
        case .dayNotFound:
            throw SheetWriterError.dayNotFound(request.day)
        case .columnNotFound(let header):
            throw SheetWriterError.columnNotFound(header)
        case .exerciseNotFound:
            throw SheetWriterError.exerciseNotFound(request.exerciseName)
        case .lastSetRPE(let anchor, let col):
            return (anchor.row, col)
        case .setLog(_, let resolution):
            return try resolution.addressedCell(for: request)
        }
    }
}

extension SetLogPlacementResolution {
    /// The cell this resolution addresses, or the writer error it names for this request. The
    /// placement rule decides where a Set Log may go; this is the one place its four outcomes
    /// become a write target or a refusal.
    func addressedCell(for request: SheetWriteRequest) throws -> (row: Int, col: Int) {
        switch self {
        case .placed(let placement):
            return (placement.row, placement.col)
        case .protectedHeaderBlocksSetRow:
            throw SheetWriterError.headerNotesBlockSetRow(
                exerciseName: request.exerciseName,
                setIndex: request.setIndex
            )
        case .setRowNotFound:
            throw SheetWriterError.setRowNotFound(exerciseName: request.exerciseName, setIndex: request.setIndex)
        case .notesColumnMissing:
            throw SheetWriterError.columnNotFound("Notes")
        }
    }
}

extension SetLogList {
    /// Overwrites the Set's token, refusing when the slot no longer holds the value the write was
    /// planned against so a concurrent edit conflicts rather than gets clobbered (ADR-0003).
    mutating func replaceToken(at position: Int, expecting expected: String, with value: String) throws {
        let current = token(at: position)
        guard current == expected else {
            throw SheetWriterError.unexpectedCurrentValue(expected: expected, actual: current)
        }
        setToken(value, at: position)
    }
}

struct SheetWritePlanningSnapshot: Sendable {
    let snapshot: SheetSnapshot
    let layout: SheetLayout

    fileprivate init(snapshot: SheetSnapshot, layout: SheetLayout) {
        self.snapshot = snapshot
        self.layout = layout
    }

    var grid: SheetGrid {
        snapshot.values
    }
}

struct SheetWritePlanner: Sendable {
    private let onLayoutBuilt: @Sendable () -> Void

    init(onLayoutBuilt: @escaping @Sendable () -> Void = {}) {
        self.onLayoutBuilt = onLayoutBuilt
    }

    func snapshot(for grid: SheetGrid) -> SheetWritePlanningSnapshot {
        snapshot(for: SheetSnapshot(values: grid))
    }

    func snapshot(for snapshot: SheetSnapshot) -> SheetWritePlanningSnapshot {
        onLayoutBuilt()
        return SheetWritePlanningSnapshot(snapshot: snapshot, layout: SheetLayoutInterpreter().interpret(snapshot))
    }

    func plan(_ request: SheetWriteRequest, in grid: SheetGrid) throws -> SheetCellUpdate {
        try plan(request, in: snapshot(for: grid))
    }

    func plan(_ request: SheetWriteRequest, in snapshot: SheetWritePlanningSnapshot) throws -> SheetCellUpdate {
        let target = try target(for: request, in: snapshot)
        return try plan(request, target: target, in: snapshot)
    }

    func target(for request: SheetWriteRequest, in snapshot: SheetWritePlanningSnapshot) throws -> SheetWriteTarget {
        let (row, col) = try addressing(for: request, in: snapshot).addressedCell(for: request)
        return SheetWriteTarget(tabName: request.blockTab, row: row, col: col)
    }

    func plan(
        _ request: SheetWriteRequest,
        target: SheetWriteTarget,
        in snapshot: SheetWritePlanningSnapshot
    ) throws -> SheetCellUpdate {
        let actual = snapshot.grid.cell(row: target.row, col: target.col).trimmed
        if let listValue = try setLogListCellValue(for: request, target: target, actual: actual, in: snapshot) {
            return SheetCellUpdate(tabName: target.tabName, row: target.row, col: target.col, value: listValue)
        }

        guard actual == request.expectedCurrentValue else {
            throw SheetWriterError.unexpectedCurrentValue(expected: request.expectedCurrentValue, actual: actual)
        }

        return SheetCellUpdate(
            tabName: target.tabName,
            row: target.row,
            col: target.col,
            value: request.writtenValue
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
        updated.write([[update.value]], atRow: update.row, col: update.col)
        return updated
    }

    func addressing(for request: SheetWriteRequest, in snapshot: SheetWritePlanningSnapshot) -> SheetWriteAddressing {
        let layout = snapshot.layout
        guard layout.week(number: request.week) != nil else { return .weekNotFound }
        guard let day = layout.day(week: request.week, day: request.day) else { return .dayNotFound }

        let (header, col): (String, Int?) =
            switch request.column {
            case .notes: ("Notes", day.columns.notes)
            case .lastSetRPE: ("Last set RPE", day.columns.lastSetRPE)
            }
        guard let col else { return .columnNotFound(header: header) }

        guard let anchor = day.exerciseAnchors.first(where: { $0.name == request.exerciseName }) else {
            return .exerciseNotFound
        }
        switch request.column {
        case .lastSetRPE:
            return .lastSetRPE(anchor: anchor, col: col)
        case .notes:
            return .setLog(
                anchor: anchor,
                anchor.setLogPlacement(for: request.setIndex, in: snapshot.snapshot, cols: day.columns)
            )
        }
    }

    /// The Notes-cell value a Set-Log list write produces, or nil when this Set owns its cell
    /// outright and the direct-write path applies. Three placement kinds share one comma-separated
    /// list cell — a multi-line Prescription Line's own Notes cell, Kevin's compact aggregate
    /// header, and the Visible Writable Row a protected header redirects to — and a Set is
    /// addressed within that cell by its list position.
    private func setLogListCellValue(
        for request: SheetWriteRequest,
        target: SheetWriteTarget,
        actual: String,
        in snapshot: SheetWritePlanningSnapshot
    ) throws -> String? {
        guard
            let placement = placement(for: request, target: target, in: snapshot),
            let position = placement.listPosition
        else { return nil }

        var list = SetLogList(cell: actual)
        try list.replaceToken(at: position, expecting: request.expectedCurrentValue, with: request.writtenValue)
        return list.cellValue
    }

    func placement(
        for request: SheetWriteRequest,
        target: SheetWriteTarget,
        in snapshot: SheetWritePlanningSnapshot
    ) -> SetLogPlacement? {
        guard
            case .setLog(_, .placed(let placement)) = addressing(for: request, in: snapshot),
            placement.row == target.row,
            placement.col == target.col
        else { return nil }
        return placement
    }
}
