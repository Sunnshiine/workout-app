import Testing

@testable import WorkoutTracker

@MainActor
@Test func blockOverviewPresentationBuildsOrderedTilesWithMixedSessionStates() {
    let scenario = WorkoutScenarios.blockOverviewWithMixedSessionStates()

    let presentation = BlockOverviewPresentation(block: scenario.block, currentSession: scenario.currentSession)

    #expect(presentation.title == "Block 27")
    #expect(presentation.tiles.map(\.weekNumber) == [1, 1, 1, 2])
    #expect(presentation.tiles.map(\.dayNumber) == [1, 2, 3, 1])
    #expect(presentation.tiles.map(\.state) == [.complete, .hasOpenExercises, .current, .upcoming])
    let identifiers = presentation.tiles.map(\.accessibilityIdentifier)
    #expect(identifiers == ["session-tile-W1-D1", "session-tile-W1-D2", "session-tile-W1-D3", "session-tile-W2-D1"])
}
