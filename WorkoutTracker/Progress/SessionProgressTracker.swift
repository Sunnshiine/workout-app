import Foundation

enum SessionTileState: Equatable, Sendable {
    case complete
    case hasOpenExercises
    case current
    case upcoming
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

    func currentSession(in block: Block, advancedToOrder: Int? = nil) -> Session? {
        let sessions = allSessions(block)
        let logged = sessions.filter { s in
            s.exercises.contains { $0.sets.contains { $0.state == .logged } }
        }
        guard let derived = logged.last ?? sessions.first else { return nil }
        guard
            let advancedToOrder,
            advancedToOrder > order(of: derived),
            let advancedSession = session(at: advancedToOrder, in: block)
        else {
            return derived
        }
        return advancedSession
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
        if session.persistentModelID == currentSession?.persistentModelID {
            return .current
        }

        let sets = session.exercises.flatMap(\.sets)
        guard !sets.isEmpty else { return .upcoming }

        let completedCount = sets.filter { $0.state == .logged || $0.state == .skipped }.count
        if completedCount == sets.count {
            return .complete
        }
        if completedCount > 0 {
            return .hasOpenExercises
        }
        return .upcoming
    }
}
