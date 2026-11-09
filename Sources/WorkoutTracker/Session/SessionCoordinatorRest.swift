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
                history: wiring.history(),
                restStartDate: restInterval.start,
                restEndDate: restInterval.end
            )
        else { return }

        wiring.liveActivity.startOrUpdate(restContent: content, sessionLabel: session.liveActivityLabel)
    }

    /// The rest Live Activity follows the Set on the card, so an Exercise picked out of order
    /// takes it over, during the rest and after it ends. The rest keeps its dates.
    func retargetLiveActivityAtActiveSet() {
        retargetLiveActivity(pendingWrites: wiring.liveActivity.restContent?.pendingWrites ?? 0)
    }

    /// Leaving the app leaves its header behind, so the card takes the count. Only here: a
    /// retarget in the turn that logged a Set would replace the start that is bringing the card up.
    func retargetLiveActivityOnLeavingTheApp() {
        retargetLiveActivity(pendingWrites: wiring.sync.pendingWriteCount)
    }

    private func retargetLiveActivity(pendingWrites: Int) {
        guard
            let running = wiring.liveActivity.restContent,
            let coordinate = sessionCoordinate,
            let session = currentSession(at: coordinate),
            let activeSet = focusManager.activeSet(in: session)
        else { return }
        var content = LiveActivityRestContentBuilder.content(
            showing: activeSet,
            in: session,
            reading: LoggablePressSource(focus: focusManager, history: wiring.history()),
            restStartDate: running.restStartDate,
            restEndDate: running.restEndDate
        )
        content.pendingWrites = pendingWrites
        guard content != running else { return }
        wiring.liveActivity.retarget(restContent: content)
    }
}
