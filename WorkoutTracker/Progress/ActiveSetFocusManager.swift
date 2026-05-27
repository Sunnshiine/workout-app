import Foundation
import Observation

struct ActiveSetID: Equatable, Hashable, Sendable {
    let exerciseOrder: Int
    let setIndex: Int
}

struct ActiveSetTransition: Equatable, Sendable {
    enum Kind: Equatable, Sendable {
        case momentumFlow
        case softFadeUp
        case collapseAndRise
    }

    let kind: Kind
    let outgoingSetID: ActiveSetID
    let incomingSetID: ActiveSetID?
    let completedExerciseOrder: Int?
}

@MainActor
@Observable
final class ActiveSetFocusManager {
    private(set) var activeSetID: ActiveSetID?
    private(set) var activeSetTransition: ActiveSetTransition?
    private(set) var scrollTargetID: ActiveSetID?
    private let supersetState = SupersetState()
    private var expandedCompletedExerciseOrders: Set<Int> = []

    init(session: Session?) {
        activeSetID = session.flatMap(Self.firstPendingSetID)
    }

    func reset(to session: Session?) {
        let nextSetID = session.flatMap(Self.firstPendingSetID)
        if let session {
            supersetState.refresh(in: session)
            activeSetID = supersetState.focusedSetID(whenNormalFocusIs: nextSetID, in: session)
        } else {
            activeSetID = nil
        }
        activeSetTransition = nil
        scrollTargetID = nil
        expandedCompletedExerciseOrders = []
    }

    func advanceAfterLog(_ set: ExerciseSet, in session: Session) {
        let nextSet = nextActiveSet(after: set, in: session)
        let completedExerciseOrder = completedExerciseOrder(containing: set)
        activeSetTransition = transition(
            kind: completedExerciseOrder == nil ? .momentumFlow : .collapseAndRise,
            from: set,
            to: nextSet.id,
            completedExerciseOrder: completedExerciseOrder
        )
        activeSetID = nextSet.id
        scrollTargetID = nextSet.activatesPlannedSuperset ? nextSet.id : nil
        collapseCompletedExercise(containing: set)
    }

    func advanceAfterSkip(_ set: ExerciseSet, in session: Session) {
        let nextSet = nextActiveSet(after: set, in: session)
        let completedExerciseOrder = completedExerciseOrder(containing: set)
        activeSetTransition = transition(
            kind: completedExerciseOrder == nil ? .softFadeUp : .collapseAndRise,
            from: set,
            to: nextSet.id,
            completedExerciseOrder: completedExerciseOrder
        )
        activeSetID = nextSet.id
        scrollTargetID = nextSet.activatesPlannedSuperset ? nextSet.id : nil
        collapseCompletedExercise(containing: set)
    }

    func focus(on set: ExerciseSet) {
        activeSetID = Self.id(for: set)
        activeSetTransition = nil
        scrollTargetID = nil
    }

    @discardableResult
    func createSuperset(with exercises: [Exercise], in session: Session) -> Bool {
        supersetState.createSuperset(with: exercises, in: session, currentActiveSetID: activeSetID)
    }

    func clearTransition(_ transition: ActiveSetTransition) {
        guard activeSetTransition == transition else { return }
        activeSetTransition = nil
    }

    func reexpand(_ exercise: Exercise) {
        guard Self.isCompleted(exercise) else { return }
        expandedCompletedExerciseOrders.insert(exercise.order)
    }

    func isCollapsed(_ exercise: Exercise) -> Bool {
        Self.isCompleted(exercise) && !expandedCompletedExerciseOrders.contains(exercise.order)
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

    private func collapseCompletedExercise(containing set: ExerciseSet) {
        guard let exercise = set.exercise, Self.isCompleted(exercise) else { return }
        expandedCompletedExerciseOrders.remove(exercise.order)
    }

    private func nextActiveSet(
        after set: ExerciseSet,
        in session: Session
    ) -> (
        id: ActiveSetID?,
        activatesPlannedSuperset: Bool
    ) {
        if let supersetNextSetID = supersetState.nextSetID(after: set, in: session) {
            return (supersetNextSetID, false)
        }
        let normalNextSetID = Self.nextPendingSetID(after: set, in: session)
        let activatesPlannedSuperset = supersetState.willActivatePlannedSuperset(
            whenNormalFocusIs: normalNextSetID,
            in: session
        )
        let nextSetID = supersetState.focusedSetID(whenNormalFocusIs: normalNextSetID, in: session)
        return (nextSetID, activatesPlannedSuperset)
    }

    private func transition(
        kind: ActiveSetTransition.Kind,
        from set: ExerciseSet,
        to incomingSetID: ActiveSetID?,
        completedExerciseOrder: Int?
    ) -> ActiveSetTransition? {
        guard let outgoingSetID = Self.id(for: set) else { return nil }
        return ActiveSetTransition(
            kind: kind,
            outgoingSetID: outgoingSetID,
            incomingSetID: incomingSetID,
            completedExerciseOrder: completedExerciseOrder
        )
    }

    private func completedExerciseOrder(containing set: ExerciseSet) -> Int? {
        guard let exercise = set.exercise, Self.isCompleted(exercise) else { return nil }
        return exercise.order
    }

    private static func isCompleted(_ exercise: Exercise) -> Bool {
        !exercise.sets.isEmpty && exercise.sets.allSatisfy { $0.state == .logged || $0.state == .skipped }
    }
}
