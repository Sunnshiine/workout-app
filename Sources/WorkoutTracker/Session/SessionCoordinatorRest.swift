import Foundation

extension SessionCoordinator {
    func isSupersetMember(_ set: ExerciseSet) -> Bool {
        guard let exercise = set.exercise else { return false }
        return focusManager.isPaired(exercise)
    }

    func startRest(afterLogging set: ExerciseSet, in session: Session, wasSupersetMember: Bool) {
        guard
            wiring.restTimer.startRest(
                afterLogging: set,
                in: session,
                wasSupersetMember: wasSupersetMember,
                durations: wiring.restDurations
            ) != nil
        else { return }
        startOrUpdateLiveActivity(afterLogging: set, in: session)
    }

    func startOrUpdateLiveActivity(afterLogging set: ExerciseSet, in session: Session) {
        let event = LiveActivityProductionEvent(
            source: .userSetLog,
            outcome: .success,
            sessionScope: wiring.navigation.liveEdge(for: session).isAtLiveEdge ? .currentSession : .nonCurrentSession
        )
        guard
            LiveActivityCreationPolicy.shouldCreateOrUpdate(for: event),
            let restInterval = wiring.restTimer.interval
        else { return }

        guard
            let content = focusManager.liveActivityRestContent(
                afterLogging: set,
                in: session,
                restStartDate: restInterval.start,
                restEndDate: restInterval.end
            )
        else { return }

        wiring.liveActivity.startOrUpdate(restContent: content, sessionLabel: session.liveActivityLabel)
    }
}
