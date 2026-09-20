import Foundation

/// One position in a Session's Set order: the `(exercise, set)` pair the walk
/// visits, plus the projection to `ActiveSetID` the focus engine and the Live
/// Activity widget need. Callers read whichever face they want — the Set, its
/// owning Exercise, or the id — without re-deriving the pairing.
struct SessionSetPosition {
    let exercise: Exercise
    let set: ExerciseSet

    var setID: ActiveSetID {
        ActiveSetID(exerciseOrder: exercise.order, setIndex: set.index)
    }
}

/// The single owner of **Pending Set order within a Session**: the answer to
/// "given the athlete's Sets, what is the *first* / *next* Pending Set, in
/// Exercise order then Set-index order?"
///
/// Three consumers used to each re-walk this ordering by hand — the on-screen
/// Active Set (`ActiveSetFocusManager`), the Live Activity rest widget's "up
/// next" (`LiveActivityRestContentBuilder`), and the Stage
/// (`SessionStagePresentation`) — spelling the Pending predicate two different
/// ways for the same concept. This owner states the ordering, the Pending
/// predicate, and the first/next/wrap-around rule exactly once; those consumers
/// keep their own policy layers on top but stop owning the walk.
///
/// Pending is decided by exactly one predicate: `ExerciseSet.isPending`.
enum SessionSetOrder {
    /// The Session's Sets in Exercise-order then Set-index order — the one
    /// definition of that ordering.
    static func orderedSets(in session: Session) -> [SessionSetPosition] {
        orderedSets(in: session.exercises)
    }

    /// The given Exercises' Sets in Exercise-order then Set-index order. The
    /// Stage walks a single render item's Exercises through this same primitive
    /// rather than re-sorting them itself.
    static func orderedSets(in exercises: [Exercise]) -> [SessionSetPosition] {
        exercises
            .sorted { $0.order < $1.order }
            .flatMap { exercise in
                exercise.sets
                    .sorted { $0.index < $1.index }
                    .map { SessionSetPosition(exercise: exercise, set: $0) }
            }
    }

    /// The first Pending Set in Session order, or `nil` when nothing is Pending.
    static func firstPendingSet(in session: Session) -> SessionSetPosition? {
        firstPendingSet(in: session.exercises)
    }

    /// The first Pending Set across the given Exercises, in Set order.
    static func firstPendingSet(in exercises: [Exercise]) -> SessionSetPosition? {
        orderedSets(in: exercises).first { $0.set.isPending }
    }

    /// The next Pending Set after `set` in Session order, wrapping back to the
    /// first Pending Set when `set` is the last one — or when `set` is not part
    /// of the Session's order (e.g. it has no owning Exercise).
    static func nextPendingSet(after set: ExerciseSet, in session: Session) -> SessionSetPosition? {
        guard let exercise = set.exercise else {
            return firstPendingSet(in: session)
        }
        let currentID = SessionSetPosition(exercise: exercise, set: set).setID
        let ordered = orderedSets(in: session)
        return
            ordered
            .drop { $0.setID != currentID }
            .dropFirst()
            .first { $0.set.isPending }
            ?? ordered.first { $0.set.isPending }
    }
}
