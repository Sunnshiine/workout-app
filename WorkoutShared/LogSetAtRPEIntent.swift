import AppIntents

/// Logs the Set a Lock Screen card offers at the RPE the athlete tapped, without opening the app. A
/// `LiveActivityIntent` runs in the app's process even from the widget extension's button. The app
/// registers the performer; the extension never performs it, and fails loudly if asked to.
struct LogSetAtRPEIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "Log a Set at an RPE"
    static let description = IntentDescription(
        "Logs the Set your Lock Screen card shows at the RPE you tap, without opening WorkoutTracker."
    )
    static let supportedModes: IntentModes = .background
    static let isDiscoverable = false

    @Parameter(title: "Set") var setIdentity: String
    @Parameter(title: "RPE") var rpe: String

    init() {}

    init(setIdentity: String, rpe: String) {
        self.setIdentity = setIdentity
        self.rpe = rpe
    }

    @MainActor
    func perform() async throws -> some IntentResult {
        guard let performer = Self.performer else { throw PerformedOutsideTheApp() }
        await performer.logSet(setIdentity: setIdentity, rpe: rpe)
        return .result()
    }
}

extension LogSetAtRPEIntent {
    /// What the app does when the intent runs. `WorkoutTrackerApp` sets it once, before its first
    /// scene, so a background launch with no scene finds it.
    @MainActor static var performer: (any LogSetAtRPEPerforming)?

    struct PerformedOutsideTheApp: Error, CustomStringConvertible {
        var description: String { "LogSetAtRPEIntent ran in a process that registered no performer; only the app performs it." }
    }
}

@MainActor
protocol LogSetAtRPEPerforming: AnyObject {
    func logSet(setIdentity: String, rpe: String) async
}
