import Testing

@testable import WorkoutTracker

@Test func parsesSetLogsFromNotesContinuationRows() throws {
    let grid = gridFromA1(
        [
            "C12": "Day 1", "S12": "Day 2",
            "D14": "Sets", "F14": "Reps", "H14": "Load", "I14": "Last set RPE", "K14": "Notes",
            "C15": "Squat", "D15": "2", "F15": "5", "H15": "RPE 8", "K15": "Coach note",
            "K16": "185x5@8, 195x5@9"
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

@Test func parsesProtectedHeaderSetLogsFromFirstVisibleWritableRowSkippingHiddenRows() throws {
    let grid = gridFromA1(
        [
            "C12": "Day 1", "S12": "Day 2",
            "D14": "Sets", "F14": "Reps", "H14": "Load", "I14": "Last set RPE", "K14": "Notes",
            "C15": "2-3:1:0 Incline DB BP", "D15": "2", "F15": "7 - 8", "H15": "RPE8, RF",
            "K15": "AMRAP w/ 0:3:0 BW Push Up",
            "K16": "stale hidden log",
            "K17": "100x8@6, 105x7@7",
            "C20": "0:2:0 Hamstring Curl", "D20": "2"
        ],
        rows: 24,
        cols: 30
    )
    let snapshot = SheetSnapshot(
        values: grid,
        rowVisibility: [15: SheetRowVisibility(hiddenByUser: true)]
    )

    let parsed = SheetParser().parse(snapshot: snapshot, tabName: "Block 27")
    let exercise = try #require(parsed.block.weeks.first?.days.first?.exercises.first)

    #expect(exercise.coachNote == "AMRAP w/ 0:3:0 BW Push Up")
    #expect(exercise.sets.map { $0.setLog?.formatted } == ["100x8@6", "105x7@7"])
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

@Test func ignoresContinuationRowsWhenHeaderNotesHoldsSetLog() throws {
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
    #expect(exercises[0].sets[1].state == .pending)
    #expect(exercises[0].sets[1].setLog == nil)
}

@Test func parsesSkipMarkerFromNotesContinuationRow() {
    let grid = gridFromA1(
        [
            "C12": "Day 1", "S12": "Day 2",
            "D14": "Sets", "F14": "Reps", "H14": "Load", "K14": "Notes",
            "C15": "Hack SQ", "D15": "1", "F15": "7", "H15": "RPE 8", "K15": "Coach note", "K16": "skip"
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
            "C15": "Hack SQ", "D15": "3", "F15": "7", "H15": "RPE 8", "K15": "Coach note",
            "K16": "185, 185x7, did 3 sets"
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
            "K16": ", skip"
        ],
        rows: 22,
        cols: 30
    )
    let section = locateWeekSections(in: grid)[0]

    let exercises = parseDay(in: grid, section: section, dayIndex: 0, endRow: grid.count)

    #expect(exercises[0].sets.map(\.state) == [.logged, .skipped])
    #expect(exercises[0].sets.allSatisfy { $0.setLog == nil })
}

/// Asserts every parsed Set's classification is exactly `SetLogToken.classify` of the token the
/// placement query resolves for that Set — i.e. the reader reads each Set from the one placement
/// decision the writer also consumes (ADR-0010), not a separately re-branched address. Used on
/// grids whose read cells are writable (not a protected header at the read cell), where reader and
/// placement-read must coincide token-for-token.
private func expectReaderReadsEachSetFromPlacement(_ snapshot: SheetSnapshot) throws {
    let layout = SheetLayoutInterpreter().interpret(snapshot)
    let parsed = SheetParser().parse(snapshot: snapshot, tabName: "B")
    for week in layout.weeks {
        let parsedWeek = try #require(parsed.block.weeks.first { $0.number == week.number })
        for (dayIndex, day) in week.days.enumerated() {
            let parsedDay = parsedWeek.days[dayIndex]
            for (anchorIndex, anchor) in day.exerciseAnchors.enumerated() {
                let exercise = parsedDay.exercises[anchorIndex]
                for setIndex in exercise.sets.indices {
                    guard
                        case .placed(let placement) = anchor.setLogPlacement(
                            for: setIndex,
                            in: snapshot,
                            cols: day.columns
                        )
                    else {
                        Issue.record("expected a resolved placement for set \(setIndex) of \(anchor.name)")
                        continue
                    }
                    let cell = snapshot.values.cell(row: placement.row, col: placement.col)
                    let token = placement.listPosition.map { SetLogList(cell: cell).token(at: $0) } ?? cell
                    let expected = SetLogToken.classify(token)
                    #expect(exercise.sets[setIndex].state == expected.state)
                    #expect(exercise.sets[setIndex].setLog == expected.setLog)
                    #expect(exercise.sets[setIndex].unstructuredSetLog == expected.unstructuredSetLog)
                }
            }
        }
    }
}

@Test func readsProtectedHeaderSetsFromThePlacementResolvedVisibleWritableRow() throws {
    let grid = gridFromA1(
        [
            "C12": "Day 1", "S12": "Day 2",
            "D14": "Sets", "F14": "Reps", "H14": "Load", "K14": "Notes",
            "C15": "Squat", "D15": "2", "F15": "5", "H15": "RPE 8", "K15": "Coach note",
            "K16": "185x5@8, 195x5@9"
        ],
        rows: 24,
        cols: 30
    )
    try expectReaderReadsEachSetFromPlacement(SheetSnapshot(values: grid))
}

@Test func readsCompactAggregateHeaderSetsFromThePlacementResolvedHeaderList() throws {
    let grid = gridFromA1(
        [
            "C12": "Day 1", "S12": "Day 2",
            "D14": "Sets", "F14": "Reps", "H14": "Load", "K14": "Notes",
            "C15": "Ab of Choice", "D15": "2", "F15": "12", "H15": "BW", "K15": "BWx12@7, skip",
            "C16": "Bench Press", "D16": "1", "F16": "5", "H16": "RPE 8", "K16": "225x5@8"
        ],
        rows: 22,
        cols: 30
    )
    try expectReaderReadsEachSetFromPlacement(SheetSnapshot(values: grid))
}

@Test func readsMultiLineSetsFromTheirPlacementResolvedPrescriptionLineCells() throws {
    // Genuine per-line Set Logs (no protected line): reader and placement must resolve the same
    // cell and list position for every Set across both Prescription Lines.
    let grid = gridFromA1(
        [
            "C12": "Day 1", "S12": "Day 2",
            "D14": "Sets", "F14": "Reps", "H14": "Load", "K14": "Notes",
            "C15": "Comp SQ", "D15": "2", "F15": "5", "H15": "RPE6", "K15": "185x5@8, 190x5@9",
            "D16": "1", "F16": "5", "H16": "Drop 20%", "K16": "205x5@7",
            "C17": "Hip Thrust", "D17": "2"
        ],
        rows: 22,
        cols: 30
    )
    try expectReaderReadsEachSetFromPlacement(SheetSnapshot(values: grid))
}
