import AppIntents

/// Turns the Lock Screen card to the Card Face its control names, without opening the app. It
/// writes nothing. A `LiveActivityIntent` runs in the app's process even from the widget
/// extension's button.
struct TurnLockScreenCardIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "Turn the Lock Screen card"
    static let description = IntentDescription(
        "Turns your Lock Screen card to the Coach Note, the Reps or the RPE of the Set it shows, and back, without opening WorkoutTracker."
    )
    static let supportedModes: IntentModes = .background
    static let isDiscoverable = false

    @Parameter(title: "Face") var face: String
    /// The Set a turn toward its Reps or its RPE is about. Nil from a control that names no Set.
    @Parameter(title: "Set") var setIdentity: String?

    init() {}

    init(to face: LockScreenCardFace, pressing setIdentity: String? = nil) {
        self.face = face.token
        self.setIdentity = setIdentity
    }

    @MainActor
    func perform() async throws -> some IntentResult {
        guard let performer = LockScreenPresses.performer else { throw LockScreenPresses.PerformedOutsideTheApp() }
        guard let face = LockScreenCardFace(token: face) else { throw LockScreenPresses.UnreadableFace(token: face) }
        await performer.turnCard(to: face, pressing: setIdentity)
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

    struct UnreadableFace: Error, CustomStringConvertible {
        let token: String

        var description: String { "A Lock Screen press named the Card Face \"\(token)\", which the card has not got." }
    }
}

@MainActor
protocol LockScreenPressPerforming: AnyObject {
    func turnCard(to face: LockScreenCardFace, pressing setIdentity: String?) async
    func logSet(setIdentity: String, reps: Int, rpe: String) async
}
