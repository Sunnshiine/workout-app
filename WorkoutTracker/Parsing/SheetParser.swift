import Foundation

struct WeekSection {
    let headerRow: Int  // 0-based row holding "Day N"
    let roleHeaderRow: Int  // headerRow + 2
    let dateRow: Int  // headerRow + 1
    let dayStartCols: [Int]  // 0-based columns of Day 1..Day 4
}

private nonisolated(unsafe) let dayHeaderPattern = /^Day [1-4]$/

struct DayColumns {
    let name: Int
    let sets: Int?
    let reps: Int?
    let percentOneRM: Int?
    let load: Int?
    let lastSetRPE: Int?
    let notes: Int?
    let span: Range<Int>  // [dayStart, nextDayStart)
}

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
    for r in 0..<grid.count {
        for c in 0..<grid[r].count where grid[r][c].wholeMatch(of: dayHeaderPattern) != nil {
            byRow[r, default: []].append(c)
        }
    }
    return byRow.keys.sorted().compactMap { row in
        let cols = byRow[row]!.sorted()
        guard !cols.isEmpty else { return nil }
        return WeekSection(headerRow: row, roleHeaderRow: row + 2, dateRow: row + 1, dayStartCols: cols)
    }
}

/// Splits a leading tempo prefix (e.g. "2-3:1-2:0") from the base exercise name.
func splitCadence(_ name: String) -> (cadence: String?, base: String) {
    let pattern = /^(\d+(?:-\d+)?:\d+(?:-\d+)?:\d+(?:-\d+)?)\s+(.+)$/
    if let m = name.wholeMatch(of: pattern) {
        return (String(m.1), String(m.2))
    }
    return (nil, name)
}

struct ParsedSet {
    var index: Int
    var prescribedReps: String
    var prescribedLoad: String
    var percentOneRM: String?
}

struct ParsedExercise {
    var name: String
    var baseName: String
    var cadence: String?
    var coachNote: String?
    var sets: [ParsedSet]
}

/// Parses all exercises in one day group. Anchor rows have a non-empty name cell;
/// the row count for an exercise is `max(Sets value, 1)` (continuation rows hold
/// extra sets / set logs; logs are read in Plan 2).
func parseDay(in grid: SheetGrid, section: WeekSection, dayIndex: Int, endRow: Int) -> [ParsedExercise] {
    let cols = resolveDayColumns(in: grid, section: section, dayIndex: dayIndex)
    let firstRow = section.roleHeaderRow + 1
    let upper = min(endRow, grid.count)

    // Collect anchor rows (name cell non-empty), stopping at the next week's day header.
    var anchors: [Int] = []
    if firstRow < upper {
        for r in firstRow..<upper {
            if grid.cell(row: r, col: cols.name).wholeMatch(of: dayHeaderPattern) != nil { break }
            if !grid.cell(row: r, col: cols.name).trimmed.isEmpty { anchors.append(r) }
        }
    }

    var result: [ParsedExercise] = []
    for r in anchors {
        let rawName = grid.cell(row: r, col: cols.name).trimmed
        let (cadence, base) = splitCadence(rawName)
        // Sets cell may be "2" or a range like "3 - 4"; take the leading integer.
        let setCount = max(Int(grid.cellOrEmpty(r, cols.sets).prefix { $0.isNumber }) ?? 1, 1)
        let reps = grid.cellOrEmpty(r, cols.reps)
        let load = grid.cellOrEmpty(r, cols.load)
        let pct = grid.cellOrEmpty(r, cols.percentOneRM)
        let note = grid.cellOrEmpty(r, cols.notes).trimmed
        let sets = (0..<setCount).map {
            ParsedSet(
                index: $0,
                prescribedReps: reps,
                prescribedLoad: load,
                percentOneRM: pct.isEmpty ? nil : pct
            )
        }
        result.append(
            ParsedExercise(
                name: rawName,
                baseName: base,
                cadence: cadence,
                coachNote: note.isEmpty ? nil : note,
                sets: sets
            )
        )
    }
    return result
}

struct ParsedSession {
    var dayNumber: Int
    var date: Date?
    var exercises: [ParsedExercise]
}
struct ParsedWeek {
    var number: Int
    var days: [ParsedSession]
}
struct ParsedBlockModel {
    var tabName: String
    var weeks: [ParsedWeek]
}
struct ParsedBlock {
    var block: ParsedBlockModel
    var warnings: [String]
}

struct SheetParser {
    func parse(grid: SheetGrid, tabName: String) -> ParsedBlock {
        var warnings: [String] = []
        let sections = locateWeekSections(in: grid)
        if sections.isEmpty {
            warnings.append("Parse warning: no week sections (no 'Day N' headers) in \(tabName)")
            return ParsedBlock(block: ParsedBlockModel(tabName: tabName, weeks: []), warnings: warnings)
        }
        var weeks: [ParsedWeek] = []
        for (i, section) in sections.enumerated() {
            let endRow = (i + 1 < sections.count) ? sections[i + 1].headerRow : grid.count
            var days: [ParsedSession] = []
            for dayIndex in 0..<section.dayStartCols.count {
                let date = parseDate(grid.cell(row: section.dateRow, col: section.dayStartCols[dayIndex]))
                let exercises = parseDay(in: grid, section: section, dayIndex: dayIndex, endRow: endRow)
                days.append(ParsedSession(dayNumber: dayIndex + 1, date: date, exercises: exercises))
            }
            weeks.append(ParsedWeek(number: i + 1, days: days))
        }
        return ParsedBlock(block: ParsedBlockModel(tabName: tabName, weeks: weeks), warnings: warnings)
    }

    private func parseDate(_ s: String) -> Date? {
        let f = DateFormatter()
        f.dateFormat = "M/d/yyyy"
        f.locale = Locale(identifier: "en_US_POSIX")
        return f.date(from: s.trimmed)
    }
}

extension String { var trimmed: String { trimmingCharacters(in: .whitespacesAndNewlines) } }
extension Array where Element == [String] {
    func cellOrEmpty(_ row: Int, _ col: Int?) -> String { col.map { cell(row: row, col: $0) } ?? "" }
}
