import Foundation

enum SessionTileState: Equatable, Sendable {
    case complete
    case hasOpenExercises
    case current
    case upcoming
}

struct SessionProgressTracker {
    /// Order index across the block: (week-1)*4 + day.
    private func order(_ s: Session) -> Int { ((s.week?.number ?? 1) - 1) * 4 + s.dayNumber }

    private func allSessions(_ block: Block) -> [Session] {
        block.weeks.flatMap { $0.sessions }.sorted { order($0) < order($1) }
    }

    func currentSession(in block: Block) -> Session? {
        let sessions = allSessions(block)
        let logged = sessions.filter { s in
            s.exercises.contains { $0.sets.contains { $0.state == .logged } }
        }
        return logged.last ?? sessions.first
    }

    func currentWeek(in block: Block) -> Week? {
        currentSession(in: block)?.week
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
