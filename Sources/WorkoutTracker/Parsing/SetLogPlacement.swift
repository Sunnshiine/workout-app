import Foundation

/// One prescription row of an Exercise. `setCount` is how many Sets this Line prescribes;
/// `firstSetIndex` is the running Set index of this Line's first Set within the Exercise, so
/// Line lookups and Set-Log addressing stay consistent across read and write.
struct PrescriptionLine: Sendable, Equatable {
    let row: Int
    let setCount: Int
    let firstSetIndex: Int
    /// A Drop line the app did not read before it read Drop lines: one whose Sets cell starts with
    /// no count. Another Set's Set Log may sit on its row,
    /// and a queued write names its Set by index, so its Sets come after every other Line's, in
    /// index and in row, and the Sets the app already had keep both.
    let addsADrop: Bool

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

    /// The Lines that do not add a Drop. They come first and keep the Set indices they had before the
    /// app read added Drops.
    var countedLines: [PrescriptionLine] { filter { !$0.addsADrop } }

    func line(containing setIndex: Int) -> PrescriptionLine? {
        first { $0.position(of: setIndex) != nil }
    }

    /// The Sets that Set `setIndex` counts among as these Lines read it now.
    func space(of setIndex: Int) -> SetIndexSpace {
        (line(containing: setIndex)?.addsADrop ?? false) ? .addedDrops : .counted
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
    /// The header Notes cell's Header Notes Role is a Coach Note or a Legacy Log, so the Set Log
    /// redirects to the first Visible Writable Row in the same Session.
    case occupiedHeaderVisibleWritableRow
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
    /// The header Notes cell's Header Notes Role is a Coach Note or a Legacy Log, and no Visible
    /// Writable Row exists before the next Exercise — the write must conflict rather than overwrite
    /// (ADR-0003, ADR-0005).
    case occupiedHeaderBlocksSetRow
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
            setCount: prescribedSetCount(in: grid, cols: cols)
        )
    }

    func prescribedSetCount(in grid: SheetGrid, cols: DayColumns) -> Int {
        PrescriptionRow(row: row, in: grid, cols: cols).setsCellCount ?? 1
    }

    /// The Prescription Lines that make up this Exercise. Line 0 is always the anchor row. Each
    /// visible blank-name continuation row inside the Exercise span that `PrescriptionRow` reads as
    /// a Line is another (coach J. Alarcon's one-line-per-row template, and a coach's Drop line). A
    /// row the coach hid prescribes nothing here. Lines that add a Drop follow every other Line,
    /// whatever row they sit on. From the first one with no row left for its Set Logs, none is read,
    /// as before, so an added Drop the app reads never changes index.
    ///
    /// Kevin's template returns exactly one Line: his continuation rows hold Set Logs in the
    /// Notes column with an empty Sets cell and no Drop, so they never qualify, keeping that path
    /// (`isMultiLine == false`) on the existing single-anchor logic.
    func prescriptionLines(in snapshot: SheetSnapshot, cols: DayColumns) -> [PrescriptionLine] {
        let grid = snapshot.values
        let anchorSetCount = prescribedSetCount(in: grid, cols: cols)
        let continuations = ownVisibleRows(from: row + 1, before: nextAnchorRow, in: snapshot).compactMap { lineRow in
            let reading = PrescriptionRow(row: lineRow, in: grid, cols: cols)
            return reading.lineSetCount.map {
                PrescriptionLine(row: lineRow, setCount: $0, firstSetIndex: 0, addsADrop: reading.setsCellCount == nil)
            }
        }
        let ordered =
            [PrescriptionLine(row: row, setCount: anchorSetCount, firstSetIndex: 0, addsADrop: false)]
            + continuations.filter { !$0.addsADrop } + continuations.filter(\.addsADrop)
        let lines = Self.numbered(ordered)
        guard let col = cols.notes else { return lines.countedLines }
        let dropRows = addedDropRows(lines: lines, in: snapshot, cols: cols, col: col)
        return lines.countedLines + lines.filter(\.addsADrop).prefix { dropRows[$0.row] != nil }
    }

    private static func numbered(_ lines: [PrescriptionLine]) -> [PrescriptionLine] {
        var nextFirstSetIndex = 0
        return lines.map { line in
            defer { nextFirstSetIndex += line.setCount }
            return PrescriptionLine(row: line.row, setCount: line.setCount, firstSetIndex: nextFirstSetIndex, addsADrop: line.addsADrop)
        }
    }

    private func ownVisibleRows(from firstRow: Int, before endRow: Int, in snapshot: SheetSnapshot) -> [Int] {
        guard firstRow < endRow else { return [] }
        return (firstRow..<endRow).filter { snapshot.isRowVisible($0) }
    }

    /// The rows inside this Exercise's span that can carry a Set Log, in sheet order, without hidden
    /// rows. A compact header keeps Set Logs on the anchor row itself; every other rule starts on the
    /// row below it. Set N takes the Nth of these, so "which
    /// row is Set N on" and "which row does an occupied header redirect to" read the same list.
    func visibleSetLogRows(headerHoldsSetLogs: Bool, in snapshot: SheetSnapshot) -> [Int] {
        ownVisibleRows(from: row + (headerHoldsSetLogs ? 0 : 1), before: nextAnchorRow, in: snapshot)
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
    /// Note sends it to) → compact-header list → occupied-header Visible Writable Row → visible
    /// Set-log row — honouring Coach Note / Legacy
    /// Log protection and never crossing the Session boundary (ADR-0003, ADR-0010). Set-Log placement
    /// is a Notes-column concern; Last Set RPE targeting stays on the Exercise anchor row and is not
    /// resolved here. This is the one query the read, write, and audit paths ask, so display and
    /// write targeting cannot diverge.
    ///
    /// A queued write passes `space`, the Sets its index counted among when it was queued. A
    /// counted Set's write then takes the address it had before the app read added Drops, and an
    /// added Drop's write is refused when no added Drop read now has its index, so neither lands on
    /// the other's row after the coach changes a Sets count. A read passes nil and takes the Sets
    /// as the Sheet numbers them now.
    func setLogPlacement(
        for setIndex: Int,
        among space: SetIndexSpace? = nil,
        in snapshot: SheetSnapshot,
        cols: DayColumns
    ) -> SetLogPlacementResolution {
        guard let col = cols.notes else { return .notesColumnMissing }

        let lines = prescriptionLines(in: snapshot, cols: cols)
        switch space ?? lines.space(of: setIndex) {
        case .addedDrops:
            return addedDropPlacement(for: setIndex, lines: lines, in: snapshot, cols: cols, col: col)
        case .counted:
            return countedPlacement(for: setIndex, lines: lines.countedLines, in: snapshot, cols: cols, col: col)
        }
    }

    /// Where a counted Line's Set lives: the addressing the Exercise had before it read added Drops.
    private func countedPlacement(
        for setIndex: Int,
        lines: [PrescriptionLine],
        in snapshot: SheetSnapshot,
        cols: DayColumns,
        col: Int
    ) -> SetLogPlacementResolution {
        let grid = snapshot.values
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
            return role.holdsSetLogs ? .setRowNotFound : .occupiedHeaderBlocksSetRow
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

        guard let writableRow = firstVisibleWritableRow(in: snapshot) else { return .occupiedHeaderBlocksSetRow }
        return .placed(
            SetLogPlacement(
                kind: .occupiedHeaderVisibleWritableRow,
                row: writableRow,
                col: col,
                listPosition: listPosition
            )
        )
    }

    /// An added Drop's Sets take its own row's Notes, or the next spare row when a counted Set or an
    /// earlier added Drop already holds that row, or when its Notes hold a Coach Note.
    private func addedDropPlacement(
        for setIndex: Int,
        lines: [PrescriptionLine],
        in snapshot: SheetSnapshot,
        cols: DayColumns,
        col: Int
    ) -> SetLogPlacementResolution {
        guard let addition = lines.line(containing: setIndex), addition.addsADrop else { return .setRowNotFound }
        guard
            let position = addition.position(of: setIndex),
            let row = addedDropRows(lines: lines, in: snapshot, cols: cols, col: col)[addition.row]
        else { return .occupiedHeaderBlocksSetRow }
        return .placed(
            SetLogPlacement(
                kind: row == addition.row ? .multiLinePrescriptionLine : .protectedLineVisibleWritableRow,
                row: row,
                col: col,
                listPosition: SetLogPlacement.listPosition(ofSet: position, amongPrescribed: addition.setCount)
            )
        )
    }

    /// The row each added Drop line's Set Logs take, keyed by the Line's own row. A Drop takes its
    /// own row unless its Notes hold a Coach Note. Otherwise it takes the next free row of its
    /// Exercise that holds no Coach Note.
    private func addedDropRows(lines: [PrescriptionLine], in snapshot: SheetSnapshot, cols: DayColumns, col: Int) -> [Int: Int] {
        var taken = countedRows(lines.countedLines, in: snapshot, cols: cols, col: col)
        var rows: [Int: Int] = [:]
        for line in lines where line.addsADrop {
            guard let row = candidateRows(for: line, lines: lines, in: snapshot, cols: cols).first(where: { !taken.contains($0) })
            else { continue }
            taken.insert(row)
            rows[line.row] = row
        }
        return rows
    }

    /// The rows an added Drop line may take, in the order it tries them.
    private func candidateRows(
        for line: PrescriptionLine,
        lines: [PrescriptionLine],
        in snapshot: SheetSnapshot,
        cols: DayColumns
    ) -> [Int] {
        let grid = snapshot.values
        let ownRowIsProtected = line.notesRole(in: grid, cols: cols).coachNote != nil
        let spareRows = ownVisibleRows(from: row + 1, before: nextAnchorRow, in: snapshot).filter { spare in
            !lines.contains { $0.row == spare }
                && HeaderNotesRole(notesCell: grid.cellOrEmpty(spare, cols.notes).trimmed, setCount: line.setCount).coachNote == nil
        }
        return (ownRowIsProtected ? [] : [line.row]) + spareRows
    }

    private func countedRows(_ counted: [PrescriptionLine], in snapshot: SheetSnapshot, cols: DayColumns, col: Int) -> Set<Int> {
        let setCount = counted.reduce(0) { $0 + $1.setCount }
        return Set(
            (0..<setCount).compactMap { index -> Int? in
                guard case .placed(let placement) = countedPlacement(for: index, lines: counted, in: snapshot, cols: cols, col: col)
                else { return nil }
                return placement.row
            }
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
        guard spareRows.indices.contains(rank) else { return .occupiedHeaderBlocksSetRow }
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
