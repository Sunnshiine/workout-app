import Foundation

@testable import WorkoutTracker

/// Records the rest-end notifications a `RestTimer` asks for, in place of the notification center.
@MainActor
final class MockRestNotificationScheduler: RestNotificationScheduling {
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

@MainActor
final class MockRestExpiryScheduler: RestExpiryScheduling {
    private(set) var scheduledDeadlines: [Date] = []
    private(set) var cancelCount = 0
    private var expire: (@MainActor () -> Void)?

    func schedule(deadline: Date, expire: @escaping @MainActor () -> Void) {
        scheduledDeadlines.append(deadline)
        self.expire = expire
    }

    func cancel() {
        cancelCount += 1
        expire = nil
    }

    /// Simulate the deadline arriving — the single moment the module decides rest is over.
    func fire() {
        expire?()
    }
}
