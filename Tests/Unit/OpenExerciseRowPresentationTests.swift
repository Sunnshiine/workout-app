import Foundation
import Testing

@testable import WorkoutTracker

@MainActor
@Test func openExerciseRowReadsBaseNameSetsAndSource() throws {
    let scenario = WorkoutScenarios.openExercises()
    let current = try #require(scenario.currentSession)
    let open = scenario.tracker.openExercises(for: current)
    let backSquat = try #require(open.first).exercise

    let row = OpenExerciseRowPresentation(exercise: backSquat)

    #expect(row.name == "Back Squat")
    #expect(row.sets.map(\.id) == backSquat.sortedSets.map(\.id))
    #expect(row.sessionAddressLabel == "W1 D1")
}

@MainActor
@Test func openExerciseRowOmitsSourceWithoutSession() throws {
    let exercise = Exercise(name: "Back Squat", coachNote: nil)

    let row = OpenExerciseRowPresentation(exercise: exercise)

    #expect(row.sessionAddressLabel.isEmpty)
}
