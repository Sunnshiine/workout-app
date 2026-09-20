import Foundation

enum RestHapticKind: Equatable, Hashable, Sendable {
    case lightTap
    case expiryBuzz
}

struct RestPillUrgencyCue: Equatable, Sendable {
    let remainingSeconds: Int
    let reduceMotion: Bool

    init(remaining: TimeInterval, reduceMotion: Bool) {
        remainingSeconds = max(0, Int(ceil(remaining)))
        self.reduceMotion = reduceMotion
    }

    var isActive: Bool {
        remainingSeconds <= 5
    }

    var shouldBreathe: Bool {
        isActive && !reduceMotion
    }

    var breathScale: Double {
        shouldBreathe ? 1.035 : 1
    }

    var accentIntensity: Double {
        guard isActive else { return 0 }
        guard !reduceMotion else { return 1 }

        let completedBeats = Double(5 - min(5, remainingSeconds))
        return min(1, 0.5 + completedBeats * 0.125)
    }
}

struct RestHapticEvent: Equatable, Hashable, Sendable {
    let offset: TimeInterval
    let kind: RestHapticKind
}

struct RestHapticSchedule: Equatable, Sendable {
    private static let finalTapRemainingSeconds = [5, 4, 3, 2, 1]

    let duration: TimeInterval

    var events: [RestHapticEvent] {
        let taps = Self.finalTapRemainingSeconds
            .map(TimeInterval.init)
            .filter { $0 <= duration }
            .map { RestHapticEvent(offset: duration - $0, kind: .lightTap) }

        guard duration >= 0 else { return [] }
        return taps + [RestHapticEvent(offset: duration, kind: .expiryBuzz)]
    }
}

/// Owns the elapsed/played bookkeeping the pill used to carry, so "which haptic events are due on
/// this tick" is answered inside the rest module rather than in the view. Each advance surfaces the
/// events that became due since the previous advance and never a second time. While the scene is
/// inactive taps are suppressed, but the emitter still advances its cursor so returning to active
/// does not replay the missed events in a burst — matching the pill's former behaviour exactly.
struct RestHapticEmitter: Equatable, Sendable {
    private let schedule: RestHapticSchedule
    private var previousElapsed: TimeInterval?
    private var playedEvents: Set<RestHapticEvent> = []

    init(duration: TimeInterval) {
        schedule = RestHapticSchedule(duration: duration)
    }

    /// Advance to `elapsed`, returning the events that became due since the last advance. The
    /// first advance only seeds the cursor and surfaces nothing.
    mutating func due(elapsed: TimeInterval, sceneActive: Bool) -> [RestHapticEvent] {
        defer { previousElapsed = elapsed }

        guard sceneActive, let previousElapsed else { return [] }

        let events = schedule.events.filter { event in
            event.offset > previousElapsed && event.offset <= elapsed && !playedEvents.contains(event)
        }
        for event in events {
            playedEvents.insert(event)
        }
        return events
    }
}
