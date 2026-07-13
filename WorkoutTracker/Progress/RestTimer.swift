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

enum RestKind: Equatable, Sendable {
    case standard
    case superset

    var label: String {
        switch self {
        case .standard:
            "Rest"
        case .superset:
            "Superset rest"
        }
    }
}

@MainActor
@Observable
final class RestTimer {
    /// The one representation of the running rest: its `start…end` span and chosen kind. The
    /// start instant the timer computes is retained here rather than discarded, so every
    /// consumer — pill, Live Activity, coordinator — reads the same interval instead of
    /// rebuilding it.
    private(set) var interval: RestInterval?
    private(set) var origin: ActiveSetID?
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

    var label: String {
        (interval?.kind ?? .standard).label
    }

    func start(
        duration: TimeInterval,
        origin: ActiveSetID?,
        originSetObjectID: ObjectIdentifier? = nil,
        kind: RestKind = .standard
    ) {
        self.origin = origin
        self.originSetObjectID = originSetObjectID
        if interval != nil {
            notificationScheduler?.cancel()
        }
        let interval = RestInterval(start: clock.now, duration: duration, kind: kind)
        self.interval = interval
        notificationScheduler?.schedule(deadline: interval.end)
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
        origin = nil
        originSetObjectID = nil
        interval = nil
        notificationScheduler?.cancel()
    }

    func expireIfNeeded(at now: Date) {
        guard interval != nil, remaining(at: now) <= 0 else { return }
        dismiss()
    }

    func remaining(at now: Date) -> TimeInterval {
        interval?.remaining(at: now) ?? 0
    }
}
