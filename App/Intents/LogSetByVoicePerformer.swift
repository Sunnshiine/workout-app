import UIKit

/// Runs `LogSetByVoiceIntent` in the app. With a scene on screen the request goes to the inbox
/// and the card listens, as it does for the dictate link, so the athlete sees the hold and can
/// clear it; with the app in the background, locked or closed, the headless Dictation listens and
/// the Live Activity reads back.
@MainActor
final class LogSetByVoicePerformer: LogSetByVoicePerforming {
    private let app: WorkoutApplication
    private let dictation: SetDictation?
    private let focus: ActiveSetFocusManager
    private let liveActivity: LiveActivityProductionAdapter
    private let entry: AppEntryInbox

    init(
        app: WorkoutApplication,
        dictation: SetDictation?,
        focus: ActiveSetFocusManager,
        liveActivity: LiveActivityProductionAdapter,
        entry: AppEntryInbox
    ) {
        self.app = app
        self.dictation = dictation
        self.focus = focus
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
            focus: focus,
            liveActivity: liveActivity,
            signIn: GoogleSignInRestorer(),
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
