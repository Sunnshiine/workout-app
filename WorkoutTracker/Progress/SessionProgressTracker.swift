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

    func openExercises(in block: Block, currentSession: Session) -> [Exercise] {
        guard let currentWeekNumber = currentSession.week?.number else { return [] }

        return allSessions(block)
            .filter { session in
                session.week?.number == currentWeekNumber
                    && session.dayNumber < currentSession.dayNumber
            }
            .flatMap { session in
                session.exercises
                    .sorted { $0.order < $1.order }
                    .filter { $0.hasPendingSet }
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
