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
    @ObservationIgnored private var originSetObjectID: ObjectIdentifier?

    @ObservationIgnored private let clock: any RestClock
    @ObservationIgnored private let notificationScheduler: (any RestNotificationScheduling)?

    init(
        clock: any RestClock = SystemRestClock(),
        notificationScheduler: (any RestNotificationScheduling)? = nil
    ) {
        self.clock = clock
        self.notificationScheduler = notificationScheduler
    }

    var remaining: TimeInterval {
        remaining(at: clock.now)
    }

    var isRunning: Bool {
        remaining > 0
    }

    func start(
        duration: TimeInterval,
        origin: ActiveSetID?,
        originSetObjectID: ObjectIdentifier? = nil
    ) {
        self.duration = duration
        self.origin = origin
        self.originSetObjectID = originSetObjectID
        if deadline != nil {
            notificationScheduler?.cancel()
        }
        let deadline = clock.now.addingTimeInterval(duration)
        self.deadline = deadline
        notificationScheduler?.schedule(deadline: deadline)
        restartRevision += 1
    }

    func cancel(
        ifOriginMatches origin: ActiveSetID?,
        originSetObjectID: ObjectIdentifier? = nil
    ) {
        guard self.origin == origin, self.originSetObjectID == originSetObjectID else { return }
        dismiss()
    }

    func dismiss() {
        duration = 0
        origin = nil
        originSetObjectID = nil
        deadline = nil
        notificationScheduler?.cancel()
    }

    func remaining(at now: Date) -> TimeInterval {
        guard let deadline else { return 0 }
        return max(0, deadline.timeIntervalSince(now))
    }
}
