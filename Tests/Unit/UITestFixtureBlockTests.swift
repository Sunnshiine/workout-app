import Testing

@testable import WorkoutTracker

/// Every launch Scenario must boot, and each into its own distinctly shaped Block, so a missing or
/// swapped row of `UITestLaunch.scenarioFlags` fails here rather than in a UI run. The
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

/// Read in address order, because a Block fetched back from the store holds its relationships in
/// no particular order.
@MainActor
private func shape(of block: Block) -> BlockShape {
    let sessions = block.weeks.sorted { $0.number < $1.number }.flatMap { $0.sessions.sorted { $0.dayNumber < $1.dayNumber } }
    let exercises = sessions.flatMap { $0.exercises.sorted { $0.order < $1.order } }
    return BlockShape(
        tabName: block.tabName,
        weeks: block.weeks.count,
        sessions: sessions.count,
        exercises: exercises.count,
        sets: exercises.flatMap(\.sets).count,
        firstExercise: exercises.first?.name ?? "",
        loggedAt: exercises.flatMap { $0.sets.sorted { $0.index < $1.index } }.compactMap { $0.loggedAt?.ISO8601Format() }
    )
}

private let expectedShapes: [WorkbookScenario: BlockShape] = [
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
@Test func everyScenarioSeedsItsOwnFixtureBlock() async throws {
    #expect(Set(expectedShapes.values).count == expectedShapes.count)
    #expect(Set(expectedShapes.keys) == Set(UITestLaunch.scenarioFlags.map(\.scenario)))
    for scenario in UITestLaunch.scenarioFlags.map(\.scenario) {
        let booted = try await BootedFixture.boot(scenario)
        #expect(shape(of: try booted.block()) == expectedShapes[scenario], "\(scenario) seeded the wrong Block")
    }
}
