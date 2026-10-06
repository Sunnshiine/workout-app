import Foundation
import Observation

enum ActiveSetVisualFocusOwner: Equatable, Sendable {
    case activeSet(ActiveSetID)
    case loggedSetReview(ActiveSetID)

    var setID: ActiveSetID {
        switch self {
        case .activeSet(let setID), .loggedSetReview(let setID):
            setID
        }
    }
}

@MainActor
@Observable
final class ActiveSetFocusManager {
    private(set) var activeSetID: ActiveSetID?
    private(set) var expandedLoggedSetID: ActiveSetID?
    private let supersetState = SupersetState()

    init(session: Session?) {
        activeSetID = session.flatMap { SessionSetOrder.firstPendingSet(in: $0)?.setID }
    }

    var visualFocusOwner: ActiveSetVisualFocusOwner? {
        if let expandedLoggedSetID {
            return .loggedSetReview(expandedLoggedSetID)
        }
        return activeSetID.map(ActiveSetVisualFocusOwner.activeSet)
    }

    func reset(to session: Session?) {
        let nextSetID = session.flatMap { SessionSetOrder.firstPendingSet(in: $0)?.setID }
        if let session {
            supersetState.refresh(in: session)
            activeSetID = supersetState.focusedSetID(whenNormalFocusIs: nextSetID, in: session)
        } else {
            activeSetID = nil
        }
        expandedLoggedSetID = nil
    }

    func advanceAfterLog(_ set: ExerciseSet, in session: Session) {
        expandedLoggedSetID = nil
        activeSetID = nextActiveSetID(after: set, in: session)
    }

    func advanceAfterSkip(_ set: ExerciseSet, in session: Session) {
        expandedLoggedSetID = nil
        activeSetID = nextActiveSetID(after: set, in: session)
    }

    func focus(on set: ExerciseSet) {
        guard let setID = Self.id(for: set) else { return }
        if set.state == .logged {
            expandedLoggedSetID = expandedLoggedSetID == setID ? nil : setID
            return
        }

        expandedLoggedSetID = nil
        activeSetID = setID
    }

    func motion(forFocusing set: ExerciseSet) -> SessionMotion? {
        switch set.state {
        case .pending:
            .focusMorph
        case .skipped:
            nil
        case .logged:
            Self.id(for: set) == expandedLoggedSetID ? nil : .focusMorph
        }
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
        supersetState.createSuperset(with: exercises, in: session, currentActiveSetID: activeSetID)
    }

    @discardableResult
    func createSuperset(from source: Exercise, to target: Exercise, in session: Session) -> Bool {
        createSuperset(with: [source, target], in: session)
    }

    func dismissSuperset(containing exercise: Exercise, in session: Session) {
        supersetState.dismissSuperset(containing: exercise)
        activeSetID = supersetState.focusedSetID(whenNormalFocusIs: activeSetID, in: session)
    }

    /// Focus and the live Supersets as one value for `SessionStage`. It reads and never writes.
    func snapshot(in session: Session) -> SessionFocusSnapshot {
        SessionFocusSnapshot(
            activeSetID: activeSetID,
            expandedLoggedSetID: expandedLoggedSetID,
            supersets: supersetState.exercisePairs(in: session),
            pairableExerciseOrders: Set(session.exercises.filter { canPair($0, in: session) }.map(\.order))
        )
    }

    func liveActivityRestContent(
        afterLogging set: ExerciseSet,
        in session: Session,
        restStartDate: Date,
        restEndDate: Date
    ) -> LiveActivityRestContent? {
        LiveActivityRestContentBuilder.content(
            afterLogging: set,
            in: session,
            supersetState: supersetState,
            restStartDate: restStartDate,
            restEndDate: restEndDate
        )
    }

    /// Whether the Exercise belongs to a Superset — a thin pass-through to the Superset
    /// owner's domain membership predicate.
    func isPaired(_ exercise: Exercise) -> Bool {
        supersetState.isPaired(exercise)
    }

    @discardableResult
    func focusNextSupersetSet(for exercise: Exercise, in session: Session) -> Bool {
        guard let nextSetID = supersetState.focusNextPendingSet(for: exercise, in: session) else {
            return false
        }
        activeSetID = nextSetID
        return true
    }

    static func id(for set: ExerciseSet) -> ActiveSetID? {
        set.exercise.map { SessionSetPosition(exercise: $0, set: set).setID }
    }

    private func nextActiveSetID(after set: ExerciseSet, in session: Session) -> ActiveSetID? {
        if let supersetNextSetID = supersetState.focusNextSetID(after: set, in: session) {
            return supersetNextSetID
        }
        let normalNextSetID = SessionSetOrder.nextPendingSet(after: set, in: session)?.setID
        return supersetState.focusedSetID(whenNormalFocusIs: normalNextSetID, in: session)
    }
}
