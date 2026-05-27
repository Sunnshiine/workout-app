import Testing

@testable import WorkoutTracker

@MainActor
@Test func blockOverviewPresentationBuildsOrderedTilesWithMixedSessionStates() {
    let complete = makeSession(weekNumber: 1, dayNumber: 1, setStates: [.logged, .skipped])
    let hasOpenExercises = makeSession(weekNumber: 1, dayNumber: 2, setStates: [.logged, .pending])
    let current = makeSession(weekNumber: 1, dayNumber: 3, setStates: [.pending, .pending])
    let upcoming = makeSession(weekNumber: 2, dayNumber: 1, setStates: [.pending, .pending])
    let block = makeBlock(sessions: [upcoming, current, hasOpenExercises, complete])

    let presentation = BlockOverviewPresentation(block: block, currentSession: current)

    #expect(presentation.title == "Block 40")
    #expect(presentation.tiles.map(\.weekNumber) == [1, 1, 1, 2])
    #expect(presentation.tiles.map(\.dayNumber) == [1, 2, 3, 1])
    #expect(presentation.tiles.map(\.state) == [.complete, .hasOpenExercises, .current, .upcoming])
    let identifiers = presentation.tiles.map(\.accessibilityIdentifier)
    #expect(identifiers == ["session-tile-W1-D1", "session-tile-W1-D2", "session-tile-W1-D3", "session-tile-W2-D1"])
}
