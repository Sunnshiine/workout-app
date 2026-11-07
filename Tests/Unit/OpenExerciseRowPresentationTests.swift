import Foundation
import Testing

@testable import WorkoutTracker

@MainActor
@Test func openExerciseRowReadsBaseNameSetsAndSource() throws {
    let scenario = WorkoutScenarios.openExercises()
    let current = try #require(scenario.currentSession)
    let open = scenario.tracker.openExercises(for: current)
    let backSquat = try #require(open.first).exercise

    backSquat.sets.insert(
        ExerciseSet(index: 5, prescribedReps: "5", prescribedLoad: "RPE8", percentOneRM: nil, state: .pending),
        at: 0
    )

    let row = OpenExerciseRowPresentation(exercise: backSquat)

    #expect(row.name == "Back Squat")
    #expect(row.sets.map(\.index) == row.sets.map(\.index).sorted())
    #expect(row.sessionAddressLabel == "W1 D1")
}

@MainActor
@Test func openExerciseRowOmitsSourceWithoutSession() throws {
    let exercise = Exercise(name: "Back Squat", coachNote: nil)

    let row = OpenExerciseRowPresentation(exercise: exercise)

    #expect(row.sessionAddressLabel.isEmpty)
}
