import Foundation

struct RestDurationSetting: Equatable, Sendable {
    static let minimumSeconds = 30
    static let maximumSeconds = 600
    static let stepSeconds = 30
    static let standard = RestDurationSetting(seconds: 120)
    static let superset = RestDurationSetting(seconds: 30)

    let seconds: Int

    init(seconds: Int) {
        self.seconds = min(Self.maximumSeconds, max(Self.minimumSeconds, seconds))
    }

    var timeInterval: TimeInterval {
        TimeInterval(seconds)
    }

    var displayText: String {
        let minutes = seconds / 60
        let secondsRemainder = seconds % 60
        return "\(minutes):\(String(format: "%02d", secondsRemainder))"
    }

    var canDecrement: Bool {
        seconds > Self.minimumSeconds
    }

    var canIncrement: Bool {
        seconds < Self.maximumSeconds
    }

    func decremented() -> RestDurationSetting {
        RestDurationSetting(seconds: seconds - Self.stepSeconds)
    }

    func incremented() -> RestDurationSetting {
        RestDurationSetting(seconds: seconds + Self.stepSeconds)
    }
}
