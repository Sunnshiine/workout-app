import Foundation

enum SessionTileState: Equatable, Sendable, CaseIterable {
    case complete
    case current
    case incomplete

    var accessibilityValue: String {
        switch self {
        case .complete:
            "Complete"
        case .current:
            "Current"
        case .incomplete:
            "Incomplete"
        }
    }
}

struct SessionProgressTracker {
    /// Order index across the block: (week-1)*4 + day.
    func order(of session: Session) -> Int { ((session.week?.number ?? 1) - 1) * 4 + session.dayNumber }

    func session(at order: Int, in block: Block) -> Session? {
        allSessions(block).first { self.order(of: $0) == order }
    }

    func nextSession(after session: Session, in block: Block) -> Session? {
        let nextOrder = order(of: session) + 1
        return self.session(at: nextOrder, in: block)
    }

    private func allSessions(_ block: Block) -> [Session] {
        block.weeks.flatMap { $0.sessions }.sorted { order(of: $0) < order(of: $1) }
    }

    func currentSession(in block: Block, overrideOrder: Int? = nil) -> Session? {
        let sessions = allSessions(block)
        let logged = sessions.filter { s in
            s.exercises.contains { $0.sets.contains { $0.state == .logged } }
        }
        guard let derived = logged.last ?? sessions.first else { return nil }

        if let overrideOrder, let overrideSession = session(at: overrideOrder, in: block) {
            return overrideSession
        }

        return derived
    }

    func currentWeek(in block: Block) -> Week? {
        currentSession(in: block)?.week
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
                    .filter { exercise in
                        exercise.sets.contains { $0.state == .pending }
                    }
            }
    }

    func tileState(for session: Session, currentSession: Session?) -> SessionTileState {
        let sets = session.exercises.flatMap(\.sets)
        if !sets.isEmpty, sets.allSatisfy({ $0.state == .logged || $0.state == .skipped }) {
            return .complete
        }

        if session.persistentModelID == currentSession?.persistentModelID {
            return .current
        }

        return .incomplete
    }
}
