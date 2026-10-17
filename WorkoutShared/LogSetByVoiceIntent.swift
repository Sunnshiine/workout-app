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

    @AppDependency(key: LogSetByVoiceIntent.performerKey) private var performer: any LogSetByVoicePerforming

    @MainActor
    func perform() async throws -> some IntentResult {
        await performer.logSetByVoice()
        return .result()
    }
}

extension LogSetByVoiceIntent {
    /// The `AppDependencyManager` key the app registers its performer under.
    static let performerKey = "LogSetByVoiceIntent.performer"
}

/// What the app does when the intent runs: the one entry for every surface outside the app.
@MainActor
protocol LogSetByVoicePerforming: AnyObject, Sendable {
    func logSetByVoice() async
}
