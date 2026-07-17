import Foundation

enum SessionTileState: Equatable, Sendable, CaseIterable {
    case complete
    case current
    case incomplete
    case unavailable

    var accessibilityValue: String {
        switch self {
        case .complete:
            "Complete"
        case .current:
            "Current"
        case .incomplete:
            "Incomplete"
        case .unavailable:
            "Not uploaded"
        }
    }
}

/// The single outcome of a Move On, encoding the full `CONTEXT.md` Move On table
/// as one value so callers ask for the decision instead of re-deriving it from the
/// `hasSessionAhead` (Available *and* Unavailable) / `nextSession` (Available only)
/// asymmetry.
enum MoveOnDestination: Equatable {
    /// Advance to the next Available Session, skipping any Unavailable Sessions in between.
    case advance(to: Session)
    /// No Available Session remains ahead, but the Block still holds Unavailable
    /// Sessions ahead — Move On returns the athlete to the Block grid.
    case returnToBlockOverview
    /// Nothing lies ahead — Move On is not offered.
    case none
}

struct SessionProgressTracker {
    /// Stride between Weeks when encoding a Session's block-wide order. A Week is a 7-day
    /// window, so a stride of 7 keeps order strictly increasing across Weeks for any 2–6 day
    /// program; a stride of 4 collided once a Week held more than 4 days (e.g. Day 5/6).
    private static let weekOrderStride = 7

    /// Order index across the block: (week-1)*stride + day.
    func order(of session: Session) -> Int {
        ((session.week?.number ?? 1) - 1) * Self.weekOrderStride + session.dayNumber
    }

    func session(at order: Int, in block: Block) -> Session? {
        allSessions(block).first { self.order(of: $0) == order }
    }

    func nextSession(after session: Session, in block: Block) -> Session? {
        let currentOrder = order(of: session)
        return allSessions(block).first {
            order(of: $0) > currentOrder && isAvailable($0)
        }
    }

    func hasSessionAhead(after session: Session, in block: Block) -> Bool {
        let currentOrder = order(of: session)
        return allSessions(block).contains { order(of: $0) > currentOrder }
    }

    /// Where a Move On from `session` lands, per the `CONTEXT.md` Move On rule:
    /// advance to the next Available Session (skipping Unavailable ones), or — when
    /// no Available Session remains ahead but the Block still holds Unavailable
    /// Sessions ahead — return to the Block grid; otherwise nothing lies ahead.
    func moveOnDestination(from session: Session, in block: Block) -> MoveOnDestination {
        guard hasSessionAhead(after: session, in: block) else { return .none }
        if let nextSession = nextSession(after: session, in: block) {
            return .advance(to: nextSession)
        }
        return .returnToBlockOverview
    }

    private func allSessions(_ block: Block) -> [Session] {
        block.weeks.flatMap { $0.sessions }.sorted { order(of: $0) < order(of: $1) }
    }

    func currentSession(in block: Block, overrideOrder: Int? = nil) -> Session? {
        let sessions = allSessions(block)
        let logged = sessions.filter { s in
            s.exercises.contains { $0.sets.contains { $0.state == .logged } }
        }
        guard let derived = logged.last ?? sessions.first(where: isAvailable) else { return nil }

        if let overrideOrder, let overrideSession = session(at: overrideOrder, in: block), isAvailable(overrideSession) {
            return overrideSession
        }

        return derived
    }

    func currentWeek(in block: Block) -> Week? {
        currentSession(in: block)?.week
    }

    /// The Sessions that make up the same Week as `session` — the single home for
    /// "which Sessions belong to the Current Week".
    ///
    /// Membership follows the `Week.sessions` relation, not `Week.number`: two
    /// Weeks can share a number (e.g. across re-parsed Blocks), so the relation is
    /// the authoritative grouping. When the relation is absent or empty — a
    /// detached Session not yet wired into its Week — this falls back to the lone
    /// passed-in Session so callers always have at least it to scan.
    func sessionsInCurrentWeek(for session: Session) -> [Session] {
        guard let week = session.week, !week.sessions.isEmpty else {
            return [session]
        }
        return week.sessions
    }

    /// One Open Exercise: an Exercise carrying at least one Pending Set in an
    /// earlier Day of the Current Week, paired with the Session it belongs to so
    /// callers that need the Session (the Live Activity rest target) don't have
    /// to reach back through a relation.
    struct OpenExercise {
        let session: Session
        let exercise: Exercise
    }

    /// The Open Exercises for `currentSession`: every Exercise with a Pending Set
    /// in an *earlier* Day of the same Current Week, ordered by Day and then by
    /// Exercise order. This is the single home for the Open-Exercise rule — the
    /// makeup queue and the Live Activity rest fallback both read from here, so
    /// they cannot disagree about which earlier-Day Exercises qualify. Current-Week
    /// membership is resolved through `sessionsInCurrentWeek(for:)`.
    func openExercises(for currentSession: Session) -> [OpenExercise] {
        sessionsInCurrentWeek(for: currentSession)
            .filter { $0.dayNumber < currentSession.dayNumber }
            .sorted { $0.dayNumber < $1.dayNumber }
            .flatMap { session in
                session.exercises
                    .sorted { $0.order < $1.order }
                    .filter(\.hasPendingSet)
                    .map { OpenExercise(session: session, exercise: $0) }
            }
    }

    func tileState(for session: Session, currentSession: Session?) -> SessionTileState {
        if !isAvailable(session) {
            return .unavailable
        }

        if session.isComplete {
            return .complete
        }

        if session.persistentModelID == currentSession?.persistentModelID {
            return .current
        }

        return .incomplete
    }

    func isAvailable(_ session: Session) -> Bool { !session.exercises.isEmpty }
}
