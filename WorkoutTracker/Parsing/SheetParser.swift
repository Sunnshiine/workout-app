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
        guard let cols = byRow[row]?.sorted(), !cols.isEmpty else { return nil }
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

private func splitLoadValues(_ load: String) -> [String] {
    let values = load.components(separatedBy: ",").map { $0.trimmingCharacters(in: .whitespaces) }
    guard
        values.count > 1,
        let numberStart = values[0].firstIndex(where: { $0.isNumber })
    else { return values }

    let prefix = values[0][..<numberStart]
    guard prefix.contains(where: { $0.isLetter }) else { return values }

    return values.enumerated().map { index, value in
        if index > 0, !value.contains(where: { $0.isLetter }) {
            return "\(prefix)\(value)"
        }
        return value
    }
}

struct ParsedSet {
    var index: Int
    var prescribedReps: String
    var prescribedLoad: String
    var percentOneRM: String?
    var state: SetState
    var setLog: SetLog?

    init(
        index: Int,
        prescribedReps: String,
        prescribedLoad: String,
        percentOneRM: String?,
        state: SetState? = nil,
        setLog: SetLog? = nil
    ) {
        self.index = index
        self.prescribedReps = prescribedReps
        self.prescribedLoad = prescribedLoad
        self.percentOneRM = percentOneRM
        self.state = state ?? (setLog == nil ? .pending : .logged)
        self.setLog = setLog
    }
}

struct ParsedExercise {
    var name: String
    var baseName: String
    var cadence: String?
    var coachNote: String?
    var sets: [ParsedSet]
}

private func parsedLogState(from raw: String) -> (SetState, SetLog?) {
    let value = raw.trimmed
    if value.caseInsensitiveCompare("skip") == .orderedSame {
        return (.skipped, nil)
    }
    if let log = SetLog(formatted: value) {
        return (.logged, log)
    }
    return (.pending, nil)
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
    for (anchorIndex, r) in anchors.enumerated() {
        let nextAnchor = anchorIndex + 1 < anchors.count ? anchors[anchorIndex + 1] : upper
        let rawName = grid.cell(row: r, col: cols.name).trimmed
        let (cadence, base) = splitCadence(rawName)
        // Sets cell may be "2" or a range like "3 - 4"; take the leading integer.
        let setCount = max(Int(grid.cellOrEmpty(r, cols.sets).prefix { $0.isNumber }) ?? 1, 1)
        let reps = grid.cellOrEmpty(r, cols.reps)
        let load = grid.cellOrEmpty(r, cols.load)
        let pct = grid.cellOrEmpty(r, cols.percentOneRM)
        let note = grid.cellOrEmpty(r, cols.notes).trimmed
        let loadValues = splitLoadValues(load)
        let repsValues = reps.components(separatedBy: ",").map { $0.trimmingCharacters(in: .whitespaces) }
        let sets = (0..<setCount).map { i in
            let logRow = r + i + 1
            let rawLog = logRow < nextAnchor ? grid.cellOrEmpty(logRow, cols.notes) : ""
            let (state, setLog) = parsedLogState(from: rawLog)
            return ParsedSet(
                index: i,
                prescribedReps: i < repsValues.count ? repsValues[i] : (repsValues.last ?? reps),
                prescribedLoad: i < loadValues.count ? loadValues[i] : (loadValues.last ?? load),
                percentOneRM: pct.isEmpty ? nil : pct,
                state: state,
                setLog: setLog
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
