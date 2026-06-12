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
