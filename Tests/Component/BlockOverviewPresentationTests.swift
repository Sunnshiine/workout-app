import Testing

@testable import WorkoutTracker

@MainActor
@Test func blockOverviewPresentationBuildsOrderedTilesWithMixedSessionStates() {
    let scenario = WorkoutScenarios.blockOverviewWithMixedSessionStates()

    let presentation = BlockOverviewPresentation(block: scenario.block, currentSession: scenario.currentSession)

    #expect(presentation.title == "Block 27")
    #expect(presentation.tiles.map(\.weekNumber) == [1, 1, 1, 2])
    #expect(presentation.tiles.map(\.dayNumber) == [1, 2, 3, 1])
    #expect(presentation.tiles.map(\.state) == [.complete, .incomplete, .current, .incomplete])
    #expect(presentation.tiles.map(\.accessibilityValue) == ["Complete", "Incomplete", "Current", "Incomplete"])
    let identifiers = presentation.tiles.map(\.accessibilityIdentifier)
    #expect(identifiers == ["session-tile-W1-D1", "session-tile-W1-D2", "session-tile-W1-D3", "session-tile-W2-D1"])
}

@MainActor
private func uniformDayBlock(daysPerWeek: Int, weeks: Int = 2) -> Block {
    BlockBuilder.makeBlock(
        from: ParsedBlockModel(
            tabName: "Block 27",
            weeks: (1...weeks).map { w in
                ParsedWeek(
                    number: w,
                    days: (1...daysPerWeek).map { d in
                        ParsedSession(
                            dayNumber: d,
                            date: nil,
                            exercises: [
                                ParsedExercise(
                                    name: "Squat",
                                    baseName: "Squat",
                                    cadence: nil,
                                    coachNote: nil,
                                    sets: [ParsedSet(index: 0, prescribedReps: "5", prescribedLoad: "RPE8", percentOneRM: nil)]
                                )
                            ]
                        )
                    }
                )
            }
        )
    )
}

@MainActor
@Test func columnCountMatchesBlockDayWidth() {
    #expect(BlockOverviewPresentation(block: uniformDayBlock(daysPerWeek: 3), currentSession: nil).columnCount == 3)
    #expect(BlockOverviewPresentation(block: uniformDayBlock(daysPerWeek: 6), currentSession: nil).columnCount == 6)

    // The existing 4-day (partially uploaded) Block still renders four columns.
    let scenario = WorkoutScenarios.partiallyUploadedBlock()
    #expect(
        BlockOverviewPresentation(block: scenario.block, currentSession: scenario.currentSession).columnCount == 4
    )
}

@MainActor
@Test func blockOverviewPresentationMarksUnavailableSessionsInPartiallyUploadedBlock() {
    let scenario = WorkoutScenarios.partiallyUploadedBlock()

    let presentation = BlockOverviewPresentation(block: scenario.block, currentSession: scenario.currentSession)

    #expect(presentation.tiles.count == 16)
    #expect(
        presentation.tiles
            .filter { $0.state != .unavailable }
            .map { "W\($0.weekNumber)D\($0.dayNumber)" }
            == ["W1D1", "W1D2", "W2D1", "W3D1", "W4D1"]
    )

    let unavailable = presentation.tiles.first { $0.weekNumber == 1 && $0.dayNumber == 3 }
    #expect(unavailable?.state == .unavailable)
    #expect(unavailable?.accessibilityValue == "Not uploaded")
    #expect(unavailable?.accessibilityIdentifier == "session-tile-W1-D3")
}

// MARK: - Focus-week layout (slice 4, DESIGN.md §5.5)

@MainActor
@Test func focusWeekIsTheWeekHoldingTheCurrentSession() {
    let scenario = WorkoutScenarios.blockOverviewWithMixedSessionStates()

    let presentation = BlockOverviewPresentation(block: scenario.block, currentSession: scenario.currentSession)

    // The Current Session lives in Week 1, so Week 1 alone expands into morning light;
    // Week 2 collapses to a shaded card.
    #expect(presentation.weeks.map(\.weekNumber) == [1, 2])
    #expect(presentation.weeks.map(\.isFocus) == [true, false])
    #expect(presentation.weeks.map(\.tiles.count) == [3, 1])
}

@MainActor
@Test func focusWeekFallsBackToTheFirstWeekWithoutACurrentSession() {
    let scenario = WorkoutScenarios.blockOverviewWithMixedSessionStates()

    let presentation = BlockOverviewPresentation(block: scenario.block, currentSession: nil)

    #expect(presentation.weeks.map(\.isFocus) == [true, false])
}

@MainActor
@Test func collapsedWeekCardSummarizesCompletedOverAvailableSessions() {
    let scenario = WorkoutScenarios.blockOverviewWithMixedSessionStates()

    let presentation = BlockOverviewPresentation(block: scenario.block, currentSession: scenario.currentSession)

    // Week 1: one of three available Sessions is complete; Week 2: none of its one done.
    #expect(presentation.weeks.map(\.summary) == ["1 / 3", "0 / 1"])
}

@MainActor
@Test func partiallyLoggedTileFillsFromTheFootInQuarters() {
    let scenario = WorkoutScenarios.blockOverviewWithMixedSessionStates()

    let presentation = BlockOverviewPresentation(block: scenario.block, currentSession: scenario.currentSession)

    // W1D1 complete → full ink; W1D2 has one of two Sets settled → two quarters; the
    // untouched current and upcoming Sessions rise from an empty foot.
    #expect(presentation.tiles.map(\.fillQuarters) == [4, 2, 0, 0])
}

@Test func fillQuartersQuantizesPartialProgressBetweenEmptyAndFull() {
    // Nothing settled reads as an empty foot; everything settled reads as full ink.
    #expect(BlockOverviewTilePresentation.fillQuarters(completed: 0, total: 5) == 0)
    #expect(BlockOverviewTilePresentation.fillQuarters(completed: 5, total: 5) == 4)
    // Any partial progress lands in 1...3 — never mistaken for empty or complete.
    #expect(BlockOverviewTilePresentation.fillQuarters(completed: 1, total: 100) == 1)
    #expect(BlockOverviewTilePresentation.fillQuarters(completed: 1, total: 4) == 1)
    #expect(BlockOverviewTilePresentation.fillQuarters(completed: 2, total: 4) == 2)
    #expect(BlockOverviewTilePresentation.fillQuarters(completed: 3, total: 4) == 3)
    #expect(BlockOverviewTilePresentation.fillQuarters(completed: 7, total: 8) == 3)
    // A Session carrying no prescribed Sets can't rise from its foot.
    #expect(BlockOverviewTilePresentation.fillQuarters(completed: 0, total: 0) == 0)
}

@MainActor
@Test func unavailableSessionsGroupAsEmptyBedsAtTheWeeksEnd() {
    // A Week whose *middle* day is un-uploaded groups it after the available days.
    let block = BlockBuilder.makeBlock(
        from: ParsedBlockModel(
            tabName: "Block 27",
            weeks: [
                ParsedWeek(number: 1, days: [availableDay(1), emptyBedDay(2), availableDay(3)])
            ]
        )
    )

    let presentation = BlockOverviewPresentation(block: block, currentSession: nil)

    #expect(presentation.tiles.map(\.dayNumber) == [1, 3, 2])
    #expect(presentation.tiles.map(\.state) == [.incomplete, .incomplete, .unavailable])
    #expect(presentation.weeks.first?.tiles.map(\.dayNumber) == [1, 3, 2])
}

@MainActor
private func availableDay(_ dayNumber: Int) -> ParsedSession {
    ParsedSession(
        dayNumber: dayNumber,
        date: nil,
        exercises: [
            ParsedExercise(
                name: "Squat",
                baseName: "Squat",
                cadence: nil,
                coachNote: nil,
                sets: [ParsedSet(index: 0, prescribedReps: "5", prescribedLoad: "RPE8", percentOneRM: nil)]
            )
        ]
    )
}

@MainActor
private func emptyBedDay(_ dayNumber: Int) -> ParsedSession {
    ParsedSession(dayNumber: dayNumber, date: nil, exercises: [])
}
