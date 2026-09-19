import Foundation

private nonisolated(unsafe) let legacyLogTokenPattern =
    /^(?:BW|\d+(?:\.\d+)?)(?:(?:x\d+)|(?:@\d+(?:\.\d+)?))(?:@\d+(?:\.\d+)?)?$/
private nonisolated(unsafe) let legacyNumberTokenPattern = /^\d+(?:\.\d+)?$/

struct WeekSection: Sendable {
    let headerRow: Int  // 0-based row holding "Day N"
    let roleHeaderRow: Int  // headerRow + 2
    let dateRow: Int  // headerRow + 1
    let dayStartCols: [Int]  // 0-based columns of Day 1..Day 4
}

struct DayColumns: Sendable {
    let name: Int
    let sets: Int?
    let reps: Int?
    let percentOneRM: Int?
    let load: Int?
    let lastSetRPE: Int?
    let notes: Int?
    let span: Range<Int>  // [dayStart, nextDayStart)
}

struct SheetLayout: Sendable {
    let weeks: [SheetLayoutWeek]

    func week(number: Int) -> SheetLayoutWeek? {
        weeks.first { $0.number == number }
    }

    func day(week weekNumber: Int, day dayNumber: Int) -> SheetLayoutDay? {
        week(number: weekNumber)?.days.first { $0.number == dayNumber }
    }
}

struct SheetLayoutWeek: Sendable {
    let number: Int
    let headerRow: Int
    let roleHeaderRow: Int
    let dateRow: Int
    let endRow: Int
    let dayStartCols: [Int]
    let days: [SheetLayoutDay]

    var section: WeekSection {
        WeekSection(
            headerRow: headerRow,
            roleHeaderRow: roleHeaderRow,
            dateRow: dateRow,
            dayStartCols: dayStartCols
        )
    }
}

struct SheetLayoutDay: Sendable {
    let number: Int
    let columns: DayColumns
    let exerciseAnchors: [SheetLayoutExerciseAnchor]
}

/// What kind of content occupies one Notes cell — the Exercise's header cell or a Prescription
/// Line's own cell. The three cases are mutually exclusive, so a cell can never be read as both
/// compact Set-Log content and coach-authored prose. Decided once, Set-count-aware, from the cell
/// value and the number of Sets that cell is prescribed to carry; the read, write, and audit paths
/// all consume this one answer (ADR-0005, ADR-0010).
enum HeaderNotesRole: Sendable, Equatable {
    /// The cell carries this Exercise's or Line's Set Logs: empty, one Set-Log-list value, or a
    /// comma list no longer than the prescribed Set count whose every entry is one ("25x12@7, skip").
    case setLogList
    /// Instruction-shaped coach prose. Read-only, never overwritten.
    case coachNote(String)
    /// Result-shaped completion evidence from older exercise-level logging. Read-only, kept as the
    /// raw entered text.
    case legacyLog(String)

    init(notesCell value: String, setCount: Int) {
        if SetLogToken.isSetLogListValue(value)
            || SetLogToken.isCompactAggregateHeader(value, setCount: setCount)
        {
            self = .setLogList
        } else if isLegacyLogValue(value) {
            self = .legacyLog(value)
        } else {
            self = .coachNote(value)
        }
    }

    /// Whether Set Logs may be read out of and written into this cell. The complement is coach
    /// content: Set Logs redirect to the next Visible Writable Row and the cell is never overwritten.
    var holdsSetLogs: Bool { self == .setLogList }

    var coachNote: String? {
        guard case .coachNote(let value) = self else { return nil }
        return value
    }

    var legacyLog: String? {
        guard case .legacyLog(let value) = self else { return nil }
        return value
    }
}

private func isLegacyLogValue(_ value: String) -> Bool {
    let tokens =
        value
        .split(separator: ",", omittingEmptySubsequences: true)
        .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
    guard !tokens.isEmpty else { return false }
    return tokens.allSatisfy { token in
        token.wholeMatch(of: legacyLogTokenPattern) != nil
            || token.wholeMatch(of: legacyNumberTokenPattern) != nil
    }
}

func splitSheetNotesList(_ value: String) -> [String] {
    value
        .split(separator: ",", omittingEmptySubsequences: false)
        .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
}

func joinedSheetNotesList(_ values: [String]) -> String {
    var trimmed = values.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
    while trimmed.last?.isEmpty == true {
        trimmed.removeLast()
    }
    return trimmed.joined(separator: ", ")
}

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

    /// What occupies this Line's own Notes cell, classified against the Sets this Line prescribes.
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

/// Which rule decided where Set N's Set Log lives — the four leaves of the Visible Writable Row
/// addressing tree (`CONTEXT.md`, ADR-0003, ADR-0010). Naming the outcome lets read, write, and
/// audit consume one decision instead of re-branching the tree apiece.
enum SetLogPlacementKind: Sendable, Equatable {
    /// Coach J. Alarcon's per-row template: the Set belongs to a multi-line Prescription Line and
    /// its log lives comma-separated in that Line's own Notes cell.
    case multiLinePrescriptionLine
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

    /// What occupies this Exercise's header Notes cell, classified against its prescribed Set count.
    /// This is the one place the question is answered; the single-line read, the multi-line read,
    /// the placement tree, and the write and audit paths all ask here, so the header cannot be
    /// interpreted as Set-Log content on one path and as coach content on another.
    func headerNotesRole(in grid: SheetGrid, cols: DayColumns) -> HeaderNotesRole {
        HeaderNotesRole(
            notesCell: grid.cellOrEmpty(row, cols.notes).trimmed,
            setCount: prescribedSetCount(in: grid, setsColumn: cols.sets)
        )
    }

    func prescribedSetCount(in grid: SheetGrid, setsColumn: Int?) -> Int {
        let rawValue = setsColumn.map { grid.cell(row: row, col: $0).trimmed } ?? ""
        return max(Int(rawValue.prefix { $0.isNumber }) ?? 1, 1)
    }

    /// The Prescription Lines that make up this Exercise. Line 0 is always the anchor
    /// row; each blank-name continuation row inside the Exercise span whose Sets cell is a
    /// non-empty number is an additional Line (coach J. Alarcon's one-line-per-row template).
    ///
    /// Kevin's template returns exactly one Line: his continuation rows hold Set Logs in the
    /// Notes column with an empty Sets cell, so they never qualify — keeping that path
    /// (`isMultiLine == false`) on the existing single-anchor logic.
    func prescriptionLines(in grid: SheetGrid, setsColumn: Int?) -> [PrescriptionLine] {
        func numericSetCount(at lineRow: Int) -> Int? {
            guard let setsColumn else { return nil }
            let digits = grid.cell(row: lineRow, col: setsColumn).trimmed.prefix { $0.isNumber }
            guard let value = Int(digits) else { return nil }
            return max(value, 1)
        }

        var lines = [PrescriptionLine(row: row, setCount: numericSetCount(at: row) ?? 1, firstSetIndex: 0)]
        var nextFirstSetIndex = lines[0].setCount
        for continuationRow in (row + 1)..<nextAnchorRow {
            guard let setCount = numericSetCount(at: continuationRow) else { continue }
            lines.append(
                PrescriptionLine(row: continuationRow, setCount: setCount, firstSetIndex: nextFirstSetIndex)
            )
            nextFirstSetIndex += setCount
        }
        return lines
    }

    func continuationSetRow(for setIndex: Int) -> Int? {
        setLogRow(for: setIndex, compactHeaderSetOne: false)
    }

    func setLogRow(for setIndex: Int, compactHeaderSetOne: Bool) -> Int? {
        guard setIndex >= 0 else { return nil }
        let rowOffset = compactHeaderSetOne ? setIndex : setIndex + 1
        let setRow = row + rowOffset
        guard setRow < nextAnchorRow else { return nil }
        return setRow
    }

    /// The rows inside this Exercise's span that can carry a Set Log, in sheet order, with hidden
    /// rows dropped. A compact header keeps Set Logs on the anchor row itself; every other rule
    /// starts on the row below it. Set N takes the Nth of these, so "which row is Set N on" and
    /// "which row does a protected header redirect to" read the same list.
    func visibleSetLogRows(compactHeaderSetOne: Bool, in snapshot: SheetSnapshot) -> [Int] {
        let firstRow = row + (compactHeaderSetOne ? 0 : 1)
        guard firstRow < nextAnchorRow else { return [] }
        return (firstRow..<nextAnchorRow).filter { snapshot.isRowVisible($0) }
    }

    func visibleSetLogRow(for setIndex: Int, compactHeaderSetOne: Bool, in snapshot: SheetSnapshot) -> Int? {
        let rows = visibleSetLogRows(compactHeaderSetOne: compactHeaderSetOne, in: snapshot)
        return rows.indices.contains(setIndex) ? rows[setIndex] : nil
    }

    func firstVisibleWritableRow(in snapshot: SheetSnapshot) -> Int? {
        visibleSetLogRows(compactHeaderSetOne: false, in: snapshot).first
    }

    /// Resolves where Set `setIndex`'s Set Log lives for this Exercise: the whole Visible Writable
    /// Row addressing tree in one place — multi-line Prescription Line → compact-header list →
    /// protected-header Visible Writable Row → visible Set-log row — honouring Coach Note / Legacy
    /// Log protection and never crossing the Session boundary (ADR-0003, ADR-0010). Set-Log placement
    /// is a Notes-column concern; Last Set RPE targeting stays on the Exercise anchor row and is not
    /// resolved here. This is the one query the read, write, and audit paths ask, so display and
    /// write targeting cannot diverge.
    func setLogPlacement(for setIndex: Int, in snapshot: SheetSnapshot, cols: DayColumns) -> SetLogPlacementResolution {
        let grid = snapshot.values
        guard let col = cols.notes else { return .notesColumnMissing }

        let lines = prescriptionLines(in: grid, setsColumn: cols.sets)
        if lines.isMultiLine {
            return multiLinePlacement(for: setIndex, lines: lines, col: col)
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
            let setRow = visibleSetLogRow(for: setIndex, compactHeaderSetOne: role.holdsSetLogs, in: snapshot)
        else {
            return role.holdsSetLogs ? .setRowNotFound : .protectedHeaderBlocksSetRow
        }
        return .placed(SetLogPlacement(kind: .visibleSetLogRow, row: setRow, col: col, listPosition: nil))
    }

    /// What this Exercise's header Notes cell does with a prescribed Set's log. A `.setLogList`
    /// header holds it in the cell's own comma-separated list; a Coach Note or Legacy Log protects
    /// the cell (ADR-0005) and redirects the log to the first Visible Writable Row below, refusing
    /// the write when there is none. nil when the Set is past the prescribed count, so the header
    /// makes no claim on it and it falls through to its own visible row.
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
    /// prescribes it and its position within that Line.
    private func multiLinePlacement(
        for setIndex: Int,
        lines: [PrescriptionLine],
        col: Int
    ) -> SetLogPlacementResolution {
        guard let line = lines.line(containing: setIndex) else { return .setRowNotFound }
        return .placed(
            SetLogPlacement(
                kind: .multiLinePrescriptionLine,
                row: line.row,
                col: col,
                listPosition: line.position(of: setIndex)
            )
        )
    }
}

struct SheetLayoutInterpreter: Sendable {
    func interpret(_ snapshot: SheetSnapshot) -> SheetLayout {
        interpret(snapshot.values)
    }

    func interpret(_ grid: SheetGrid) -> SheetLayout {
        let sections = locateWeekSections(in: grid)
        let weeks = sections.enumerated().map { index, section in
            let endRow = index + 1 < sections.count ? sections[index + 1].headerRow : grid.count
            let firstBodyRow = section.roleHeaderRow + 1
            let upper = min(endRow, grid.count)
            let bodyRows = firstBodyRow..<max(firstBodyRow, upper)
            let days = section.dayStartCols.indices.map { dayIndex in
                let columns = resolveDayColumns(
                    in: grid,
                    section: section,
                    dayIndex: dayIndex,
                    bodyRows: bodyRows
                )
                let anchors = exerciseAnchors(
                    in: grid,
                    cols: columns,
                    firstRow: firstBodyRow,
                    upper: upper
                )
                return SheetLayoutDay(
                    number: dayIndex + 1,
                    columns: columns,
                    exerciseAnchors: anchors
                )
            }
            return SheetLayoutWeek(
                number: index + 1,
                headerRow: section.headerRow,
                roleHeaderRow: section.roleHeaderRow,
                dateRow: section.dateRow,
                endRow: endRow,
                dayStartCols: section.dayStartCols,
                days: Array(days)
            )
        }
        return SheetLayout(weeks: weeks)
    }
}

// Any "Day N" header (1-indexed, no upper bound) so 2–6 day programs all parse; the count of
// detected headers drives every downstream day count (ADR-0003 — never hardcode the layout).
private nonisolated(unsafe) let sheetLayoutDayHeaderPattern = /^Day \d+$/

/// Resolves role columns by scanning the role-header row within the day's span.
/// Columns are never hardcoded (ADR 0003). `bodyRows` is the day's exercise-row range,
/// used only to disambiguate a role header that is repeated across columns; the empty
/// default (`0..<0`) skips disambiguation and returns the first matching column.
func resolveDayColumns(
    in grid: SheetGrid,
    section: WeekSection,
    dayIndex: Int,
    bodyRows: Range<Int> = 0..<0
) -> DayColumns {
    let starts = section.dayStartCols
    let start = starts[dayIndex]
    let end =
        dayIndex + 1 < starts.count
        ? starts[dayIndex + 1]
        : start + (starts.count > 1 ? starts[1] - starts[0] : 16)
    let span = start..<end

    func find(_ label: String) -> Int? {
        let matches = span.filter {
            grid.cell(row: section.roleHeaderRow, col: $0).caseInsensitiveCompare(label) == .orderedSame
        }
        guard matches.count > 1 else { return matches.first }
        // A coach sheet can repeat a role header across adjacent columns where only one
        // carries data (e.g. a stray duplicate "Sets" header). Prefer the column with
        // values in the day's body; fall back to the first match.
        return matches.first { col in
            bodyRows.contains { !grid.cell(row: $0, col: col).trimmed.isEmpty }
        } ?? matches.first
    }
    return DayColumns(
        name: start,
        sets: find("Sets"),
        reps: find("Reps"),
        percentOneRM: find("%1RM"),
        load: find("Load"),
        lastSetRPE: find("Last set RPE"),
        notes: find("Notes"),
        span: span
    )
}

func locateWeekSections(in grid: SheetGrid) -> [WeekSection] {
    var byRow: [Int: [Int]] = [:]
    for row in 0..<grid.count {
        for col in 0..<grid[row].count where isSheetLayoutDayHeader(grid[row][col]) {
            byRow[row, default: []].append(col)
        }
    }
    return byRow.keys.sorted().compactMap { row in
        guard let cols = byRow[row]?.sorted(), !cols.isEmpty else { return nil }
        return WeekSection(headerRow: row, roleHeaderRow: row + 2, dateRow: row + 1, dayStartCols: cols)
    }
}

func anchorRows(in grid: SheetGrid, cols: DayColumns, firstRow: Int, upper: Int) -> [Int] {
    guard firstRow < upper else { return [] }

    var rows: [Int] = []
    for row in firstRow..<upper {
        if isSheetLayoutDayHeader(grid.cell(row: row, col: cols.name)) { break }
        if !grid.cell(row: row, col: cols.name).trimmed.isEmpty { rows.append(row) }
    }
    return rows
}

private func exerciseAnchors(
    in grid: SheetGrid,
    cols: DayColumns,
    firstRow: Int,
    upper: Int
) -> [SheetLayoutExerciseAnchor] {
    let rows = anchorRows(in: grid, cols: cols, firstRow: firstRow, upper: upper)
    return rows.enumerated().map { index, row in
        SheetLayoutExerciseAnchor(
            name: grid.cell(row: row, col: cols.name).trimmed,
            row: row,
            nextAnchorRow: index + 1 < rows.count ? rows[index + 1] : upper
        )
    }
}

private func isSheetLayoutDayHeader(_ value: String) -> Bool {
    value.wholeMatch(of: sheetLayoutDayHeaderPattern) != nil
}
