import Foundation
import Testing

@testable import WorkoutTracker

/// Records each Session verb, motion, and Live Activity call in the order the coordinator makes them.
enum SessionVerbEntry: Equatable {
    case began(SessionMotion, focus: ActiveSetID?)
    case logged
    case skipped
    case deleted
    case liveActivityStarted
    case liveActivityReconciled
    case ended(focus: ActiveSetID?)
    case flushRequested
    case failureReported
}

@MainActor
final class SessionVerbLedger: SessionMotionPerforming, SessionLoggingAdapter, SessionSyncAdapter, SessionLiveActivityAdapter {
    var reducesMotion = false
    var writeError: TestLoggingError?
    weak var coordinator: SessionCoordinator?
    private(set) var entries: [SessionVerbEntry] = []

    var motions: [SessionMotion] {
        entries.compactMap { entry in
            guard case .began(let motion, _) = entry else { return nil }
            return motion
        }
    }

    func animate(_ motion: SessionMotion, _ change: () throws -> Void) rethrows {
        entries.append(.began(motion, focus: coordinator?.activeSetID))
        defer { entries.append(.ended(focus: coordinator?.activeSetID)) }
        try change()
    }

    func log(_ set: ExerciseSet, as log: SetLog) throws {
        if let writeError { throw writeError }
        entries.append(.logged)
        set.setLog = log
        set.state = .logged
    }

    func skip(_ set: ExerciseSet) throws {
        entries.append(.skipped)
        set.setLog = nil
        set.state = .skipped
    }

    func deleteLog(for set: ExerciseSet) throws {
        entries.append(.deleted)
        set.setLog = nil
        set.state = .pending
    }

    func reportLocalWriteFailure(_ error: any Error) {
        entries.append(.failureReported)
    }

    func requestPendingWriteFlush() {
        entries.append(.flushRequested)
    }

    func startOrUpdate(restContent: LiveActivityRestContent, sessionLabel: String) {
        entries.append(.liveActivityStarted)
    }

    func end() {}

    func endIfInvalidated(at liveEdge: LiveEdge) {
        entries.append(.liveActivityReconciled)
    }
}
