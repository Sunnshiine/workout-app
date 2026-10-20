import AppIntents

/// Opens the app on the Current Session's active Set, listening for its Spoken Set. It runs only
/// in the foreground, because the app records only while it is open.
struct StartSetDictationIntent: AppIntent {
    static let title: LocalizedStringResource = "Log a Set"
    static let description = IntentDescription("Opens your Current Session's active Set and listens for it.")
    static let supportedModes: IntentModes = .foreground

    @AppDependency private var entry: AppEntryInbox

    @MainActor
    func perform() async throws -> some IntentResult {
        entry.deliver(.dictateCurrentSet)
        return .result()
    }
}

/// What the Action button, Siri, and Spotlight offer without the athlete building a shortcut.
struct WorkoutTrackerShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: StartSetDictationIntent(),
            phrases: [
                "Log a Set in \(.applicationName)",
                "Dictate a Set in \(.applicationName)"
            ],
            shortTitle: "Log a Set",
            systemImageName: "mic"
        )
    }
}
