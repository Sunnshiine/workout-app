import AppIntents

/// What the Action button, Siri, and Spotlight offer without the athlete building a shortcut.
struct WorkoutTrackerShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: LogSetByVoiceIntent(),
            phrases: [
                "Log a Set in \(.applicationName)",
                "Dictate a Set in \(.applicationName)"
            ],
            shortTitle: "Log a Set",
            systemImageName: "mic"
        )
    }
}
