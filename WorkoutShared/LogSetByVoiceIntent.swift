import AppIntents

/// Listens for the Current Session's active Set and logs it, from the Action button, a control,
/// Siri, or Shortcuts, with the phone locked or not. An `AudioRecordingIntent` may record in the
/// background while a Live Activity is up, and a `LiveActivityIntent` runs in the app's process
/// even from the widget extension's control and may start that Live Activity there. The app
/// registers the performer; the extension never performs it, and fails loudly if asked to.
struct LogSetByVoiceIntent: AudioRecordingIntent, LiveActivityIntent {
    static let title: LocalizedStringResource = "Log a Set"
    static let description = IntentDescription(
        "Listens for your Current Session's active Set and logs it, without opening WorkoutTracker."
    )
    static let supportedModes: IntentModes = .background

    @MainActor
    func perform() async throws -> some IntentResult {
        guard let performer = Self.performer else { throw PerformedOutsideTheApp() }
        try await performer.logSetByVoice()
        return .result()
    }
}

extension LogSetByVoiceIntent {
    /// What the app does when the intent runs. `WorkoutTrackerApp` sets it once, before its first
    /// scene, so a background launch with no scene finds it; the widget extension never does, so
    /// a run that reaches the extension throws instead of doing work there. It is not an
    /// `@AppDependency` because that would make the extension's control depend on a registry the
    /// extension never fills, and the intent carries no stored state, so nothing of the app's is
    /// serialized with it.
    @MainActor static var performer: (any LogSetByVoicePerforming)?

    struct PerformedOutsideTheApp: Error, CustomStringConvertible {
        var description: String { "LogSetByVoiceIntent ran in a process that registered no performer; only the app performs it." }
    }
}

/// What the app does when the intent runs: the one entry for every surface outside the app. It
/// throws what the surface should show when the press could not run, in the athlete's words.
@MainActor
protocol LogSetByVoicePerforming: AnyObject {
    func logSetByVoice() async throws
}
