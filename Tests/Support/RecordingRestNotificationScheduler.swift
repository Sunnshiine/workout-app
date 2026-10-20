import Foundation

@testable import WorkoutTracker

/// Records every call instead of reaching the notification center, which aborts a process with no
/// app bundle, as `swift test` is (#1006). Shared so the rest-timer and wiring suites use one
/// double instead of copies.
@MainActor
final class RecordingRestNotificationScheduler: RestNotificationScheduling {
    private(set) var requestedAuthorizationCount = 0
    private(set) var scheduledDeadlines: [Date] = []
    private(set) var cancelCount = 0

    func requestAuthorizationIfNeeded() {
        requestedAuthorizationCount += 1
    }

    func schedule(deadline: Date) {
        scheduledDeadlines.append(deadline)
    }

    func cancel() {
        cancelCount += 1
    }
}
