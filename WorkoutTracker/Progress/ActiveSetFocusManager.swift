import Foundation
import Observation

struct ActiveSetID: Equatable, Sendable {
    let exerciseOrder: Int
    let setIndex: Int
}

@MainActor
@Observable
final class ActiveSetFocusManager {
    private(set) var activeSetID: ActiveSetID?

    init(session: Session?) {
        activeSetID = session.flatMap(Self.firstPendingSetID)
    }

    func reset(to session: Session?) {
        activeSetID = session.flatMap(Self.firstPendingSetID)
    }

    func advanceAfterLog(_ set: ExerciseSet, in session: Session) {
        activeSetID = Self.nextPendingSetID(after: set, in: session)
    }

    func advanceAfterSkip(_ set: ExerciseSet, in session: Session) {
        activeSetID = Self.nextPendingSetID(after: set, in: session)
    }

    func focus(on set: ExerciseSet) {
        activeSetID = Self.id(for: set)
    }

    static func id(for set: ExerciseSet) -> ActiveSetID? {
        guard let exercise = set.exercise else { return nil }
        return ActiveSetID(exerciseOrder: exercise.order, setIndex: set.index)
    }

    private static func firstPendingSetID(in session: Session) -> ActiveSetID? {
        sortedExercises(in: session)
            .lazy
            .flatMap { exercise in
                sortedSets(in: exercise).map { set in
                    (exercise: exercise, set: set)
                }
            }
            .first { $0.set.state == .pending }
            .map { ActiveSetID(exerciseOrder: $0.exercise.order, setIndex: $0.set.index) }
    }

    private static func nextPendingSetID(after set: ExerciseSet, in session: Session) -> ActiveSetID? {
        guard let currentID = id(for: set) else {
            return firstPendingSetID(in: session)
        }
        return orderedSets(in: session)
            .drop { pair in
                ActiveSetID(exerciseOrder: pair.exercise.order, setIndex: pair.set.index) != currentID
            }
            .dropFirst()
            .first { $0.set.state == .pending }
            .map { ActiveSetID(exerciseOrder: $0.exercise.order, setIndex: $0.set.index) }
            ?? firstPendingSetID(in: session)
    }

    private static func orderedSets(in session: Session) -> [(exercise: Exercise, set: ExerciseSet)] {
        sortedExercises(in: session).flatMap { exercise in
            sortedSets(in: exercise).map { set in
                (exercise: exercise, set: set)
            }
        }
    }

    private static func sortedExercises(in session: Session) -> [Exercise] {
        session.exercises.sorted { $0.order < $1.order }
    }

    private static func sortedSets(in exercise: Exercise) -> [ExerciseSet] {
        exercise.sets.sorted { $0.index < $1.index }
    }
}
