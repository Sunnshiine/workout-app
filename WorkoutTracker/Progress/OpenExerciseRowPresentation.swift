import Foundation

/// Row readings for an Open Exercise: what to call it, how much is left, and
/// which Session it comes from. Kept out of the view layer so the makeup
/// affordance stays unit-testable.
struct OpenExerciseRowPresentation {
    let name: String
    let pendingSetLabel: String
    let sourceLabel: String

    @MainActor
    init(exercise: Exercise) {
        name = exercise.baseName

        let pendingSetCount = exercise.pendingSetCount
        pendingSetLabel = pendingSetCount == 1 ? "1 pending set" : "\(pendingSetCount) pending sets"

        if let session = exercise.session, let week = session.week {
            sourceLabel = "W\(week.number) D\(session.dayNumber)"
        } else {
            sourceLabel = ""
        }
    }
}
