import Foundation

/// Row readings for an Open Exercise: what to call it, how much is left, and
/// which Session it comes from. Kept out of the view layer so the makeup
/// affordance stays unit-testable.
struct OpenExerciseRowPresentation {
    let name: String
    let pendingSetLabel: String
    let sessionAddressLabel: String

    @MainActor
    init(exercise: Exercise) {
        name = exercise.exerciseName.base

        let pendingSetCount = exercise.pendingSetCount
        pendingSetLabel = pendingSetCount == 1 ? "1 Set left" : "\(pendingSetCount) Sets left"

        sessionAddressLabel = exercise.session?.address?.sessionLabel ?? ""
    }
}
