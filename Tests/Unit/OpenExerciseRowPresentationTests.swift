import Foundation
import Testing

@testable import WorkoutTracker

@MainActor
@Test func openExerciseRowReadsBaseNamePendingSetsAndSource() throws {
    let scenario = WorkoutScenarios.openExercises()
    let current = try #require(scenario.currentSession)
    let open = scenario.tracker.openExercises(inCurrentWeekOf: current)
    let backSquat = try #require(open.first)

    let row = OpenExerciseRowPresentation(exercise: backSquat)

    #expect(row.name == "Back Squat")
    #expect(row.pendingSetLabel == "1 pending set")
    #expect(row.sourceLabel == "W1 D1")
}

@MainActor
@Test func openExerciseRowPluralizesPendingSets() throws {
    let scenario = WorkoutScenarios.openExercises()
    let current = try #require(scenario.currentSession)
    let open = scenario.tracker.openExercises(inCurrentWeekOf: current)
    let backSquat = try #require(open.first)
    backSquat.sets.append(
        ExerciseSet(index: 2, prescribedReps: "5", prescribedLoad: "RPE8", percentOneRM: nil, state: .pending)
    )

    let row = OpenExerciseRowPresentation(exercise: backSquat)

    #expect(row.pendingSetLabel == "2 pending sets")
}

@MainActor
@Test func openExerciseRowOmitsSourceWithoutSession() throws {
    let exercise = Exercise(name: "Back Squat", baseName: "Back Squat", cadence: nil, coachNote: nil)

    let row = OpenExerciseRowPresentation(exercise: exercise)

    #expect(row.sourceLabel.isEmpty)
}
