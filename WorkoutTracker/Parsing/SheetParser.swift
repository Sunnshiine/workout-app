import Foundation

private let trainingMaxHeaderScanRowLimit = 15

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
    var unstructuredSetLog: String?

    init(
        index: Int,
        prescribedReps: String,
        prescribedLoad: String,
        percentOneRM: String?,
        state: SetState? = nil,
        setLog: SetLog? = nil,
        unstructuredSetLog: String? = nil
    ) {
        self.index = index
        self.prescribedReps = prescribedReps
        self.prescribedLoad = prescribedLoad
        self.percentOneRM = percentOneRM
        self.state = state ?? (setLog == nil ? .pending : .logged)
        self.setLog = setLog
        self.unstructuredSetLog = unstructuredSetLog
    }
}

struct ParsedExercise {
    var name: String
    var baseName: String
    var cadence: String?
    var coachNote: String?
    var legacyLog: String?
    var sets: [ParsedSet]

    init(
        name: String,
        baseName: String,
        cadence: String?,
        coachNote: String?,
        legacyLog: String? = nil,
        sets: [ParsedSet]
    ) {
        self.name = name
        self.baseName = baseName
        self.cadence = cadence
        self.coachNote = coachNote
        self.legacyLog = legacyLog
        self.sets = sets
    }
}

private struct ParsedLogState {
    let state: SetState
    let setLog: SetLog?
    let unstructuredSetLog: String?
}

private func parsedLogState(from raw: String) -> ParsedLogState {
    let value = raw.trimmed
    guard !value.isEmpty else {
        return ParsedLogState(state: .pending, setLog: nil, unstructuredSetLog: nil)
    }
    if value.caseInsensitiveCompare("skip") == .orderedSame {
        return ParsedLogState(state: .skipped, setLog: nil, unstructuredSetLog: nil)
    }
    if let log = SetLog(formatted: value) {
        return ParsedLogState(state: .logged, setLog: log, unstructuredSetLog: nil)
    }
    return ParsedLogState(state: .logged, setLog: nil, unstructuredSetLog: value)
}

private struct ParsedSetContext {
    let setCount: Int
    let anchor: SheetLayoutExerciseAnchor
    let cols: DayColumns
    let grid: SheetGrid
    let headerNote: String
    let compactHeaderSetOne: Bool
    let reps: String
    let repsValues: [String]
    let load: String
    let loadValues: [String]
    let percentOneRM: String
}

private func parsedSets(_ context: ParsedSetContext) -> [ParsedSet] {
    (0..<context.setCount).map { i in
        let rawLog: String
        if context.compactHeaderSetOne, i == 0 {
            rawLog = context.headerNote
        } else {
            let logRow = context.anchor.setLogRow(
                for: i,
                compactHeaderSetOne: context.compactHeaderSetOne
            )
            rawLog = logRow.map { context.grid.cellOrEmpty($0, context.cols.notes) } ?? ""
        }
        let logState = parsedLogState(from: rawLog)
        return ParsedSet(
            index: i,
            prescribedReps: i < context.repsValues.count ? context.repsValues[i] : (context.repsValues.last ?? context.reps),
            prescribedLoad: i < context.loadValues.count ? context.loadValues[i] : (context.loadValues.last ?? context.load),
            percentOneRM: context.percentOneRM.isEmpty ? nil : context.percentOneRM,
            state: logState.state,
            setLog: logState.setLog,
            unstructuredSetLog: logState.unstructuredSetLog
        )
    }
}

private func completionSets(_ sets: [ParsedSet], legacyLog: String?) -> [ParsedSet] {
    guard legacyLog != nil, !sets.contains(where: { $0.setLog != nil }) else { return sets }

    return sets.map {
        ParsedSet(
            index: $0.index,
            prescribedReps: $0.prescribedReps,
            prescribedLoad: $0.prescribedLoad,
            percentOneRM: $0.percentOneRM,
            state: $0.state == .skipped ? .skipped : .logged,
            setLog: $0.setLog,
            unstructuredSetLog: $0.unstructuredSetLog
        )
    }
}

private func parsedExercise(grid: SheetGrid, day: SheetLayoutDay, anchor: SheetLayoutExerciseAnchor) -> ParsedExercise {
    let cols = day.columns
    let anchorRow = anchor.row
    let rawName = grid.cell(row: anchorRow, col: cols.name).trimmed
    let (cadence, base) = splitCadence(rawName)
    let reps = grid.cellOrEmpty(anchorRow, cols.reps)
    let load = grid.cellOrEmpty(anchorRow, cols.load)
    let headerNotes = anchor.headerNotes(in: grid, notesColumn: cols.notes)
    let note = headerNotes.value
    let setCount = anchor.prescribedSetCount(in: grid, setsColumn: cols.sets)
    let compactHeaderSetOne = anchor.usesCompactHeaderSetOne(headerNotes: headerNotes)
    let legacyLog = headerNotes.isLegacyLog ? note : nil
    let sets = completionSets(
        parsedSets(
            ParsedSetContext(
                setCount: setCount,
                anchor: anchor,
                cols: cols,
                grid: grid,
                headerNote: note,
                compactHeaderSetOne: compactHeaderSetOne,
                reps: reps,
                repsValues: reps.components(separatedBy: ",").map { $0.trimmingCharacters(in: .whitespaces) },
                load: load,
                loadValues: splitLoadValues(load),
                percentOneRM: grid.cellOrEmpty(anchorRow, cols.percentOneRM)
            )
        ),
        legacyLog: legacyLog
    )

    return ParsedExercise(
        name: rawName,
        baseName: base,
        cadence: cadence,
        coachNote: headerNotes.isCoachNote ? note : nil,
        legacyLog: legacyLog,
        sets: sets
    )
}

/// Parses all exercises in one day group. Anchor rows have a non-empty name cell;
/// the row count for an exercise is `max(Sets value, 1)` (continuation rows hold
/// extra sets / set logs; logs are read in Plan 2).
func parseDay(in grid: SheetGrid, section: WeekSection, dayIndex: Int, endRow: Int) -> [ParsedExercise] {
    let layout = SheetLayoutInterpreter().interpret(grid)
    guard
        let week = layout.weeks.first(where: { $0.headerRow == section.headerRow }),
        dayIndex < week.days.count
    else { return [] }

    return parseDay(in: grid, day: week.days[dayIndex])
}

private func parseDay(in grid: SheetGrid, day: SheetLayoutDay) -> [ParsedExercise] {
    day.exerciseAnchors.map { anchor in
        parsedExercise(grid: grid, day: day, anchor: anchor)
    }
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
struct ParsedTrainingMax {
    var squat: Double?
    var bench: Double?
    var deadlift: Double?
}

func parseTrainingMax(from grid: SheetGrid) -> ParsedTrainingMax {
    let scannedRows = min(grid.count, trainingMaxHeaderScanRowLimit)
    for row in 0..<scannedRows {
        for col in 0..<grid[row].count
        where grid[row][col].trimmed.caseInsensitiveCompare("Training Max") == .orderedSame {
            return trainingMaxValues(from: grid, valueCol: col, labelCol: col - 2, startRow: row + 1)
        }
    }

    return ParsedTrainingMax()
}

private func trainingMaxValues(
    from grid: SheetGrid,
    valueCol: Int,
    labelCol: Int,
    startRow: Int
) -> ParsedTrainingMax {
    guard labelCol >= 0 else { return ParsedTrainingMax() }

    func value(for expectedLabel: String) -> Double? {
        let endRow = min(grid.count, startRow + 8)
        return (startRow..<endRow).compactMap { row -> Double? in
            let label = grid.cell(row: row, col: labelCol).trimmed
            guard label.caseInsensitiveCompare(expectedLabel) == .orderedSame else { return nil }
            return Double(grid.cell(row: row, col: valueCol).trimmed)
        }.first
    }

    return ParsedTrainingMax(
        squat: value(for: "Squat"),
        bench: value(for: "Bench Press"),
        deadlift: value(for: "Deadlift")
    )
}

struct ParsedBlockModel {
    var tabName: String
    var weeks: [ParsedWeek]
    var squatTM: Double?
    var benchTM: Double?
    var deadliftTM: Double?

    init(
        tabName: String,
        weeks: [ParsedWeek],
        squatTM: Double? = nil,
        benchTM: Double? = nil,
        deadliftTM: Double? = nil
    ) {
        self.tabName = tabName
        self.weeks = weeks
        self.squatTM = squatTM
        self.benchTM = benchTM
        self.deadliftTM = deadliftTM
    }
}
struct ParsedBlock {
    var block: ParsedBlockModel
    var warnings: [String]
}

struct SheetParser {
    func parse(grid: SheetGrid, tabName: String) -> ParsedBlock {
        var warnings: [String] = []
        let trainingMax = parseTrainingMax(from: grid)
        let layout = SheetLayoutInterpreter().interpret(grid)
        if layout.weeks.isEmpty {
            warnings.append("Parse warning: no week sections (no 'Day N' headers) in \(tabName)")
            return ParsedBlock(
                block: ParsedBlockModel(
                    tabName: tabName,
                    weeks: [],
                    squatTM: trainingMax.squat,
                    benchTM: trainingMax.bench,
                    deadliftTM: trainingMax.deadlift
                ),
                warnings: warnings
            )
        }

        let weeks = layout.weeks.map { week in
            let days = week.days.map { day in
                let date = parseDate(grid.cell(row: week.dateRow, col: day.columns.name))
                let exercises = parseDay(in: grid, day: day)
                return ParsedSession(dayNumber: day.number, date: date, exercises: exercises)
            }
            return ParsedWeek(number: week.number, days: days)
        }

        return ParsedBlock(
            block: ParsedBlockModel(
                tabName: tabName,
                weeks: weeks,
                squatTM: trainingMax.squat,
                benchTM: trainingMax.bench,
                deadliftTM: trainingMax.deadlift
            ),
            warnings: warnings
        )
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
