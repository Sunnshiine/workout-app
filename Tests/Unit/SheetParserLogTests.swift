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
}

@Test func ignoresAnchorNotesAsSetLogs() {
    let grid = gridFromA1(
        [
            "C12": "Day 1", "S12": "Day 2",
            "D14": "Sets", "F14": "Reps", "H14": "Load", "K14": "Notes",
            "C15": "Standing Calve Raises", "D15": "1", "F15": "12", "H15": "RPE 9", "K15": "25x12, 12"
        ],
        rows: 20,
        cols: 30
    )
    let section = locateWeekSections(in: grid)[0]

    let exercises = parseDay(in: grid, section: section, dayIndex: 0, endRow: grid.count)

    #expect(exercises[0].coachNote == "25x12, 12")
    #expect(exercises[0].sets[0].state == .pending)
    #expect(exercises[0].sets[0].setLog == nil)
}
