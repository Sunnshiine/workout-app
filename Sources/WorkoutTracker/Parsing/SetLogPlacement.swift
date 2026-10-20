import Foundation

/// One prescription row of an Exercise. `setCount` is how many Sets this Line prescribes;
/// `firstSetIndex` is the running Set index of this Line's first Set within the Exercise, so
/// Line lookups and Set-Log addressing stay consistent across read and write.
struct PrescriptionLine: Sendable, Equatable {
    let row: Int
    let setCount: Int
    let firstSetIndex: Int

    /// The zero-based position of Set `setIndex` within this Line's own Set-Log list, or nil
    /// when the Set does not belong to this Line.
    func position(of setIndex: Int) -> Int? {
        let local = setIndex - firstSetIndex
        return (0..<setCount).contains(local) ? local : nil
    }

    func notesRole(in grid: SheetGrid, cols: DayColumns) -> HeaderNotesRole {
        HeaderNotesRole(notesCell: grid.cellOrEmpty(row, cols.notes).trimmed, setCount: setCount)
    }
}

extension Array where Element == PrescriptionLine {
    /// Exercises authored as more than one Prescription Line use the per-line Set model;
    /// a single Line means the existing single-anchor (Kevin) path applies.
    var isMultiLine: Bool { count > 1 }

    func line(containing setIndex: Int) -> PrescriptionLine? {
        first { $0.position(of: setIndex) != nil }
    }
}

/// Which rule decided where Set N's Set Log lives — the five leaves of the Visible Writable Row
/// addressing tree (`CONTEXT.md`, ADR-0003, ADR-0010). Naming the outcome lets read, write, and
/// audit consume one decision instead of re-branching the tree apiece.
enum SetLogPlacementKind: Sendable, Equatable {
    /// Coach J. Alarcon's per-row template: the Set belongs to a multi-line Prescription Line and
    /// its log lives comma-separated in that Line's own Notes cell.
    case multiLinePrescriptionLine
    /// The Set's multi-line Prescription Line holds a Coach Note in its Notes cell, so the Line's
    /// Set Logs move to a Visible Writable Row in the Exercise's span that is not itself a Line.
    case protectedLineVisibleWritableRow
    /// Kevin's compact template: the Exercise stores its Set Logs comma-separated in the one header
    /// Notes cell (compact Set-One / aggregate header).
    case compactHeaderList
    /// The header Notes cell holds protected coach content (a Coach Note or Legacy Log), so the Set
    /// Log redirects to the first Visible Writable Row in the same Session.
    case protectedHeaderVisibleWritableRow
    /// The Set log lives on its own visible per-Set row below the anchor.
    case visibleSetLogRow
}

/// Where Set N's Set Log lives, resolved in domain terms: the addressing `kind`, the resolved `row`
/// and `col`, and — for list kinds — the Set's `listPosition` within the comma-separated Set-Log
/// list (nil when the row holds a single value). The row/column/A1 detail stays transient here and
/// is never cached (ADR-0003).
struct SetLogPlacement: Sendable, Equatable {
    let kind: SetLogPlacementKind
    let row: Int
    let col: Int
    let listPosition: Int?

    /// Set `setIndex`'s position in a Notes cell shared by `setCount` prescribed Sets. A single
    /// prescribed Set has no comma list, so its placement addresses the cell whole — a nil position
    /// takes the direct-write path on both the read and the write side.
    static func listPosition(ofSet setIndex: Int, amongPrescribed setCount: Int) -> Int? {
        setCount > 1 ? setIndex : nil
    }
}

/// The outcome of resolving where one Set's Set Log lives — either a resolved `SetLogPlacement`, or
/// a reason the Set has no writable row. The write path maps these to its conflict / not-found
/// errors so the "conflict rather than guess" failure mode (ADR-0003) is decided in one place.
enum SetLogPlacementResolution: Sendable, Equatable {
    case placed(SetLogPlacement)
    /// The header Notes cell holds protected coach content and no safe Visible Writable Row exists
    /// before the next Exercise — the write must conflict rather than overwrite (ADR-0003, ADR-0005).
    case protectedHeaderBlocksSetRow
    /// The Set has no row in the Exercise's span (out of range or hidden).
    case setRowNotFound
    /// The day has no Notes column, so Set Logs cannot be placed at all.
    case notesColumnMissing
}

struct SheetLayoutExerciseAnchor: Sendable {
    let name: String
    let row: Int
    let nextAnchorRow: Int

    func headerNotesRole(in grid: SheetGrid, cols: DayColumns) -> HeaderNotesRole {
        HeaderNotesRole(
            notesCell: grid.cellOrEmpty(row, cols.notes).trimmed,
            setCount: prescribedSetCount(in: grid, setsColumn: cols.sets)
        )
    }

    /// The most Sets one Prescription Line can prescribe. A larger Sets cell is a typo, and is
    /// read like a non-numeric one, so it cannot make sync build a Set per count (#686).
    private static let maxSetsPerLine = 99

    func prescribedSetCount(in grid: SheetGrid, setsColumn: Int?) -> Int {
        setCount(at: row, in: grid, setsColumn: setsColumn) ?? 1
    }

    /// The Sets cell on `lineRow` as a count of at least one, or nil when the cell holds no number
    /// or a number past `maxSetsPerLine`.
    private func setCount(at lineRow: Int, in grid: SheetGrid, setsColumn: Int?) -> Int? {
        guard let setsColumn else { return nil }
        let digits = grid.cell(row: lineRow, col: setsColumn).trimmed.prefix { $0.isNumber }
        guard let value = Int(digits), value <= Self.maxSetsPerLine else { return nil }
        return max(value, 1)
    }

    /// The Prescription Lines that make up this Exercise. Line 0 is always the anchor
    /// row; each blank-name continuation row inside the Exercise span whose Sets cell is a
    /// number up to `maxSetsPerLine` is an additional Line (coach J. Alarcon's one-line-per-row template).
    /// A row the coach hid prescribes nothing.
    ///
    /// Kevin's template returns exactly one Line: his continuation rows hold Set Logs in the
    /// Notes column with an empty Sets cell, so they never qualify — keeping that path
    /// (`isMultiLine == false`) on the existing single-anchor logic.
    func prescriptionLines(in snapshot: SheetSnapshot, setsColumn: Int?) -> [PrescriptionLine] {
        let grid = snapshot.values
        let anchorSetCount = prescribedSetCount(in: grid, setsColumn: setsColumn)
        var lines = [PrescriptionLine(row: row, setCount: anchorSetCount, firstSetIndex: 0)]
        var nextFirstSetIndex = anchorSetCount
        for continuationRow in (row + 1)..<nextAnchorRow where snapshot.isRowVisible(continuationRow) {
            guard let lineSetCount = setCount(at: continuationRow, in: grid, setsColumn: setsColumn) else { continue }
            lines.append(
                PrescriptionLine(row: continuationRow, setCount: lineSetCount, firstSetIndex: nextFirstSetIndex)
            )
            nextFirstSetIndex += lineSetCount
        }
        return lines
    }

    /// The rows inside this Exercise's span that can carry a Set Log, in sheet order, with hidden
    /// rows dropped. A compact header keeps Set Logs on the anchor row itself; every other rule
    /// starts on the row below it. Set N takes the Nth of these, so "which row is Set N on" and
    /// "which row does a protected header redirect to" read the same list.
    func visibleSetLogRows(headerHoldsSetLogs: Bool, in snapshot: SheetSnapshot) -> [Int] {
        let firstRow = row + (headerHoldsSetLogs ? 0 : 1)
        guard firstRow < nextAnchorRow else { return [] }
        return (firstRow..<nextAnchorRow).filter { snapshot.isRowVisible($0) }
    }

    func visibleSetLogRow(for setIndex: Int, headerHoldsSetLogs: Bool, in snapshot: SheetSnapshot) -> Int? {
        let rows = visibleSetLogRows(headerHoldsSetLogs: headerHoldsSetLogs, in: snapshot)
        return rows.indices.contains(setIndex) ? rows[setIndex] : nil
    }

    func firstVisibleWritableRow(in snapshot: SheetSnapshot) -> Int? {
        visibleSetLogRows(headerHoldsSetLogs: false, in: snapshot).first
    }

    /// Resolves where Set `setIndex`'s Set Log lives for this Exercise: the whole Visible Writable
    /// Row addressing tree in one place — multi-line Prescription Line (or the spare row its Coach
    /// Note sends it to) → compact-header list → protected-header Visible Writable Row → visible
    /// Set-log row — honouring Coach Note / Legacy
    /// Log protection and never crossing the Session boundary (ADR-0003, ADR-0010). Set-Log placement
    /// is a Notes-column concern; Last Set RPE targeting stays on the Exercise anchor row and is not
    /// resolved here. This is the one query the read, write, and audit paths ask, so display and
    /// write targeting cannot diverge.
    func setLogPlacement(for setIndex: Int, in snapshot: SheetSnapshot, cols: DayColumns) -> SetLogPlacementResolution {
        let grid = snapshot.values
        guard let col = cols.notes else { return .notesColumnMissing }

        let lines = prescriptionLines(in: snapshot, setsColumn: cols.sets)
        if lines.isMultiLine {
            return multiLinePlacement(for: setIndex, lines: lines, in: snapshot, cols: cols, col: col)
        }

        let line = lines[0]
        let role = line.notesRole(in: grid, cols: cols)
        if let headerPlacement = headerNotesPlacement(
            for: setIndex,
            role: role,
            setCount: line.setCount,
            in: snapshot,
            col: col
        ) {
            return headerPlacement
        }

        guard
            let setRow = visibleSetLogRow(for: setIndex, headerHoldsSetLogs: role.holdsSetLogs, in: snapshot)
        else {
            return role.holdsSetLogs ? .setRowNotFound : .protectedHeaderBlocksSetRow
        }
        return .placed(SetLogPlacement(kind: .visibleSetLogRow, row: setRow, col: col, listPosition: nil))
    }

    private func headerNotesPlacement(
        for setIndex: Int,
        role: HeaderNotesRole,
        setCount: Int,
        in snapshot: SheetSnapshot,
        col: Int
    ) -> SetLogPlacementResolution? {
        guard setIndex < setCount else { return nil }
        let listPosition = SetLogPlacement.listPosition(ofSet: setIndex, amongPrescribed: setCount)

        if role.holdsSetLogs {
            guard snapshot.isRowVisible(row) else { return .setRowNotFound }
            return .placed(
                SetLogPlacement(kind: .compactHeaderList, row: row, col: col, listPosition: listPosition)
            )
        }

        guard let writableRow = firstVisibleWritableRow(in: snapshot) else { return .protectedHeaderBlocksSetRow }
        return .placed(
            SetLogPlacement(
                kind: .protectedHeaderVisibleWritableRow,
                row: writableRow,
                col: col,
                listPosition: listPosition
            )
        )
    }

    /// Coach J. Alarcon's per-row template (ADR-0010): each Prescription Line keeps its own Sets'
    /// logs comma-separated in that Line's Notes cell, so a Set is addressed by the Line that
    /// prescribes it and its position within that Line. A Line whose Notes cell holds a Coach Note
    /// keeps that list on a spare row instead. A Legacy Log keeps its Line's cell, so the writer's
    /// value check refuses the write rather than log the Line a second time elsewhere.
    private func multiLinePlacement(
        for setIndex: Int,
        lines: [PrescriptionLine],
        in snapshot: SheetSnapshot,
        cols: DayColumns,
        col: Int
    ) -> SetLogPlacementResolution {
        guard let line = lines.line(containing: setIndex), let position = line.position(of: setIndex) else {
            return .setRowNotFound
        }
        let coachNoteLines = lines.filter { $0.notesRole(in: snapshot.values, cols: cols).coachNote != nil }
        guard let rank = coachNoteLines.firstIndex(of: line) else {
            return .placed(
                SetLogPlacement(kind: .multiLinePrescriptionLine, row: line.row, col: col, listPosition: position)
            )
        }
        let spareRows = visibleSetLogRows(headerHoldsSetLogs: false, in: snapshot).filter { row in
            !lines.contains { $0.row == row }
        }
        guard spareRows.indices.contains(rank) else { return .protectedHeaderBlocksSetRow }
        return .placed(
            SetLogPlacement(
                kind: .protectedLineVisibleWritableRow,
                row: spareRows[rank],
                col: col,
                listPosition: SetLogPlacement.listPosition(ofSet: position, amongPrescribed: line.setCount)
            )
        )
    }
}
