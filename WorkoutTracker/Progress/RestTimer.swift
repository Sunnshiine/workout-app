import Foundation
import Observation

@MainActor
protocol RestClock: AnyObject {
    var now: Date { get }
}

@MainActor
final class SystemRestClock: RestClock {
    var now: Date {
        Date()
    }
}

@MainActor
@Observable
final class RestTimer {
    private(set) var deadline: Date?
    private(set) var origin: ActiveSetID?
    private(set) var duration: TimeInterval = 0
    private(set) var restartRevision = 0

    @ObservationIgnored private let clock: any RestClock

    init(clock: any RestClock = SystemRestClock()) {
        self.clock = clock
    }

    var remaining: TimeInterval {
        remaining(at: clock.now)
    }

    var isRunning: Bool {
        remaining > 0
    }

    func start(duration: TimeInterval, origin: ActiveSetID?) {
        self.duration = duration
        self.origin = origin
        deadline = clock.now.addingTimeInterval(duration)
        restartRevision += 1
    }

    func cancel(ifOriginMatches origin: ActiveSetID?) {
        guard self.origin == origin else { return }
        dismiss()
    }

    func dismiss() {
        duration = 0
        origin = nil
        deadline = nil
    }

    func remaining(at now: Date) -> TimeInterval {
        guard let deadline else { return 0 }
        return max(0, deadline.timeIntervalSince(now))
    }
}
