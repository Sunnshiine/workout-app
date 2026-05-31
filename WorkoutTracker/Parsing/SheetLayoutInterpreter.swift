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

struct SheetLayoutHeaderNotes: Sendable, Equatable {
    let value: String

    var usesCompactHeaderSetOne: Bool {
        value.isEmpty
            || value.caseInsensitiveCompare("skip") == .orderedSame
            || SetLog(formatted: value) != nil
    }

    var hasProtectedValue: Bool {
        !value.isEmpty && !usesCompactHeaderSetOne
    }

    var isLegacyLog: Bool {
        guard hasProtectedValue else { return false }
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

    var isCoachNote: Bool {
        hasProtectedValue && !isLegacyLog
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

struct SheetLayoutExerciseAnchor: Sendable {
    let name: String
    let row: Int
    let nextAnchorRow: Int

    func headerNotes(in grid: SheetGrid, notesColumn: Int?) -> SheetLayoutHeaderNotes {
        SheetLayoutHeaderNotes(value: grid.cellOrEmpty(row, notesColumn).trimmed)
    }

    func prescribedSetCount(in grid: SheetGrid, setsColumn: Int?) -> Int {
        let rawValue = setsColumn.map { grid.cell(row: row, col: $0).trimmed } ?? ""
        return max(Int(rawValue.prefix { $0.isNumber }) ?? 1, 1)
    }

    func usesCompactHeaderSetOne(headerNotes: SheetLayoutHeaderNotes) -> Bool {
        headerNotes.usesCompactHeaderSetOne
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

    func visibleSetLogRow(for setIndex: Int, compactHeaderSetOne: Bool, in snapshot: SheetSnapshot) -> Int? {
        guard setIndex >= 0 else { return nil }
        let firstRow = row + (compactHeaderSetOne ? 0 : 1)
        guard firstRow < nextAnchorRow else { return nil }

        var visibleIndex = 0
        for candidate in firstRow..<nextAnchorRow where snapshot.isRowVisible(candidate) {
            if visibleIndex == setIndex {
                return candidate
            }
            visibleIndex += 1
        }
        return nil
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
            let days = section.dayStartCols.indices.map { dayIndex in
                let columns = resolveDayColumns(in: grid, section: section, dayIndex: dayIndex)
                let anchors = exerciseAnchors(
                    in: grid,
                    cols: columns,
                    firstRow: section.roleHeaderRow + 1,
                    upper: min(endRow, grid.count)
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

private nonisolated(unsafe) let sheetLayoutDayHeaderPattern = /^Day [1-4]$/

/// Resolves role columns by scanning the role-header row within the day's span.
/// Columns are never hardcoded (ADR 0003).
func resolveDayColumns(in grid: SheetGrid, section: WeekSection, dayIndex: Int) -> DayColumns {
    let starts = section.dayStartCols
    let start = starts[dayIndex]
    let end =
        dayIndex + 1 < starts.count
        ? starts[dayIndex + 1]
        : start + (starts.count > 1 ? starts[1] - starts[0] : 16)
    let span = start..<end

    func find(_ label: String) -> Int? {
        span.first {
            grid.cell(row: section.roleHeaderRow, col: $0).caseInsensitiveCompare(label) == .orderedSame
        }
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
