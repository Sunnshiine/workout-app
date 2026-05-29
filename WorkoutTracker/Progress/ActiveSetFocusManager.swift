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

struct SupersetSectionState {
    let presentation: ActiveSupersetPresentation
    let exercises: [Exercise]
}

@MainActor
@Observable
final class ActiveSetFocusManager {
    private(set) var activeSetID: ActiveSetID?
    private(set) var expandedLoggedSetID: ActiveSetID?
    private(set) var activeSetTransition: ActiveSetTransition?
    private(set) var scrollTargetID: ActiveSetID?
    private(set) var supersetScrollTargetOrder: Int?
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
        expandedLoggedSetID = nil
        scrollTargetID = nil
        supersetScrollTargetOrder = nil
        expandedCompletedExerciseOrders = []
    }

    func advanceAfterLog(_ set: ExerciseSet, in session: Session) {
        expandedLoggedSetID = nil
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
        expandedLoggedSetID = nil
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
        guard let setID = Self.id(for: set) else { return }
        if set.state == .logged {
            expandedLoggedSetID = expandedLoggedSetID == setID ? nil : setID
            activeSetTransition = nil
            scrollTargetID = nil
            supersetScrollTargetOrder = nil
            return
        }

        expandedLoggedSetID = nil
        activeSetID = setID
        activeSetTransition = nil
        scrollTargetID = nil
        supersetScrollTargetOrder = nil
    }

    func collapseLoggedSetReview() {
        expandedLoggedSetID = nil
    }

    func canPair(_ exercise: Exercise, in session: Session) -> Bool {
        session.exercises.contains { candidate in
            candidate !== exercise
                && supersetState.canCreateSuperset(with: [exercise, candidate], in: session)
        }
    }

    @discardableResult
    func createSuperset(with exercises: [Exercise], in session: Session) -> Bool {
        guard supersetState.createSuperset(with: exercises, in: session, currentActiveSetID: activeSetID) else {
            return false
        }
        supersetScrollTargetOrder = exercises.map(\.order).min()
        return true
    }

    @discardableResult
    func createSuperset(from source: Exercise, to target: Exercise, in session: Session) -> Bool {
        createSuperset(with: [source, target], in: session)
    }

    func dismissSuperset(containing exercise: Exercise, in session: Session) {
        supersetState.dismissSuperset(containing: exercise)
        supersetScrollTargetOrder = nil
        activeSetID = supersetState.focusedSetID(whenNormalFocusIs: activeSetID, in: session)
    }

    func supersetSections(in session: Session) -> [SupersetSectionState] {
        let pairs = supersetState.exercisePairs(in: session)
        let sections = pairs.compactMap { sectionState(for: $0) }
        return sections.sorted {
            ($0.presentation.containerExerciseOrder ?? Int.max)
                < ($1.presentation.containerExerciseOrder ?? Int.max)
        }
    }

    func activeSupersetPresentation(in session: Session) -> ActiveSupersetPresentation? {
        supersetSections(in: session).first { $0.presentation.activeExerciseOrder != nil }?.presentation
    }

    func activeSupersetExercises(in session: Session) -> [Exercise] {
        supersetState.activeExercises(in: session)
    }

    @discardableResult
    func focusNextSupersetSet(for exercise: Exercise, in session: Session) -> Bool {
        guard let nextSetID = supersetState.focusNextPendingSet(for: exercise, in: session) else {
            return false
        }
        activeSetID = nextSetID
        activeSetTransition = nil
        scrollTargetID = nextSetID
        supersetScrollTargetOrder = nil
        return true
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

    private func sectionState(for exercises: [Exercise]) -> SupersetSectionState? {
        let sectionActiveSetID = activeSetID(containedIn: exercises)
        guard let presentation = ActiveSupersetPresentation(exercises: exercises, activeSetID: sectionActiveSetID) else {
            return nil
        }
        return SupersetSectionState(presentation: presentation, exercises: exercises)
    }

    private func activeSetID(containedIn exercises: [Exercise]) -> ActiveSetID? {
        guard let activeSetID else { return nil }
        return exercises.contains { $0.order == activeSetID.exerciseOrder } ? activeSetID : nil
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
