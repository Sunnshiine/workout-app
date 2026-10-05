import Foundation
import Observation

/// Which Exercise a Superset side names. Sheet order stays out, so a coach who reorders the Sheet
/// keeps the pair. The Block tab stays in, because a coach reuses the template between Blocks.
struct SupersetExerciseIdentity: Hashable, Sendable {
    let session: SessionReparseIdentity
    let exerciseName: String
    let baseName: String

    init(exercise: Exercise) {
        session = exercise.session?.reparseIdentity ?? .weekless(dayNumber: 0)
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

    /// The side the alternation moves to from `identity`.
    func other(than identity: SupersetExerciseIdentity) -> SupersetExerciseIdentity {
        first == identity ? second : first
    }
}

/// Reads are pure: they filter to live pairs and never write. Only `ActiveSetFocusManager`'s
/// write paths prune and reconcile, through `refresh(in:)` and `focusedSetID(whenNormalFocusIs:in:)`.
@MainActor
@Observable
final class SupersetState {
    private var pairs: [SupersetPair] = []
    private var activePair: SupersetPair?
    private var activeSetID: ActiveSetID?
    private var activeSetExerciseIdentity: SupersetExerciseIdentity?

    func canCreateSuperset(with exercises: [Exercise], in session: Session) -> Bool {
        guard exercises.count == 2 else { return false }
        let identities = exercises.map(SupersetExerciseIdentity.init)
        guard Set(identities).count == 2 else { return false }

        return exercises.allSatisfy { exercise in
            sessionContains(exercise, in: session)
                && exercise.hasPendingSet
                && !isPaired(exercise, in: session)
        }
    }

    @discardableResult
    func createSuperset(
        with exercises: [Exercise],
        in session: Session,
        currentActiveSetID: ActiveSetID? = nil
    ) -> Bool {
        guard canCreateSuperset(with: exercises, in: session) else { return false }
        pairs = livePairs(in: session)
        let pair = SupersetPair(
            first: SupersetExerciseIdentity(exercise: exercises[0]),
            second: SupersetExerciseIdentity(exercise: exercises[1])
        )
        pairs.append(pair)
        if let currentActiveSetID, self.pair(containing: currentActiveSetID, in: session) == pair {
            activePair = pair
            activeSetID = currentActiveSetID
            activeSetExerciseIdentity = exercise(containing: currentActiveSetID, in: session).map(SupersetExerciseIdentity.init)
        }
        return true
    }

    func focusedSetID(whenNormalFocusIs normalFocus: ActiveSetID?, in session: Session) -> ActiveSetID? {
        refresh(in: session)
        if let liveActiveSetID = liveActiveSetID(in: session) {
            return liveActiveSetID
        }
        guard let normalFocus, let pair = pair(containing: normalFocus, in: session) else {
            return normalFocus
        }
        activePair = pair
        activeSetID = normalFocus
        activeSetExerciseIdentity = exercise(containing: normalFocus, in: session).map(SupersetExerciseIdentity.init)
        return normalFocus
    }

    func nextSetID(after set: ExerciseSet, in session: Session) -> ActiveSetID? {
        guard
            let exercise = set.exercise,
            let pair = pair(containing: exercise, in: session)
        else {
            return nil
        }

        let nextIdentity = pair.other(than: SupersetExerciseIdentity(exercise: exercise))
        let nextSetID = nextPendingSetID(for: nextIdentity, in: session)
        activePair = pair
        activeSetID = nextSetID
        activeSetExerciseIdentity = nextSetID == nil ? nil : nextIdentity
        return nextSetID
    }

    /// Whether `focusNextPendingSet(for:in:)` would move focus. Pure.
    func canFocusNextPendingSet(for exercise: Exercise, in session: Session) -> Bool {
        guard pair(containing: exercise, in: session) != nil else { return false }
        return nextPendingSetID(for: SupersetExerciseIdentity(exercise: exercise), in: session) != nil
    }

    func focusNextPendingSet(for exercise: Exercise, in session: Session) -> ActiveSetID? {
        guard let pair = pair(containing: exercise, in: session) else { return nil }
        let identity = SupersetExerciseIdentity(exercise: exercise)
        guard let nextSetID = nextPendingSetID(for: identity, in: session) else { return nil }
        activePair = pair
        activeSetID = nextSetID
        activeSetExerciseIdentity = identity
        return nextSetID
    }

    func dismissSuperset(containing exercise: Exercise, in session: Session) {
        guard let pair = pair(containing: exercise, in: session) else { return }
        dissolve(pair)
    }

    func exercisePairs(in session: Session) -> [[Exercise]] {
        livePairs(in: session).compactMap { pair in
            let exercises = [pair.first, pair.second].compactMap { identity in
                exercise(matching: identity, in: session)
            }
            return exercises.count == 2 ? exercises : nil
        }
    }

    func refresh(in session: Session) {
        pairs = livePairs(in: session)
        if let activePair, !pairs.contains(activePair) {
            self.activePair = nil
            activeSetID = nil
            activeSetExerciseIdentity = nil
        } else {
            reconcileActiveSet(in: session)
        }
    }

    func isPaired(_ exercise: Exercise, in session: Session) -> Bool {
        pair(containing: exercise, in: session) != nil
    }

    /// The Exercise's next Pending Set — the first Pending Set by Set index, or `nil` when the
    /// Exercise has no Pending Set. This is the single home for the *ordering-and-first* rule the
    /// Superset alternation is built from. It is pure, side-effect-free, and per-Exercise: it needs
    /// neither a `SupersetState` instance nor a `Session` handle, so read-only callers (view bodies,
    /// presentation initializers) can ask the owner for the selection whether they consume it as a
    /// Set or as a projected `ActiveSetID`.
    static func nextPendingSet(for exercise: Exercise) -> ExerciseSet? {
        exercise.sets
            .filter(\.isPending)
            .sorted { $0.index < $1.index }
            .first
    }

    /// The Exercise's next Pending Set projected to an `ActiveSetID` — see `nextPendingSet(for:)`.
    static func nextPendingSetID(for exercise: Exercise) -> ActiveSetID? {
        nextPendingSet(for: exercise)
            .map { ActiveSetID(exerciseOrder: exercise.order, setIndex: $0.index) }
    }

    private func sessionContains(_ exercise: Exercise, in session: Session) -> Bool {
        session.exercises.contains { candidate in candidate === exercise }
    }

    /// A pair alternates only while both sides still have somewhere to go. When one side runs out,
    /// the Superset is over, whether or not a write has pruned it from `pairs` yet.
    private func livePairs(in session: Session) -> [SupersetPair] {
        pairs.filter { bothSidesHavePendingSet($0, in: session) }
    }

    private func pair(containing exercise: Exercise, in session: Session) -> SupersetPair? {
        let identity = SupersetExerciseIdentity(exercise: exercise)
        return livePairs(in: session).first { $0.contains(identity) }
    }

    private func pair(containing setID: ActiveSetID, in session: Session) -> SupersetPair? {
        guard let exercise = exercise(containing: setID, in: session) else { return nil }
        return pair(containing: exercise, in: session)
    }

    /// The Superset's own focus survives only while its pair is still paired and the Set it holds
    /// is still Pending; otherwise normal Session focus takes over.
    private func liveActiveSetID(in session: Session) -> ActiveSetID? {
        guard
            let activePair,
            pairs.contains(activePair),
            let activeSetID,
            isPending(activeSetID, in: session)
        else {
            return nil
        }
        return activeSetID
    }

    private func bothSidesHavePendingSet(_ pair: SupersetPair, in session: Session) -> Bool {
        hasPendingSet(for: pair.first, in: session) && hasPendingSet(for: pair.second, in: session)
    }

    private func hasPendingSet(for identity: SupersetExerciseIdentity, in session: Session) -> Bool {
        guard let exercise = exercise(matching: identity, in: session) else { return false }
        return exercise.hasPendingSet
    }

    private func nextPendingSetID(for identity: SupersetExerciseIdentity, in session: Session) -> ActiveSetID? {
        guard let exercise = exercise(matching: identity, in: session) else { return nil }
        return Self.nextPendingSetID(for: exercise)
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
            .isPending ?? false
    }

    private func reconcileActiveSet(in session: Session) {
        guard
            let activeSetID,
            let activeSetExerciseIdentity
        else {
            return
        }
        guard
            let exercise = exercise(matching: activeSetExerciseIdentity, in: session),
            exercise.sets.contains(where: { $0.index == activeSetID.setIndex })
        else {
            self.activeSetID = nil
            self.activeSetExerciseIdentity = nil
            return
        }
        self.activeSetID = ActiveSetID(exerciseOrder: exercise.order, setIndex: activeSetID.setIndex)
    }

    private func dissolve(_ pair: SupersetPair) {
        pairs.removeAll { $0 == pair }
        if activePair == pair {
            activePair = nil
            activeSetID = nil
            activeSetExerciseIdentity = nil
        }
    }
}
