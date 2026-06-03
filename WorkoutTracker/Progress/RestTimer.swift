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
    private(set) var deadline: Date?
    private(set) var origin: ActiveSetID?
    private(set) var duration: TimeInterval = 0
    private(set) var kind: RestKind = .standard
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
        kind.label
    }

    func start(
        duration: TimeInterval,
        origin: ActiveSetID?,
        originSetObjectID: ObjectIdentifier? = nil,
        kind: RestKind = .standard
    ) {
        self.duration = duration
        self.origin = origin
        self.originSetObjectID = originSetObjectID
        self.kind = kind
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
        kind = .standard
        deadline = nil
        notificationScheduler?.cancel()
    }

    func expireIfNeeded(at now: Date) {
        guard deadline != nil, remaining(at: now) <= 0 else { return }
        dismiss()
    }

    func remaining(at now: Date) -> TimeInterval {
        guard let deadline else { return 0 }
        return max(0, deadline.timeIntervalSince(now))
    }
}
