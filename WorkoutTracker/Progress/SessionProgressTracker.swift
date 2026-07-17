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

    func openExercises(in block: Block, currentSession: Session) -> [Exercise] {
        openExercises(inCurrentWeekOf: currentSession)
    }

    /// The Open Exercise rule scoped to the Current Week: Exercises holding a
    /// Pending Set in Current-Week days *earlier* than `currentSession`, in
    /// day order then Exercise order. This is the one home for "earlier
    /// Current-Week days still owe makeup work" — the Block-scoped
    /// `openExercises(in:currentSession:)` and the Live Activity rest widget's
    /// makeup fallback both read it, rather than each re-walking the Week.
    func openExercises(inCurrentWeekOf currentSession: Session) -> [Exercise] {
        guard let week = currentSession.week else { return [] }

        return week.sessions
            .filter { $0.dayNumber < currentSession.dayNumber }
            .sorted { $0.dayNumber < $1.dayNumber }
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
