import Foundation

/// Row readings for an Open Exercise: what to call it, its Sets, and which
/// Session it comes from. Kept out of the view layer so the makeup
/// affordance stays unit-testable.
struct OpenExerciseRowPresentation {
    let name: String
    let sets: [ExerciseSet]
    let sessionAddressLabel: String

    @MainActor
    init(exercise: Exercise) {
        name = exercise.exerciseName.base
        sets = exercise.sortedSets
        sessionAddressLabel = exercise.session?.address?.sessionLabel ?? ""
    }
}
