import Foundation
import Observation

@testable import WorkoutTracker

/// A `SessionWiring` for suites that build a `SessionCoordinator` around one collaborator under
/// test. Every collaborator not named keeps its writes and Lock Screen effects to itself: a Set
/// Log fails as unwired, the flush and the Live Activity go nowhere, the Session reads as browsed
/// away, and a rest or an Effort Countdown starts on a clock that never moves and never expires on
/// its own, the countdown saying nothing.
extension SessionWiring {
    @MainActor
    static func fixture(
        logging: any SessionLoggingAdapter = UnwiredSessionLogging(),
        navigation: any SessionNavigationAdapter = BrowsedAwaySessionNavigation(),
        sync: any SessionSyncAdapter = InertSessionSync(),
        restTimer: RestTimer = RestTimer(
            clock: ManualRestClock(now: Date(timeIntervalSinceReferenceDate: 0)),
            expiryScheduler: HeldRestExpiry()
        ),
        countdown: EffortCountdown = EffortCountdown(
            clock: ManualRestClock(now: Date(timeIntervalSinceReferenceDate: 0)),
            scheduler: HeldRestExpiry(),
            cues: SilentCountdownCues()
        ),
        restDurations: any SessionRestDurations = SettingsStore(defaults: .inMemory()),
        liveActivity: any SessionLiveActivityAdapter = InertSessionLiveActivity(),
        motion: any SessionMotionPerforming = ImmediateSessionMotion(),
        entry: AppEntryInbox = AppEntryInbox(),
        history: @escaping () -> LastPerformedLookupSnapshot = { .empty },
        formClips: FormClipLibrary = FormClipLibrary(
            directory: URL.temporaryDirectory.appending(path: UUID().uuidString),
            tracker: UnwiredBarPathTracker(),
            now: { Date(timeIntervalSinceReferenceDate: 0) }
        ),
        spreadsheetId: @escaping () -> String? = { nil }
    ) -> SessionWiring {
        SessionWiring(
            logging: logging,
            navigation: navigation,
            sync: sync,
            restTimer: restTimer,
            countdown: countdown,
            restDurations: restDurations,
            liveActivity: liveActivity,
            motion: motion,
            entry: entry,
            history: history,
            formClips: formClips,
            spreadsheetId: spreadsheetId
        )
    }
}

/// A tracker for suites that never trace, which fails the test that reaches it.
struct UnwiredBarPathTracker: BarPathTracker {
    func trace(_ movie: URL, from start: BarPathStart, progress: @escaping @Sendable (Double) -> Void) async throws -> BarPath {
        throw UnwiredSessionLoggingError.unwired
    }
}

enum UnwiredSessionLoggingError: Error {
    case unwired
}

@MainActor
struct UnwiredSessionLogging: SessionLoggingAdapter {
    func log(_ set: ExerciseSet, as log: SetLog) throws {
        throw UnwiredSessionLoggingError.unwired
    }

    func skip(_ set: ExerciseSet) throws {
        throw UnwiredSessionLoggingError.unwired
    }

    func deleteLog(for set: ExerciseSet) throws {
        throw UnwiredSessionLoggingError.unwired
    }
}

@MainActor
@Observable
final class BrowsedAwaySessionNavigation: SessionNavigationAdapter {
    var liveEdge: LiveEdge { .browsedAway }
    var canMoveOn: Bool { false }
    var openExercises: [Exercise] { [] }
    var currentSession: Session? { nil }
    var viewedSession: Session? { nil }
    func liveEdge(for session: Session) -> LiveEdge { .browsedAway }
    func requestMoveOnCelebration() {}
    func show(_ address: SessionAddress) {}
    func showCurrent() {}
}

@MainActor
struct InertSessionSync: SessionSyncAdapter {
    func reportLocalWriteFailure(_ error: any Error) {}
    func requestPendingWriteFlush() {}
}

@MainActor
struct InertSessionLiveActivity: SessionLiveActivityAdapter {
    var restContent: LiveActivityRestContent? { nil }
    func startOrUpdate(restContent: LiveActivityRestContent, sessionLabel: String) {}
    func retarget(restContent: LiveActivityRestContent) {}
    func end() {}
    func endIfInvalidated(at liveEdge: LiveEdge) {}
}

/// Leaves a rest running until a test cancels or dismisses it.
@MainActor
final class HeldRestExpiry: RestExpiryScheduling {
    func schedule(deadline: Date, expire: @escaping @MainActor () -> Void) {}
    func cancel() {}
}

/// Says and plays nothing.
@MainActor
final class SilentCountdownCues: CountdownCuePlaying {
    func play(_ cue: CountdownCue) {}
    func silence() {}
}
