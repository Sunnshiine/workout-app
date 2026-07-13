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

private struct ParsedSetContext {
    let setCount: Int
    let anchor: SheetLayoutExerciseAnchor
    let cols: DayColumns
    let snapshot: SheetSnapshot
    let reps: String
    let repsValues: [String]
    let load: String
    let loadValues: [String]
    let percentOneRM: String
}

private func parsedSets(_ context: ParsedSetContext) -> [ParsedSet] {
    (0..<context.setCount).map { i in
        let rawLog = rawSetLog(
            for: i,
            anchor: context.anchor,
            snapshot: context.snapshot,
            cols: context.cols
        )
        let logState = SetLogToken.classify(rawLog)
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

/// Reads Set `setIndex`'s raw Notes token from wherever the placement query resolves it — the one
/// addressing decision the write path also consumes (ADR-0010), so display and write targeting
/// cannot diverge. A list placement (compact header list, protected-header Visible Writable Row, or
/// a multi-line Prescription Line) reads the token at the Set's list position via the shared
/// `SetLogList` codec; a whole-cell placement reads the cell. An unresolved placement — a protected
/// header with no safe writable row, a Set row out of the Exercise's span, or a missing Notes
/// column — reads empty, leaving the Set Pending unless a Legacy Log later marks it complete.
private func rawSetLog(
    for setIndex: Int,
    anchor: SheetLayoutExerciseAnchor,
    snapshot: SheetSnapshot,
    cols: DayColumns
) -> String {
    guard case .placed(let placement) = anchor.setLogPlacement(for: setIndex, in: snapshot, cols: cols) else {
        return ""
    }
    let cell = snapshot.values.cell(row: placement.row, col: placement.col)
    return placement.listPosition.map { SetLogList(cell: cell).token(at: $0) } ?? cell
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

/// Builds the Sets for one Prescription Line: the Line's own Reps/Load/%1RM are split
/// positionally (repeating the last token), and each Set's Set Log is read from the placement query
/// (the Line's own Notes cell at the Set's list position — the same cell the write path targets). A
/// protected Line Notes cell (a Coach Note or Legacy Log, ADR-0005) leaves the Line's Sets Pending
/// rather than reading its coach content out as Set Logs.
private func parsedSetsForLine(
    snapshot: SheetSnapshot,
    cols: DayColumns,
    anchor: SheetLayoutExerciseAnchor,
    line: PrescriptionLine
) -> [ParsedSet] {
    let grid = snapshot.values
    let reps = grid.cellOrEmpty(line.row, cols.reps)
    let repsValues = reps.components(separatedBy: ",").map { $0.trimmingCharacters(in: .whitespaces) }
    let load = grid.cellOrEmpty(line.row, cols.load)
    let loadValues = splitLoadValues(load)
    let percent = grid.cellOrEmpty(line.row, cols.percentOneRM)
    let notes = SheetLayoutHeaderNotes(value: grid.cellOrEmpty(line.row, cols.notes).trimmed)
    let protectedLine = anchor.isHeaderProtectedFromSetLogWrites(headerNotes: notes, setCount: line.setCount)

    return (0..<line.setCount).map { position in
        let setIndex = line.firstSetIndex + position
        let rawLog = protectedLine ? "" : rawSetLog(for: setIndex, anchor: anchor, snapshot: snapshot, cols: cols)
        let logState = SetLogToken.classify(rawLog)
        return ParsedSet(
            index: setIndex,
            prescribedReps: position < repsValues.count ? repsValues[position] : (repsValues.last ?? reps),
            prescribedLoad: position < loadValues.count ? loadValues[position] : (loadValues.last ?? load),
            percentOneRM: percent.isEmpty ? nil : percent,
            state: logState.state,
            setLog: logState.setLog,
            unstructuredSetLog: logState.unstructuredSetLog
        )
    }
}

private func parsedMultiLineExercise(
    snapshot: SheetSnapshot,
    cols: DayColumns,
    anchor: SheetLayoutExerciseAnchor,
    lines: [PrescriptionLine]
) -> ParsedExercise {
    let grid = snapshot.values
    let rawName = grid.cell(row: anchor.row, col: cols.name).trimmed
    let (cadence, base) = splitCadence(rawName)
    let anchorNotes = anchor.headerNotes(in: grid, notesColumn: cols.notes)
    let sets = lines.flatMap { parsedSetsForLine(snapshot: snapshot, cols: cols, anchor: anchor, line: $0) }
    return ParsedExercise(
        name: rawName,
        baseName: base,
        cadence: cadence,
        coachNote: anchorNotes.isCoachNote ? anchorNotes.value : nil,
        sets: sets
    )
}

private func parsedExercise(snapshot: SheetSnapshot, day: SheetLayoutDay, anchor: SheetLayoutExerciseAnchor) -> ParsedExercise {
    let cols = day.columns
    let lines = anchor.prescriptionLines(in: snapshot.values, setsColumn: cols.sets)
    return lines.isMultiLine
        ? parsedMultiLineExercise(snapshot: snapshot, cols: cols, anchor: anchor, lines: lines)
        : parsedSingleLineExercise(snapshot: snapshot, cols: cols, anchor: anchor)
}

private func parsedSingleLineExercise(snapshot: SheetSnapshot, cols: DayColumns, anchor: SheetLayoutExerciseAnchor) -> ParsedExercise {
    let grid = snapshot.values
    let anchorRow = anchor.row
    let rawName = grid.cell(row: anchorRow, col: cols.name).trimmed
    let (cadence, base) = splitCadence(rawName)
    let reps = grid.cellOrEmpty(anchorRow, cols.reps)
    let load = grid.cellOrEmpty(anchorRow, cols.load)
    let headerNotes = anchor.headerNotes(in: grid, notesColumn: cols.notes)
    let note = headerNotes.value
    let setCount = anchor.prescribedSetCount(in: grid, setsColumn: cols.sets)
    // A Legacy Log is only completion evidence when the header cannot be read as compact Set Logs;
    // a value that fits as a compact header list (`setCount`-aware) is read as Set Logs instead.
    let compactHeaderSetOne = anchor.usesCompactHeaderSetOne(headerNotes: headerNotes, setCount: setCount)
    let legacyLog = !compactHeaderSetOne && headerNotes.isLegacyLog ? note : nil
    let sets = completionSets(
        parsedSets(
            ParsedSetContext(
                setCount: setCount,
                anchor: anchor,
                cols: cols,
                snapshot: snapshot,
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
/// the row count for an exercise is `max(Sets value, 1)`.
func parseDay(in grid: SheetGrid, section: WeekSection, dayIndex: Int, endRow: Int) -> [ParsedExercise] {
    let snapshot = SheetSnapshot(values: grid)
    let layout = SheetLayoutInterpreter().interpret(snapshot)
    guard
        let week = layout.weeks.first(where: { $0.headerRow == section.headerRow }),
        dayIndex < week.days.count
    else { return [] }

    return parseDay(in: snapshot, day: week.days[dayIndex])
}

private func parseDay(in snapshot: SheetSnapshot, day: SheetLayoutDay) -> [ParsedExercise] {
    day.exerciseAnchors.map { anchor in
        parsedExercise(snapshot: snapshot, day: day, anchor: anchor)
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
    func parse(snapshot: SheetSnapshot, tabName: String) -> ParsedBlock {
        parse(snapshot, tabName: tabName)
    }

    func parse(grid: SheetGrid, tabName: String) -> ParsedBlock {
        parse(SheetSnapshot(values: grid), tabName: tabName)
    }

    private func parse(_ snapshot: SheetSnapshot, tabName: String) -> ParsedBlock {
        let grid = snapshot.values
        var warnings: [String] = []
        let trainingMax = parseTrainingMax(from: grid)
        let layout = SheetLayoutInterpreter().interpret(snapshot)
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
                let exercises = parseDay(in: snapshot, day: day)
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
