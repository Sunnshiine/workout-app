import Foundation

private nonisolated(unsafe) let legacyLogTokenPattern =
    /^(?:BW|\d+(?:\.\d+)?)(?:(?:x\d+)|(?:@\d+(?:\.\d+)?))(?:@\d+(?:\.\d+)?)?$/
private nonisolated(unsafe) let legacyNumberTokenPattern = /^\d+(?:\.\d+)?$/

enum IgnoredDayHeader: Sendable, Equatable {
    case repeated(dayNumber: Int)
    case outsideWeek(header: String)
}

struct DayHeader: Sendable {
    enum Reading: Sendable, Equatable {
        case session(Int)
        case ignored(IgnoredDayHeader)
    }

    let col: Int
    let reading: Reading
}

struct WeekSection: Sendable {
    let headerRow: Int  // 0-based row holding "Day N"
    let roleHeaderRow: Int  // headerRow + 2
    let dateRow: Int  // headerRow + 1
    let dayHeaders: [DayHeader]

    var dayStartCols: [Int] { dayHeaders.map(\.col) }
}

struct DayColumns: Sendable {
    let name: Int
    let sets: Int?
    let reps: Int?
    let percentOneRM: Int?
    let load: Int?
    let lastSetRPE: Int?
    let notes: Int?
    let span: Range<Int>  // [dayStart, nextDayStart), or past the last Day's rightmost role column
}

struct SheetLayout: Sendable {
    let weeks: [SheetLayoutWeek]

    func week(number: Int) -> SheetLayoutWeek? {
        weeks.first { $0.number == number }
    }

    func day(at address: SessionAddress) -> SheetLayoutDay? {
        week(number: address.week)?.days.first { $0.number == address.day }
    }

    func rankAndNumberAgree(week weekNumber: Int, rank: Int) -> Bool {
        guard let week = week(number: weekNumber) else { return true }
        guard week.dayHeaders.indices.contains(rank - 1) else { return !week.days.contains { $0.number == rank } }
        return week.dayHeaders[rank - 1].reading == .session(rank)
    }
}

struct SheetLayoutWeek: Sendable {
    let number: Int
    let headerRow: Int
    let roleHeaderRow: Int
    let dateRow: Int
    let endRow: Int
    let days: [SheetLayoutDay]
    let dayHeaders: [DayHeader]

    var ignoredDayHeaders: [IgnoredDayHeader] {
        dayHeaders.reduce(into: []) { ignored, header in
            guard case .ignored(let reason) = header.reading, !ignored.contains(reason) else { return }
            ignored.append(reason)
        }
    }
}

struct SheetLayoutDay: Sendable {
    let number: Int
    let columns: DayColumns
    let exerciseAnchors: [SheetLayoutExerciseAnchor]
}

/// What kind of content occupies one Notes cell, either an Exercise's header cell or a Prescription
/// Line's own cell. Coach content is read-only and the app never overwrites it (ADR-0005).
enum HeaderNotesRole: Sendable, Equatable {
    /// An empty cell counts here. A blank header is an empty Set-Log list the app writes into, not
    /// absent content.
    case setLogList
    /// Instruction-shaped coach prose.
    case coachNote(String)
    /// Result-shaped completion evidence from older exercise-level logging.
    case legacyLog(String)

    init(notesCell value: String, setCount: Int) {
        let cellHoldsSetLogs =
            SetLogToken.isSetLogListValue(value)
            || SetLogToken.isCompactAggregateHeader(value, setCount: setCount)
        if cellHoldsSetLogs {
            self = .setLogList
        } else if isLegacyLogValue(value) {
            self = .legacyLog(value)
        } else {
            self = .coachNote(value)
        }
    }

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
    while let last = trimmed.last, last.isEmpty {
        trimmed.removeLast()
    }
    return trimmed.joined(separator: ", ")
}

struct SheetLayoutInterpreter: Sendable {
    func interpret(_ snapshot: SheetSnapshot) -> SheetLayout {
        let grid = snapshot.values
        let sections = locateWeekSections(in: grid)
        let weeks = sections.enumerated().map { index, section in
            let endRow = index + 1 < sections.count ? sections[index + 1].headerRow : grid.count
            let firstBodyRow = section.roleHeaderRow + 1
            let upper = min(endRow, grid.count)
            let bodyRows = firstBodyRow..<max(firstBodyRow, upper)
            let days = section.dayHeaders.enumerated().compactMap { headerIndex, header -> SheetLayoutDay? in
                guard case .session(let number) = header.reading else { return nil }
                let columns = resolveDayColumns(
                    in: grid,
                    section: section,
                    headerIndex: headerIndex,
                    bodyRows: bodyRows
                )
                let anchors = exerciseAnchors(
                    in: snapshot,
                    cols: columns,
                    firstRow: firstBodyRow,
                    upper: upper
                )
                return SheetLayoutDay(
                    number: number,
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
                days: days.sorted { $0.number < $1.number },
                dayHeaders: section.dayHeaders
            )
        }
        return SheetLayout(weeks: weeks)
    }
}

private func dayHeaders(reading cells: [(col: Int, text: String)]) -> [DayHeader] {
    let numbers = cells.map { cell in
        cell.text.wholeMatch(of: sheetLayoutDayHeaderPattern).flatMap { Int($0.1) }.flatMap {
            Week.dayNumbers.contains($0) ? $0 : nil
        }
    }
    let counts = Dictionary(numbers.compactMap { $0 }.map { ($0, 1) }, uniquingKeysWith: +)
    return zip(cells, numbers).map { cell, number in
        let reading: DayHeader.Reading =
            switch number {
            case nil: .ignored(.outsideWeek(header: cell.text))
            case let number? where counts[number, default: 0] > 1: .ignored(.repeated(dayNumber: number))
            case let number?: .session(number)
            }
        return DayHeader(col: cell.col, reading: reading)
    }
}

private nonisolated(unsafe) let sheetLayoutDayHeaderPattern = /^Day (\d+)$/

/// Resolves role columns by scanning the role-header row within the day's span.
/// Columns are never hardcoded (ADR 0003). `bodyRows` is the day's exercise-row range,
/// used only to disambiguate a role header that is repeated across columns; the empty
/// default (`0..<0`) skips disambiguation and returns the first matching column.
///
/// A Day ends where the next Day starts. The last Day has no next start, so it takes the first
/// Day's width (16 for a one-Day week) and grows to reach any role it lacks within that width:
/// the first matching header to its right, so a coach cell further out cannot shadow the Day's
/// own column (#1045). Its span then ends after its rightmost role column.
func resolveDayColumns(
    in grid: SheetGrid,
    section: WeekSection,
    headerIndex: Int,
    bodyRows: Range<Int> = 0..<0
) -> DayColumns {
    let starts = section.dayStartCols
    let start = starts[headerIndex]
    let isLastDay = headerIndex + 1 == starts.count
    let end = isLastDay ? start + (starts.count > 1 ? starts[1] - starts[0] : 16) : starts[headerIndex + 1]
    let roleHeaderWidth = grid.indices.contains(section.roleHeaderRow) ? grid[section.roleHeaderRow].count : 0
    let pastEnd = isLastDay ? end..<max(end, roleHeaderWidth) : end..<end

    func isHeaded(_ col: Int, _ label: String) -> Bool {
        grid.cell(row: section.roleHeaderRow, col: col).caseInsensitiveCompare(label) == .orderedSame
    }
    func find(_ label: String) -> Int? {
        let matches = (start..<end).filter { isHeaded($0, label) }
        guard !matches.isEmpty else { return pastEnd.first { isHeaded($0, label) } }
        guard matches.count > 1 else { return matches.first }
        // A coach sheet can repeat a role header across adjacent columns where only one
        // carries data (e.g. a stray duplicate "Sets" header). Prefer the column with
        // values in the day's body; fall back to the first match.
        return matches.first { col in
            bodyRows.contains { !grid.cell(row: $0, col: col).trimmed.isEmpty }
        } ?? matches.first
    }
    let sets = find("Sets")
    let reps = find("Reps")
    let percentOneRM = find("%1RM")
    let load = find("Load")
    let lastSetRPE = find("Last set RPE")
    let notes = find("Notes")
    let roleColumns = [sets, reps, percentOneRM, load, lastSetRPE, notes].compactMap { $0 }
    return DayColumns(
        name: start,
        sets: sets,
        reps: reps,
        percentOneRM: percentOneRM,
        load: load,
        lastSetRPE: lastSetRPE,
        notes: notes,
        span: start..<roleColumns.reduce(end) { max($0, $1 + 1) }
    )
}

func locateWeekSections(in grid: SheetGrid) -> [WeekSection] {
    var byRow: [Int: [(col: Int, text: String)]] = [:]
    for row in 0..<grid.count {
        for col in 0..<grid[row].count where isSheetLayoutDayHeader(grid[row][col]) {
            byRow[row, default: []].append((col, grid[row][col]))
        }
    }
    return byRow.sorted { $0.key < $1.key }.map { row, cells in
        WeekSection(headerRow: row, roleHeaderRow: row + 2, dateRow: row + 1, dayHeaders: dayHeaders(reading: cells))
    }
}

/// Every row in a day's span that starts an Exercise block, hidden or not. A hidden row still ends
/// the block above it: the rows under a retired movement belong to that movement, not to the
/// Exercise before it.
func anchorRows(in grid: SheetGrid, cols: DayColumns, firstRow: Int, upper: Int) -> [Int] {
    guard firstRow < upper else { return [] }

    var rows: [Int] = []
    for row in firstRow..<upper {
        if isSheetLayoutDayHeader(grid.cell(row: row, col: cols.name)) { break }
        if !grid.cell(row: row, col: cols.name).trimmed.isEmpty { rows.append(row) }
    }
    return rows
}

/// The Exercises a day surfaces: one per anchor row the coach left visible. Hiding a row is how a
/// movement is retired without losing its history, so a hidden row is not an Exercise — the same
/// reading ADR-0003 already gives it on the write side. Block boundaries still come from every
/// anchor row, so a retired movement's own continuation rows are dropped with it rather than
/// absorbed by the Exercise above.
private func exerciseAnchors(
    in snapshot: SheetSnapshot,
    cols: DayColumns,
    firstRow: Int,
    upper: Int
) -> [SheetLayoutExerciseAnchor] {
    let grid = snapshot.values
    let rows = anchorRows(in: grid, cols: cols, firstRow: firstRow, upper: upper)
    return rows.enumerated().compactMap { index, row in
        guard snapshot.isRowVisible(row) else { return nil }
        return SheetLayoutExerciseAnchor(
            name: grid.cell(row: row, col: cols.name).trimmed,
            row: row,
            nextAnchorRow: index + 1 < rows.count ? rows[index + 1] : upper
        )
    }
}

private func isSheetLayoutDayHeader(_ value: String) -> Bool {
    value.wholeMatch(of: sheetLayoutDayHeaderPattern) != nil
}
