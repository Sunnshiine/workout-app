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
protocol SessionNavigationAdapter: AnyObject, Observable {
    /// The Viewed Session's live edge, resolved against the Current Session as the store holds them
    /// now. A sync replaces every Session model, so this stays right while a Session the
    /// coordinator was bound to is a stale instance.
    ///
    /// Observable, and changed only on the main actor: the coordinator re-checks the rest Live
    /// Activity whenever a read of it would change, and a change it cannot observe is a reconcile
    /// that never runs.
    var liveEdge: LiveEdge { get }
    var canMoveOn: Bool { get }
    var openExercises: [Exercise] { get }
    var currentSession: Session? { get }
    func liveEdge(for session: Session) -> LiveEdge
    func requestMoveOnCelebration()
    func show(_ address: SessionAddress)
    func showCurrent()
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
    /// Where a request to say the Current Session's active Set waits for the stage to answer it.
    let entry: AppEntryInbox
    /// What a card's first values suggest from, for a Spoken Set on a Set no card has reported.
    let history: () -> LastPerformedLookupSnapshot
}

/// The Session collaborators only the app can build, because each reaches an iOS-only API: the
/// rest Live Activity, SwiftUI's motion, and the rest timer over the rest notifications. The app
/// passes them in so nothing in `Sources/` reaches the notification center, which aborts a process
/// with no app bundle, as `swift test` is (#1006).
@MainActor
struct SessionPlatform {
    let liveActivity: any SessionLiveActivityAdapter
    let motion: any SessionMotionPerforming
    /// The process's one rest, which a locked log may have started before the stage showed, so
    /// the stage's pill, the Live Activity, and the rest-end notification read the same one.
    let restTimer: RestTimer
}

extension SessionWiring {
    /// The app's wiring. Every collaborator not on `platform` is a store the app already holds.
    static func live(  // swiftlint:disable:this function_parameter_count
        workout: WorkoutStore,
        sync: SyncCoordinator,
        settings: SettingsStore,
        lastPerformed: LastPerformedLookupStore,
        entry: AppEntryInbox,
        platform: SessionPlatform
    ) -> SessionWiring {
        SessionWiring(
            logging: workout,
            navigation: workout,
            sync: SessionPendingWriteSyncAdapter(sync: sync, settings: settings),
            restTimer: platform.restTimer,
            restDurations: settings,
            liveActivity: platform.liveActivity,
            motion: platform.motion,
            entry: entry,
            history: { lastPerformed.snapshot }
        )
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
