import Foundation

@testable import WorkoutTracker

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
