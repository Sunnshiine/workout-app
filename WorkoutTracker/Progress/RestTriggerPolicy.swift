import Foundation

enum RestTriggerDecision: Equatable, Sendable {
    case none
    case start
}

@MainActor
struct RestTriggerPolicy {
    static func decision(afterLogging loggedSet: ExerciseSet, in session: Session) -> RestTriggerDecision {
        let sessions = currentWeekSessions(for: session)
        let hasPendingSet = sessions.contains { session in
            session.exercises.contains { exercise in
                exercise.sets.contains { set in
                    set !== loggedSet && set.state == .pending
                }
            }
        }
        return hasPendingSet ? .start : .none
    }

    private static func currentWeekSessions(for session: Session) -> [Session] {
        guard let week = session.week, !week.sessions.isEmpty else {
            return [session]
        }
        return week.sessions
    }
}
