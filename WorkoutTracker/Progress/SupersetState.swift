import Foundation

struct SupersetExerciseIdentity: Equatable, Hashable, Sendable {
    let weekNumber: Int?
    let dayNumber: Int
    let exerciseOrder: Int
    let exerciseName: String
    let baseName: String

    init(exercise: Exercise) {
        weekNumber = exercise.session?.week?.number
        dayNumber = exercise.session?.dayNumber ?? 0
        exerciseOrder = exercise.order
        exerciseName = exercise.name
        baseName = exercise.baseName
    }
}

private struct SupersetPair: Equatable, Sendable {
    let first: SupersetExerciseIdentity
    let second: SupersetExerciseIdentity

    func contains(_ identity: SupersetExerciseIdentity) -> Bool {
        first == identity || second == identity
    }
}

@MainActor
final class SupersetState {
    private var pairs: [SupersetPair] = []
    private var activePair: SupersetPair?
    private var activeSetID: ActiveSetID?

    var supersetCount: Int { pairs.count }

    func canCreateSuperset(with exercises: [Exercise], in session: Session) -> Bool {
        guard exercises.count == 2 else { return false }
        let identities = exercises.map(SupersetExerciseIdentity.init)
        guard Set(identities).count == 2 else { return false }

        return exercises.allSatisfy { exercise in
            sessionContains(exercise, in: session)
                && hasPendingSet(exercise)
                && !isPaired(exercise)
        }
    }

    @discardableResult
    func createSuperset(
        with exercises: [Exercise],
        in session: Session,
        currentActiveSetID: ActiveSetID? = nil
    ) -> Bool {
        guard canCreateSuperset(with: exercises, in: session) else { return false }
        let pair = SupersetPair(
            first: SupersetExerciseIdentity(exercise: exercises[0]),
            second: SupersetExerciseIdentity(exercise: exercises[1])
        )
        pairs.append(pair)
        if let currentActiveSetID, self.pair(containing: currentActiveSetID, in: session) == pair {
            activePair = pair
            activeSetID = currentActiveSetID
        }
        return true
    }

    func focusedSetID(whenNormalFocusIs normalFocus: ActiveSetID?, in session: Session) -> ActiveSetID? {
        refresh(in: session)
        if let activePair, pairs.contains(activePair), let activeSetID, isPending(activeSetID, in: session) {
            return activeSetID
        }
        guard let normalFocus, let pair = pair(containing: normalFocus, in: session) else {
            return normalFocus
        }
        activePair = pair
        activeSetID = normalFocus
        return normalFocus
    }

    func nextSetID(after set: ExerciseSet, in session: Session) -> ActiveSetID? {
        guard
            let exercise = set.exercise,
            let pair = pair(containing: exercise)
        else {
            return nil
        }
        guard
            hasPendingSet(for: pair.first, in: session),
            hasPendingSet(for: pair.second, in: session)
        else {
            dissolve(pair)
            return nil
        }

        let currentIdentity = SupersetExerciseIdentity(exercise: exercise)
        let nextIdentity = pair.first == currentIdentity ? pair.second : pair.first
        let nextSetID = nextPendingSetID(for: nextIdentity, in: session)
        activePair = pair
        activeSetID = nextSetID
        return nextSetID
    }

    func focusNextPendingSet(for exercise: Exercise, in session: Session) -> ActiveSetID? {
        guard let pair = pair(containing: exercise) else { return nil }
        let nextSetID = nextPendingSetID(for: SupersetExerciseIdentity(exercise: exercise), in: session)
        activePair = pair
        activeSetID = nextSetID
        return nextSetID
    }

    func dismissSuperset(containing exercise: Exercise) {
        guard let pair = pair(containing: exercise) else { return }
        dissolve(pair)
    }

    func refresh(in session: Session) {
        pairs.removeAll { pair in
            !hasPendingSet(for: pair.first, in: session)
                || !hasPendingSet(for: pair.second, in: session)
        }
        if let activePair, !pairs.contains(activePair) {
            self.activePair = nil
            activeSetID = nil
        }
    }

    func isPaired(_ exercise: Exercise) -> Bool {
        let identity = SupersetExerciseIdentity(exercise: exercise)
        return pairs.contains { $0.contains(identity) }
    }

    private func sessionContains(_ exercise: Exercise, in session: Session) -> Bool {
        session.exercises.contains { candidate in candidate === exercise }
    }

    private func hasPendingSet(_ exercise: Exercise) -> Bool {
        exercise.sets.contains { $0.state == .pending }
    }

    private func pair(containing exercise: Exercise) -> SupersetPair? {
        let identity = SupersetExerciseIdentity(exercise: exercise)
        return pairs.first { $0.contains(identity) }
    }

    private func pair(containing setID: ActiveSetID, in session: Session) -> SupersetPair? {
        guard let exercise = exercise(containing: setID, in: session) else { return nil }
        return pair(containing: exercise)
    }

    private func hasPendingSet(for identity: SupersetExerciseIdentity, in session: Session) -> Bool {
        guard let exercise = exercise(matching: identity, in: session) else { return false }
        return hasPendingSet(exercise)
    }

    private func nextPendingSetID(for identity: SupersetExerciseIdentity, in session: Session) -> ActiveSetID? {
        guard let exercise = exercise(matching: identity, in: session) else { return nil }
        return exercise.sets
            .filter { $0.state == .pending }
            .sorted { $0.index < $1.index }
            .first
            .map { ActiveSetID(exerciseOrder: exercise.order, setIndex: $0.index) }
    }

    private func exercise(matching identity: SupersetExerciseIdentity, in session: Session) -> Exercise? {
        session.exercises.first { SupersetExerciseIdentity(exercise: $0) == identity }
    }

    private func exercise(containing setID: ActiveSetID, in session: Session) -> Exercise? {
        session.exercises.first { exercise in
            exercise.order == setID.exerciseOrder && exercise.sets.contains { $0.index == setID.setIndex }
        }
    }

    private func isPending(_ setID: ActiveSetID, in session: Session) -> Bool {
        exercise(containing: setID, in: session)?
            .sets
            .first { $0.index == setID.setIndex }?
            .state == .pending
    }

    private func dissolve(_ pair: SupersetPair) {
        pairs.removeAll { $0 == pair }
        if activePair == pair {
            activePair = nil
            activeSetID = nil
        }
    }
}
