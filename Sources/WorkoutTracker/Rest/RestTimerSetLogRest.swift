import Foundation

extension RestTimer {
    /// Starts the rest the stage runs after logging this Set, keyed to the Set so
    /// `cancelRest(startedBy:)` finds it. Returns whether a rest started.
    @discardableResult
    func startRest(
        afterLogging set: ExerciseSet,
        in session: Session,
        wasSupersetMember: Bool,
        durations: any SessionRestDurations
    ) -> Bool {
        guard
            let kind = RestTriggerPolicy.restKind(
                afterLogging: set,
                in: session,
                isSupersetMember: wasSupersetMember,
                isRestRunning: isRunning
            )
        else { return false }
        start(
            duration: durations.restDuration(for: kind),
            origin: ActiveSetFocusManager.id(for: set),
            originSetObjectID: ObjectIdentifier(set),
            kind: kind
        )
        return true
    }

    /// Cancels the rest only when this Set's log started it.
    func cancelRest(startedBy set: ExerciseSet) {
        cancel(ifOriginMatches: ActiveSetFocusManager.id(for: set), originSetObjectID: ObjectIdentifier(set))
    }
}
