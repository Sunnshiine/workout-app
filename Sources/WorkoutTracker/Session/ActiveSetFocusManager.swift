import Foundation
import Observation

enum ActiveSetVisualFocusOwner: Equatable, Sendable {
    case activeSet(ActiveSetID)
    case loggedSetReview(ActiveSetID)
    /// A Set just written by speech, which the card keeps until the hold ends. The Active Set has
    /// already moved on.
    case heldAfterSpokenWrite(ActiveSetID)

    var setID: ActiveSetID {
        switch self {
        case .activeSet(let setID), .loggedSetReview(let setID), .heldAfterSpokenWrite(let setID):
            setID
        }
    }
}

@MainActor
@Observable
final class ActiveSetFocusManager {
    /// A Set the card shows in place of the Active Set.
    private enum ShownInstead: Equatable {
        case review(ActiveSetID)
        case heldAfterSpokenWrite(ActiveSetID)

        var setID: ActiveSetID {
            switch self {
            case .review(let setID), .heldAfterSpokenWrite(let setID): setID
            }
        }
    }

    private(set) var activeSetID: ActiveSetID?
    private var shownInstead: ShownInstead?
    private let supersetState = SupersetState()
    /// The Session the focus is about: the one the stage last bound. An `ActiveSetID` names a Set
    /// only within it.
    @ObservationIgnored private(set) var session: Session?

    init(session: Session?) {
        self.session = session
        activeSetID = session.flatMap { SessionSetOrder.firstPendingSet(in: $0)?.setID }
    }

    /// The Set the card for `session` listens on: the stage's own focus while it is about
    /// `session`, Superset alternation and the athlete's focus included. A stage about another
    /// Session, or none yet, holds no Superset of this one, so binding `session` would focus its
    /// first Pending Set.
    func activeSet(in session: Session) -> SessionSetPosition? {
        guard self.session === session else { return SessionSetOrder.firstPendingSet(in: session) }
        return SessionSetOrder.orderedSets(in: session).first { $0.setID == activeSetID && $0.set.isPending }
    }

    var expandedLoggedSetID: ActiveSetID? {
        guard case .review(let setID) = shownInstead else { return nil }
        return setID
    }

    var visualFocusOwner: ActiveSetVisualFocusOwner? {
        switch shownInstead {
        case .review(let setID): .loggedSetReview(setID)
        case .heldAfterSpokenWrite(let setID): .heldAfterSpokenWrite(setID)
        case nil: activeSetID.map(ActiveSetVisualFocusOwner.activeSet)
        }
    }

    func reset(to session: Session?) {
        self.session = session
        let nextSetID = session.flatMap { SessionSetOrder.firstPendingSet(in: $0)?.setID }
        if let session {
            supersetState.refresh(in: session)
            activeSetID = supersetState.focusedSetID(whenNormalFocusIs: nextSetID, in: session)
        } else {
            activeSetID = nil
        }
        shownInstead = nil
    }

    func advanceAfterLog(_ set: ExerciseSet, in session: Session) {
        shownInstead = nil
        activeSetID = nextActiveSetID(after: set, in: session)
    }

    func advanceAfterSkip(_ set: ExerciseSet, in session: Session) {
        shownInstead = nil
        activeSetID = nextActiveSetID(after: set, in: session)
    }

    /// A spoken write lands after the press let go, when the athlete may have moved on. The Active
    /// Set moves past `set` only while it is still `set`, and the card keeps `set` only while it
    /// still showed it. Whatever else the card shows stays. True when the card keeps `set`.
    @discardableResult
    func advanceAfterSpokenWrite(_ set: ExerciseSet, in session: Session, holding: Bool) -> Bool {
        guard self.session === session, let setID = Self.id(for: set), activeSetID == setID else { return false }
        activeSetID = nextActiveSetID(after: set, in: session)
        guard holding, shownInstead == nil else { return false }
        shownInstead = .heldAfterSpokenWrite(setID)
        return true
    }

    var isHoldingSpokenWrite: Bool {
        guard case .heldAfterSpokenWrite = shownInstead else { return false }
        return true
    }

    func endHoldAfterSpokenWrite() {
        guard isHoldingSpokenWrite else { return }
        shownInstead = nil
    }

    /// A logged Set's leaf toggles its review, and closes whatever the card shows of it instead.
    func focus(on set: ExerciseSet) {
        guard let setID = Self.id(for: set) else { return }
        if set.state == .logged {
            shownInstead = shownInstead?.setID == setID ? nil : .review(setID)
            return
        }

        shownInstead = nil
        activeSetID = setID
    }

    func motion(forFocusing set: ExerciseSet) -> SessionMotion? {
        switch set.state {
        case .pending:
            .focusMorph
        case .skipped:
            nil
        case .logged:
            Self.id(for: set) == shownInstead?.setID ? nil : .focusMorph
        }
    }

    func collapseLoggedSetReview() {
        guard expandedLoggedSetID != nil else { return }
        shownInstead = nil
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

    func snapshot(in session: Session) -> SessionFocusSnapshot {
        SessionFocusSnapshot(
            visualFocusOwner: visualFocusOwner,
            supersets: supersetState.supersets(in: session),
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
