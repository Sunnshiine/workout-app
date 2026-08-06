import Foundation
import Testing

@testable import WorkoutTracker

// MARK: - Focus-week grouping

@MainActor
@Test func focusWeekIsTheOneHoldingTheCurrentSession() {
    let scenario = WorkoutScenarios.blockOverviewWithMixedSessionStates()

    let presentation = BlockOverviewPresentation(block: scenario.block, currentSession: scenario.currentSession)

    #expect(presentation.weeks.map(\.weekNumber) == [1, 2])
    // The Current Session lives in Week 1 (W1 D3), so Week 1 alone expands.
    #expect(presentation.weeks.map(\.isFocus) == [true, false])
}

@MainActor
@Test func brandNewBlockExpandsTheFirstWeekSoTheGridIsNeverFullyCollapsed() {
    let block = blockWithControlledSessions(weeks: [
        [.complete, .available],
        [.available, .available]
    ])

    let presentation = BlockOverviewPresentation(block: block, currentSession: nil)

    #expect(presentation.weeks.map(\.isFocus) == [true, false])
}

@MainActor
@Test func collapsedWeekSummaryCountsCompleteOverDayCountWithStateClause() {
    // Week 1: 2 complete of 3, the third partially logged → "in progress".
    // Week 2: 0 of 3 with one un-uploaded day → "not uploaded" wins over any progress.
    let block = blockWithControlledSessions(weeks: [
        [.complete, .complete, .partial],
        [.partial, .available, .unavailable]
    ])

    let presentation = BlockOverviewPresentation(block: block, currentSession: nil)

    #expect(presentation.weeks[0].summary == "2 of 3")
    #expect(presentation.weeks[0].detail == "· 1 in progress")
    #expect(presentation.weeks[0].collapsedSummary == "2 of 3 · 1 in progress")

    #expect(presentation.weeks[1].summary == "0 of 3")
    #expect(presentation.weeks[1].detail == "· 1 not uploaded")
}

@MainActor
@Test func settledWeekCarriesNoStateClause() {
    let block = blockWithControlledSessions(weeks: [[.complete, .complete]])

    let presentation = BlockOverviewPresentation(block: block, currentSession: nil)

    #expect(presentation.weeks[0].summary == "2 of 2")
    #expect(presentation.weeks[0].detail == "")
    #expect(presentation.weeks[0].collapsedSummary == "2 of 2")
}

@MainActor
@Test func emptyBedsGroupAtTheWeeksEnd() {
    // A middle day is the empty bed — it must sort to the Week's end.
    let block = blockWithControlledSessions(weeks: [[.available, .unavailable, .available]])

    let presentation = BlockOverviewPresentation(block: block, currentSession: nil)

    let tiles = presentation.weeks[0].tiles
    #expect(tiles.map(\.dayNumber) == [1, 3, 2])
    #expect(tiles.map(\.state) == [.incomplete, .incomplete, .unavailable])
}

@Test func fillQuartersQuantizesPartialProgressWithoutMistakingItForEmptyOrFull() {
    #expect(BlockOverviewTilePresentation.fillQuarters(completed: 0, total: 4) == 0)
    #expect(BlockOverviewTilePresentation.fillQuarters(completed: 4, total: 4) == 4)
    // A single logged Set of eight still shows a quarter (never reads as empty).
    #expect(BlockOverviewTilePresentation.fillQuarters(completed: 1, total: 8) == 1)
    #expect(BlockOverviewTilePresentation.fillQuarters(completed: 2, total: 4) == 2)
    // Seven of eight rounds toward full but clamps to 3 (never reads as complete).
    #expect(BlockOverviewTilePresentation.fillQuarters(completed: 7, total: 8) == 3)
}

/// A day's target state, expressed so a test can build a Block of exactly the tile states
/// it means to assert against without threading logged Sets by hand.
private enum DayState {
    case complete
    case partial
    case available
    case unavailable
}

@MainActor
private func blockWithControlledSessions(weeks: [[DayState]]) -> Block {
    let block = Block(tabName: "Block 27", squatTM: nil, benchTM: nil, deadliftTM: nil)
    block.weeks = weeks.enumerated().map { weekIndex, days in
        let week = Week(number: weekIndex + 1)
        week.sessions = days.enumerated().map { dayIndex, day in
            makeSession(dayNumber: dayIndex + 1, day: day)
        }
        return week
    }
    return block
}

@MainActor
private func makeSession(dayNumber: Int, day: DayState) -> Session {
    let session = Session(dayNumber: dayNumber, date: nil)
    guard day != .unavailable else {
        session.exercises = [] // an un-uploaded day carries no Exercises
        return session
    }
    let exercise = Exercise(name: "Squat", baseName: "Squat", cadence: nil, coachNote: nil, order: 0)
    exercise.sets = (0..<4).map { index in
        let state: SetState
        switch day {
        case .complete:
            state = .logged
        case .partial:
            state = index < 1 ? .logged : .pending // one settled Set of four → in progress
        case .available, .unavailable:
            state = .pending
        }
        return ExerciseSet(index: index, prescribedReps: "5", prescribedLoad: "RPE8", percentOneRM: nil, state: state)
    }
    session.exercises = [exercise]
    return session
}

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
