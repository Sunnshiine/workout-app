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
    /// The expiry buzz, published at the deadline for a still-mounted pill to play. The timer is
    /// the single author of the "rest ended" haptic — never the view — and holds the interval alive
    /// across a short linger so the pill is still on screen to feel it before the rest clears.
    /// Empty whenever there is nothing new to play.
    private(set) var expiryHaptics: [RestHapticEvent] = []
    @ObservationIgnored private var originSetObjectID: ObjectIdentifier?
    @ObservationIgnored private var hapticEmitter: RestHapticEmitter?

    @ObservationIgnored private let clock: any RestClock
    @ObservationIgnored private let notificationScheduler: (any RestNotificationScheduling)?
    @ObservationIgnored private let expiryScheduler: any RestExpiryScheduling

    /// How long the pill lingers past the deadline so the expiry buzz is felt before the rest
    /// clears — mirrors the pre-refactor dismiss-after-beat grace.
    @ObservationIgnored private let expiryLingerSeconds: TimeInterval = 0.5

    init(
        clock: any RestClock = SystemRestClock(),
        notificationScheduler: (any RestNotificationScheduling)? = nil,
        expiryScheduler: any RestExpiryScheduling = RestExpiryTimerScheduler()
    ) {
        self.clock = clock
        self.notificationScheduler = notificationScheduler
        self.expiryScheduler = expiryScheduler
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
        expiryHaptics = []
        if interval != nil {
            notificationScheduler?.cancel()
        }
        let interval = RestInterval(start: clock.now, duration: duration, kind: kind)
        self.interval = interval
        hapticEmitter = RestHapticEmitter(duration: duration)
        notificationScheduler?.schedule(deadline: interval.end)
        expiryScheduler.schedule(deadline: interval.end) { [weak self] in
            self?.expireIfNeeded(at: interval.end)
        }
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
        hapticEmitter = nil
        expiryHaptics = []
        notificationScheduler?.cancel()
        expiryScheduler.cancel()
    }

    /// The rest module's answer to "which haptic events are due on this tick" — the final-five
    /// light taps. Driven by the pill's clock but owned here: the pill plays whatever this surfaces
    /// without building the schedule or tracking played/elapsed state. Taps are suppressed while the
    /// scene is inactive, without replaying the missed ones when it returns. The expiry buzz is
    /// authored at the deadline by `expireIfNeeded` instead, since a tick can only land after the
    /// rest would otherwise clear; draining through the shared emitter keeps the two paths from ever
    /// double-playing it.
    func dueHapticEvents(at now: Date, sceneActive: Bool) -> [RestHapticEvent] {
        guard let interval else { return [] }
        return hapticEmitter?.due(elapsed: interval.elapsed(at: now), sceneActive: sceneActive) ?? []
    }

    /// The one author of the "rest ended" instant. Driven by the expiry scheduler at the
    /// deadline — no view is required — so a rest ends and its pending notification is cancelled
    /// exactly once whether or not the pill is on screen.
    ///
    /// If a pill has been surfacing haptics, the expiry buzz is authored here and published for it
    /// to play, and the interval is held for a short linger so the pill is still mounted to feel it
    /// before the rest clears. With no pill (nothing to play), the rest clears immediately.
    /// Idempotent: a stray call mid-linger, after the interval clears, or before the deadline is a
    /// no-op.
    func expireIfNeeded(at now: Date) {
        guard let interval, remaining(at: now) <= 0, expiryHaptics.isEmpty else { return }
        // Drain through the emitter: it surfaces the buzz only once (no duplicate if a tick already
        // played it), and its advancing cursor is the signal that a pill was actually ticking. The
        // timer always authors the buzz; the pill gates whether to play it on the scene phase.
        let buzz = hapticEmitter?.due(elapsed: interval.elapsed(at: now), sceneActive: true) ?? []
        guard !buzz.isEmpty else {
            dismiss()
            return
        }
        expiryHaptics = buzz
        expiryScheduler.schedule(deadline: now.addingTimeInterval(expiryLingerSeconds)) { [weak self] in
            self?.dismiss()
        }
    }

    func remaining(at now: Date) -> TimeInterval {
        interval?.remaining(at: now) ?? 0
    }
}
