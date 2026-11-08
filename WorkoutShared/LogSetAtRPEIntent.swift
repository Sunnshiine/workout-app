import AppIntents

/// Turns the Lock Screen card's row to RPE Chips for the Reps the athlete tapped, or back to Reps
/// for nil, without opening the app. It writes nothing. A `LiveActivityIntent` runs in the app's
/// process even from the widget extension's button.
struct ChooseRepsIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "Choose the Reps of a Set"
    static let description = IntentDescription(
        "Chooses the Reps of the Set your Lock Screen card shows, then offers its RPE, without opening WorkoutTracker."
    )
    static let supportedModes: IntentModes = .background
    static let isDiscoverable = false

    @Parameter(title: "Set") var setIdentity: String
    @Parameter(title: "Reps") var reps: Int?

    init() {}

    init(setIdentity: String, reps: Int?) {
        self.setIdentity = setIdentity
        self.reps = reps
    }

    @MainActor
    func perform() async throws -> some IntentResult {
        guard let performer = LockScreenPresses.performer else { throw LockScreenPresses.PerformedOutsideTheApp() }
        await performer.chooseReps(setIdentity: setIdentity, reps: reps)
        return .result()
    }
}

/// Logs the Set a Lock Screen card offers at the Reps and the RPE the athlete tapped, without
/// opening the app. The app registers the performer; the extension never performs it, and fails
/// loudly if asked to.
struct LogSetAtRPEIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "Log a Set at an RPE"
    static let description = IntentDescription(
        "Logs the Set your Lock Screen card shows at the Reps and the RPE you tap, without opening WorkoutTracker."
    )
    static let supportedModes: IntentModes = .background
    static let isDiscoverable = false

    @Parameter(title: "Set") var setIdentity: String
    @Parameter(title: "Reps") var reps: Int
    @Parameter(title: "RPE") var rpe: String

    init() {}

    init(setIdentity: String, reps: Int, rpe: String) {
        self.setIdentity = setIdentity
        self.reps = reps
        self.rpe = rpe
    }

    @MainActor
    func perform() async throws -> some IntentResult {
        guard let performer = LockScreenPresses.performer else { throw LockScreenPresses.PerformedOutsideTheApp() }
        await performer.logSet(setIdentity: setIdentity, reps: reps, rpe: rpe)
        return .result()
    }
}

enum LockScreenPresses {
    /// What the app does when a press runs. `WorkoutTrackerApp` sets it once, before its first
    /// scene, so a background launch with no scene finds it.
    @MainActor static var performer: (any LockScreenPressPerforming)?

    struct PerformedOutsideTheApp: Error, CustomStringConvertible {
        var description: String { "A Lock Screen press ran in a process that registered no performer; only the app performs it." }
    }
}

@MainActor
protocol LockScreenPressPerforming: AnyObject {
    func chooseReps(setIdentity: String, reps: Int?) async
    func logSet(setIdentity: String, reps: Int, rpe: String) async
}
