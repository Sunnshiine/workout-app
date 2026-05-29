import Testing

@testable import WorkoutTracker

@Test func parsesSetLogsFromNotesContinuationRows() throws {
    let grid = gridFromA1(
        [
            "C12": "Day 1", "S12": "Day 2",
            "D14": "Sets", "F14": "Reps", "H14": "Load", "I14": "Last set RPE", "K14": "Notes",
            "C15": "Squat", "D15": "2", "F15": "5", "H15": "RPE 8", "K15": "Coach note",
            "K16": "185x5@8",
            "K17": "195x5@9"
        ],
        rows: 24,
        cols: 30
    )
    let section = locateWeekSections(in: grid)[0]

    let exercises = parseDay(in: grid, section: section, dayIndex: 0, endRow: grid.count)

    #expect(exercises[0].coachNote == "Coach note")
    #expect(exercises[0].sets[0].state == .logged)
    #expect(exercises[0].sets[0].setLog?.formatted == "185x5@8")
    #expect(exercises[0].sets[1].state == .logged)
    #expect(exercises[0].sets[1].setLog?.formatted == "195x5@9")
}

@Test func parsesCompactHeaderSetLogAsSetOne() throws {
    let grid = gridFromA1(
        [
            "C12": "Day 1", "S12": "Day 2",
            "D14": "Sets", "F14": "Reps", "H14": "Load", "K14": "Notes",
            "C15": "Ab of Choice", "D15": "1", "F15": "12", "H15": "BW", "K15": "BWx12@7",
            "C16": "Bench Press", "D16": "1", "F16": "5", "H16": "RPE 8"
        ],
        rows: 22,
        cols: 30
    )
    let section = locateWeekSections(in: grid)[0]

    let exercises = parseDay(in: grid, section: section, dayIndex: 0, endRow: grid.count)

    #expect(exercises[0].coachNote == nil)
    #expect(exercises[0].legacyLog == nil)
    #expect(exercises[0].sets[0].state == .logged)
    #expect(exercises[0].sets[0].setLog == SetLog(weight: .bodyweight, reps: 12, rpe: 7))
}

@Test func parsesCompactHeaderSetLogBeforeContinuationSetLogs() throws {
    let grid = gridFromA1(
        [
            "C12": "Day 1", "S12": "Day 2",
            "D14": "Sets", "F14": "Reps", "H14": "Load", "K14": "Notes",
            "C15": "Ab of Choice", "D15": "2", "F15": "12", "H15": "BW", "K15": "BWx12@7",
            "K16": "BWx10@8",
            "C17": "Bench Press", "D17": "1", "F17": "5", "H17": "RPE 8"
        ],
        rows: 22,
        cols: 30
    )
    let section = locateWeekSections(in: grid)[0]

    let exercises = parseDay(in: grid, section: section, dayIndex: 0, endRow: grid.count)

    #expect(exercises[0].sets[0].setLog?.formatted == "BWx12@7")
    #expect(exercises[0].sets[1].setLog?.formatted == "BWx10@8")
}

@Test func parsesSkipMarkerFromNotesContinuationRow() {
    let grid = gridFromA1(
        [
            "C12": "Day 1", "S12": "Day 2",
            "D14": "Sets", "F14": "Reps", "H14": "Load", "K14": "Notes",
            "C15": "Hack SQ", "D15": "1", "F15": "7", "H15": "RPE 8", "K16": "skip"
        ],
        rows: 22,
        cols: 30
    )
    let section = locateWeekSections(in: grid)[0]

    let exercises = parseDay(in: grid, section: section, dayIndex: 0, endRow: grid.count)

    #expect(exercises[0].sets[0].state == .skipped)
    #expect(exercises[0].sets[0].setLog == nil)
}

@Test func treatsPartialNotesContinuationRowsAsLoggedWithoutSetLog() {
    let grid = gridFromA1(
        [
            "C12": "Day 1", "S12": "Day 2",
            "D14": "Sets", "F14": "Reps", "H14": "Load", "K14": "Notes",
            "C15": "Hack SQ", "D15": "3", "F15": "7", "H15": "RPE 8",
            "K16": "185",
            "K17": "185x7",
            "K18": "did 3 sets"
        ],
        rows: 22,
        cols: 30
    )
    let section = locateWeekSections(in: grid)[0]

    let exercises = parseDay(in: grid, section: section, dayIndex: 0, endRow: grid.count)

    #expect(exercises[0].sets.map(\.state) == [.logged, .logged, .logged])
    #expect(exercises[0].sets.allSatisfy { $0.setLog == nil })
    #expect(exercises[0].sets.map(\.unstructuredSetLog) == ["185", "185x7", "did 3 sets"])
}

@Test func legacyAnchorNotesCompletePrescribedSetsWithoutStructuredSetLogs() {
    let grid = gridFromA1(
        [
            "C12": "Day 1", "S12": "Day 2",
            "D14": "Sets", "F14": "Reps", "H14": "Load", "K14": "Notes",
            "C15": "Standing Calve Raises", "D15": "2", "F15": "12", "H15": "RPE 9", "K15": "25x12, 12"
        ],
        rows: 20,
        cols: 30
    )
    let section = locateWeekSections(in: grid)[0]

    let exercises = parseDay(in: grid, section: section, dayIndex: 0, endRow: grid.count)

    #expect(exercises[0].coachNote == nil)
    #expect(exercises[0].legacyLog == "25x12, 12")
    #expect(exercises[0].sets.map(\.state) == [.logged, .logged])
    #expect(exercises[0].sets.allSatisfy { $0.setLog == nil })
}

@Test func classifiesResultShapedAnchorNotesAsLegacyLogs() {
    let grid = gridFromA1(
        [
            "C12": "Day 1", "S12": "Day 2",
            "D14": "Sets", "F14": "Reps", "H14": "Load", "K14": "Notes",
            "C15": "Standing Calve Raises", "D15": "2", "F15": "12", "H15": "RPE 9", "K15": "25x12, 12"
        ],
        rows: 20,
        cols: 30
    )
    let section = locateWeekSections(in: grid)[0]

    let exercises = parseDay(in: grid, section: section, dayIndex: 0, endRow: grid.count)

    #expect(exercises[0].coachNote == nil)
    #expect(exercises[0].legacyLog == "25x12, 12")
}

@Test func keepsInstructionShapedAnchorNotesAsCoachNotes() {
    let grid = gridFromA1(
        [
            "C12": "Day 1", "S12": "Day 2",
            "D14": "Sets", "F14": "Reps", "H14": "Load", "K14": "Notes",
            "C15": "Split Squat", "D15": "2", "F15": "8", "H15": "RPE 8", "K15": "Start w/ 10 sec hold",
            "C18": "Cable Row", "D18": "2", "F18": "10", "H18": "RPE 7", "K18": "Superset w/ curls"
        ],
        rows: 24,
        cols: 30
    )
    let section = locateWeekSections(in: grid)[0]

    let exercises = parseDay(in: grid, section: section, dayIndex: 0, endRow: grid.count)

    #expect(exercises[0].coachNote == "Start w/ 10 sec hold")
    #expect(exercises[0].legacyLog == nil)
    #expect(exercises[1].coachNote == "Superset w/ curls")
    #expect(exercises[1].legacyLog == nil)
}

@Test func structuredContinuationSetLogsTakePrecedenceOverLegacyAnchorLog() {
    let grid = gridFromA1(
        [
            "C12": "Day 1", "S12": "Day 2",
            "D14": "Sets", "F14": "Reps", "H14": "Load", "K14": "Notes",
            "C15": "Standing Calve Raises", "D15": "2", "F15": "12", "H15": "RPE 9", "K15": "25x12, 12",
            "K16": "35x12@9"
        ],
        rows: 22,
        cols: 30
    )
    let section = locateWeekSections(in: grid)[0]

    let exercises = parseDay(in: grid, section: section, dayIndex: 0, endRow: grid.count)

    #expect(exercises[0].legacyLog == "25x12, 12")
    #expect(exercises[0].sets[0].state == .logged)
    #expect(exercises[0].sets[0].setLog?.formatted == "35x12@9")
    #expect(exercises[0].sets[1].state == .pending)
    #expect(exercises[0].sets[1].setLog == nil)
}

@Test func legacyAnchorLogPreservesSetLevelSkipMarkers() {
    let grid = gridFromA1(
        [
            "C12": "Day 1", "S12": "Day 2",
            "D14": "Sets", "F14": "Reps", "H14": "Load", "K14": "Notes",
            "C15": "Standing Calve Raises", "D15": "2", "F15": "12", "H15": "RPE 9", "K15": "25x12, 12",
            "K17": "skip"
        ],
        rows: 22,
        cols: 30
    )
    let section = locateWeekSections(in: grid)[0]

    let exercises = parseDay(in: grid, section: section, dayIndex: 0, endRow: grid.count)

    #expect(exercises[0].sets.map(\.state) == [.logged, .skipped])
    #expect(exercises[0].sets.allSatisfy { $0.setLog == nil })
}
