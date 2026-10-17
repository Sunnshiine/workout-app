import Foundation

@MainActor
protocol SessionLoggingAdapter {
    func log(_ set: ExerciseSet, as log: SetLog) throws
    func skip(_ set: ExerciseSet) throws
    func deleteLog(for set: ExerciseSet) throws
}

@MainActor
protocol SessionSyncAdapter {
    func reportLocalWriteFailure(_ error: any Error)
    func requestPendingWriteFlush()
}

@MainActor
protocol SessionLiveActivityAdapter {
    func startOrUpdate(restContent: LiveActivityRestContent, sessionLabel: String)
    func end()
    func endIfInvalidated(at liveEdge: LiveEdge)
}

@MainActor
protocol SessionNavigationAdapter: AnyObject {
    /// The Viewed Session's live edge, resolved against the Current Session as the store holds them
    /// now. A sync replaces every Session model, so this stays right while a Session the
    /// coordinator was bound to is a stale instance.
    var liveEdge: LiveEdge { get }
    var canMoveOn: Bool { get }
    var openExercises: [Exercise] { get }
    func liveEdge(for session: Session) -> LiveEdge
    func requestMoveOnCelebration()
    func show(_ address: SessionAddress)
}

/// Read at each rest's start, so a rest length changed mid-Session takes effect on the next Set.
@MainActor
protocol SessionRestDurations {
    func restDuration(for kind: RestKind) -> TimeInterval
}

/// What a Session's engine is made of. `SessionCoordinator` takes one at construction, so a
/// coordinator missing a collaborator does not compile.
@MainActor
struct SessionWiring {
    let logging: any SessionLoggingAdapter
    let navigation: any SessionNavigationAdapter
    let sync: any SessionSyncAdapter
    let restTimer: RestTimer
    let restDurations: any SessionRestDurations
    let liveActivity: any SessionLiveActivityAdapter
    let motion: any SessionMotionPerforming
}

extension SessionWiring {
    /// The app's wiring. The Live Activity and the motion are the platform's; every other
    /// collaborator is a store the app already holds, or the rest timer chosen here.
    static func live(
        workout: WorkoutStore,
        sync: SyncCoordinator,
        settings: SettingsStore,
        liveActivity: any SessionLiveActivityAdapter,
        motion: any SessionMotionPerforming
    ) -> SessionWiring {
        SessionWiring(
            logging: workout,
            navigation: workout,
            sync: SessionPendingWriteSyncAdapter(sync: sync, settings: settings),
            restTimer: liveRestTimer(),
            restDurations: settings,
            liveActivity: liveActivity,
            motion: motion
        )
    }

    private static func liveRestTimer() -> RestTimer {
        #if canImport(UserNotifications)
            RestTimer(notificationScheduler: RestNotificationCenterScheduler.shared)
        #else
            RestTimer()
        #endif
    }
}

extension WorkoutStore: SessionLoggingAdapter {}

extension WorkoutStore: SessionNavigationAdapter {}

extension SettingsStore: SessionRestDurations {
    func restDuration(for kind: RestKind) -> TimeInterval {
        switch kind {
        case .standard: standardRestDuration.timeInterval
        case .superset: supersetRestDuration.timeInterval
        }
    }
}

struct SessionPendingWriteSyncAdapter: SessionSyncAdapter {
    let sync: SyncCoordinator
    let settings: SettingsStore

    func reportLocalWriteFailure(_ error: any Error) {
        sync.reportLocalWriteFailure(error)
    }

    func requestPendingWriteFlush() {
        guard let id = settings.spreadsheetId else { return }
        // Awaiting it would keep flushes apart, which changes when Set Logs are flushed (#702).
        // swiftlint:disable:next unstructured_task_is_held
        Task { await sync.flushPending(spreadsheetId: id) }
    }
}
