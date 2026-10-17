import Foundation

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
