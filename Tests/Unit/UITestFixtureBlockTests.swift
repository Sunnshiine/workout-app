import Testing

@testable import WorkoutTracker

/// `UITestFixture.blocks` is a table, so the compiler cannot tell a new scenario that it needs a
/// row. These expectations do: every scenario must resolve, and each must resolve to its own
/// distinctly shaped Block, so a missing or swapped row fails here rather than in a UI run. The
/// shape also lists every seeded `loggedAt`. The Sheet never carries one, so no fixture Set does.

private struct BlockShape: Hashable {
    var tabName: String
    var weeks: Int
    var sessions: Int
    var exercises: Int
    var sets: Int
    var firstExercise: String
    var loggedAt: [String] = []
}

@MainActor
private func shape(of scenario: UITestLaunch.Scenario) -> BlockShape {
    let block = UITestFixture.block(for: scenario)
    let sessions = block.weeks.flatMap(\.sessions)
    let exercises = sessions.flatMap(\.exercises)
    return BlockShape(
        tabName: block.tabName,
        weeks: block.weeks.count,
        sessions: sessions.count,
        exercises: exercises.count,
        sets: exercises.flatMap(\.sets).count,
        firstExercise: exercises.first?.name ?? "",
        loggedAt: exercises.flatMap(\.sets).compactMap { $0.loggedAt?.ISO8601Format() }
    )
}

private let expectedShapes: [UITestLaunch.Scenario: BlockShape] = [
    .perfectMoveOnCelebration: BlockShape(
        tabName: "Block 27",
        weeks: 1,
        sessions: 2,
        exercises: 1,
        sets: 2,
        firstExercise: "Back Squat"
    ),
    .completedOpenExercises: BlockShape(
        tabName: "Block 27",
        weeks: 1,
        sessions: 3,
        exercises: 3,
        sets: 5,
        firstExercise: "Back Squat"
    ),
    .openExercises: BlockShape(
        tabName: "Block 27",
        weeks: 1,
        sessions: 3,
        exercises: 3,
        sets: 6,
        firstExercise: "Back Squat"
    ),
    .longSession: BlockShape(
        tabName: "Block 27",
        weeks: 1,
        sessions: 1,
        exercises: 8,
        sets: 8,
        firstExercise: "Primer Row"
    ),
    .fullBlock: BlockShape(
        tabName: "Block 27",
        weeks: 4,
        sessions: 16,
        exercises: 18,
        sets: 24,
        firstExercise: "Back Squat"
    ),
    .partialUpload: BlockShape(
        tabName: "Block 27",
        weeks: 4,
        sessions: 16,
        exercises: 7,
        sets: 13,
        firstExercise: "Back Squat"
    )
]

@MainActor
@Test func everyScenarioSeedsItsOwnFixtureBlock() {
    #expect(UITestLaunch.Scenario.allCases.count == 6)
    #expect(Set(expectedShapes.values).count == 6)
    for scenario in UITestLaunch.Scenario.allCases {
        #expect(shape(of: scenario) == expectedShapes[scenario], "\(scenario) seeded the wrong Block")
    }
}
