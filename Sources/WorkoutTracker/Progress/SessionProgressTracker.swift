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
    case notOffered

    /// Whether Move On is offered from here — true unless nothing lies ahead. Lets a
    /// caller gating a control ask the decision directly instead of comparing against a
    /// case (and avoids the `Optional.none` footgun a `.none` case would invite).
    var isOffered: Bool { self != .notOffered }
}

struct SessionProgressTracker {
    private static let weekOrderStride = Week.dayNumbers.count

    /// The first Available Session after `session` in Block order, or nil when none lies ahead or
    /// `block` does not hold `session`.
    func nextSession(after session: Session, in block: Block) -> Session? {
        sessions(after: session, in: block).first(where: isAvailable)
    }

    func hasSessionAhead(after session: Session, in block: Block) -> Bool {
        !sessions(after: session, in: block).isEmpty
    }

    /// Where a Move On from `session` lands, per the `CONTEXT.md` Move On rule:
    /// advance to the next Available Session (skipping Unavailable ones), or — when
    /// no Available Session remains ahead but the Block still holds Unavailable
    /// Sessions ahead — return to the Block grid; otherwise nothing lies ahead.
    func moveOnDestination(from session: Session, in block: Block) -> MoveOnDestination {
        guard hasSessionAhead(after: session, in: block) else { return .notOffered }
        if let nextSession = nextSession(after: session, in: block) {
            return .advance(to: nextSession)
        }
        return .returnToBlockOverview
    }

    /// Empty when `block` does not hold `session`, as for a Session held across the sync that
    /// replaced its Block: navigation refuses such a Session rather than guessing where it sat.
    private func sessions(after session: Session, in block: Block) -> ArraySlice<Session> {
        let sessions = allSessions(block)
        guard let index = sessions.firstIndex(where: { $0.persistentModelID == session.persistentModelID }) else { return [] }
        return sessions[(index + 1)...]
    }

    private func allSessions(_ block: Block) -> [Session] {
        block.weeks
            .flatMap { week in
                week.sessions.map { (order: (week.number - 1) * Self.weekOrderStride + $0.dayNumber, session: $0) }
            }
            .sorted { $0.order < $1.order }
            .map(\.session)
    }

    /// The Sheet-derived Current Session: the last logged Session, else the first Available one.
    /// `CurrentSessionPin.resolve(in:)` decides whether a Current Session Pin wins over it.
    func currentSession(in block: Block) -> Session? {
        let sessions = allSessions(block)
        let logged = sessions.filter { s in
            s.exercises.contains { $0.sets.contains { $0.state == .logged } }
        }
        return logged.last ?? sessions.first(where: isAvailable)
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
