/// Where a Log a Set request goes when the intent runs in the app's process.
enum LogSetByVoiceRoute: Equatable, Sendable {
    /// A scene is on screen: the request goes to the inbox and the card listens, so the athlete
    /// sees the hold and can clear it.
    case card
    /// The app is in the background, locked or closed: the headless Dictation listens and the
    /// Live Activity reads back.
    case headless
    /// Nothing can listen with the app behind, as on the Simulator, which has no SpeechAnalyzer.
    case nothing

    static func route(appIsInBackground: Bool, hasMic: Bool) -> LogSetByVoiceRoute {
        guard appIsInBackground else { return .card }
        return hasMic ? .headless : .nothing
    }
}
