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

        // Every remaining target is a Notes-column Set Log, so the one placement query decides it.
        return try anchor.setLogPlacement(for: request.setIndex, in: snapshot.snapshot, cols: day.columns)
            .addressedCell(for: request)
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

    /// The Set-Log placement for this request, but only when it lands on the given `target` cell.
    /// The list-value assembly and the diagnostics audit both read the Set's list position from this
    /// one placement rather than re-deriving the addressing tree; a target that does not match (e.g. a
    /// Last Set RPE cell) or an unresolvable placement yields nil so the caller falls through to the
    /// direct-write path.
    func placement(
        for request: SheetWriteRequest,
        target: SheetWriteTarget,
        in snapshot: SheetWritePlanningSnapshot
    ) -> SetLogPlacement? {
        guard
            let day = snapshot.layout.day(week: request.week, day: request.day),
            let anchor = day.exerciseAnchors.first(where: { $0.name == request.exerciseName }),
            case .placed(let placement) = anchor.setLogPlacement(
                for: request.setIndex,
                in: snapshot.snapshot,
                cols: day.columns
            ),
            placement.row == target.row,
            placement.col == target.col
        else { return nil }
        return placement
    }
}
