import Foundation

@MainActor
struct RestTriggerPolicy {
    /// Selects the rest kind to run after logging a set, or `nil` when no rest
    /// should run. Superset members rest as `.superset`, everyone else as
    /// `.standard`. When no new rest is triggered but one is already running,
    /// the running rest's kind is kept.
    static func restKind(
        afterLogging loggedSet: ExerciseSet,
        in session: Session,
        isSupersetMember: Bool,
        isRestRunning: Bool
    ) -> RestKind? {
        let sessions = currentWeekSessions(for: session)
        let hasPendingSet = sessions.contains { session in
            session.exercises.contains { exercise in
                exercise.sets.contains { set in
                    set !== loggedSet && set.state == .pending
                }
            }
        }
        guard hasPendingSet || isRestRunning else { return nil }
        return isSupersetMember ? .superset : .standard
    }

    private static func currentWeekSessions(for session: Session) -> [Session] {
        guard let week = session.week, !week.sessions.isEmpty else {
            return [session]
        }
        return week.sessions
    }
}
