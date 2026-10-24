import Foundation

extension RestTimer {
    /// Starts the rest the stage runs after logging this Set, keyed to the Set so
    /// `cancelRest(startedBy:)` finds it. Returns the rest it started, if any.
    func startRest(
        afterLogging set: ExerciseSet,
        in session: Session,
        wasSupersetMember: Bool,
        durations: any SessionRestDurations
    ) -> RestInterval? {
        guard
            let kind = RestTriggerPolicy.restKind(
                afterLogging: set,
                in: session,
                isSupersetMember: wasSupersetMember,
                isRestRunning: isRunning
            )
        else { return nil }
        start(
            duration: durations.restDuration(for: kind),
            origin: ActiveSetFocusManager.id(for: set),
            originSetObjectID: ObjectIdentifier(set),
            kind: kind
        )
        return interval
    }

    /// Cancels the rest only when this Set's log started it.
    func cancelRest(startedBy set: ExerciseSet) {
        cancel(ifOriginMatches: ActiveSetFocusManager.id(for: set), originSetObjectID: ObjectIdentifier(set))
    }
}
