import UIKit

/// Runs `LogSetByVoiceIntent` in the app. With a scene on screen the card listens, as link 3's
/// route has it, so the athlete sees the hold and can clear it; with the app in the background,
/// locked or closed, the headless Dictation listens and the Live Activity reads back.
@MainActor
final class LogSetByVoicePerformer: LogSetByVoicePerforming {
    private let app: WorkoutApplication
    private let dictation: SetDictation?
    private let liveActivity: LiveActivityProductionAdapter
    private let entry: AppEntryInbox

    init(app: WorkoutApplication, dictation: SetDictation?, liveActivity: LiveActivityProductionAdapter, entry: AppEntryInbox) {
        self.app = app
        self.dictation = dictation
        self.liveActivity = liveActivity
        self.entry = entry
    }

    func logSetByVoice() async {
        guard UIApplication.shared.applicationState == .background else {
            entry.deliver(.dictateCurrentSet)
            return
        }
        // The Simulator has no SpeechAnalyzer, so a launch that names no transcript has no mic.
        guard let dictation else { return }
        let background = BackgroundDictation(
            app: app,
            dictation: dictation,
            liveActivity: liveActivity,
            signIn: GoogleSignInRestorer(),
            entry: entry,
            clock: ContinuousListeningClock(),
            now: Date.init
        )
        _ = await background.run()
    }
}

@MainActor
private final class GoogleSignInRestorer: SignInRestoring {
    func restorePreviousSignIn() async -> Bool {
        #if DEBUG
            if UITestFixture.isEnabled { return true }
        #endif
        return await GoogleAuth.restorePreviousSignIn()
    }
}
