import UIKit

/// Runs `LogSetByVoiceIntent` in the app. With a scene on screen the request goes to the inbox
/// and the card listens, as it does for `workouttracker://dictate`, so the athlete sees the hold and can
/// clear it; with the app in the background, locked or closed, the headless Dictation listens and
/// the Live Activity reads back.
@MainActor
final class LogSetByVoicePerformer: LogSetByVoicePerforming {
    private let app: WorkoutApplication
    private let dictation: SetDictation?
    private let focus: ActiveSetFocusManager
    private let restTimer: RestTimer
    private let liveActivity: LiveActivityProductionAdapter
    private let entry: AppEntryInbox

    init(
        app: WorkoutApplication,
        dictation: SetDictation?,
        focus: ActiveSetFocusManager,
        restTimer: RestTimer,
        liveActivity: LiveActivityProductionAdapter,
        entry: AppEntryInbox
    ) {
        self.app = app
        self.dictation = dictation
        self.focus = focus
        self.restTimer = restTimer
        self.liveActivity = liveActivity
        self.entry = entry
    }

    func logSetByVoice() async throws {
        let route = LogSetByVoiceRoute.route(
            appIsInBackground: UIApplication.shared.applicationState == .background,
            hasMic: dictation != nil
        )
        switch route {
        case .card:
            entry.deliver(.dictateCurrentSet)
        case .nothing:
            break
        case .headless:
            try await listenHeadless()
        }
    }

    private func listenHeadless() async throws {
        guard let dictation else { return }
        let background = BackgroundDictation(
            app: app,
            dictation: dictation,
            focus: focus,
            restTimer: restTimer,
            liveActivity: liveActivity,
            signIn: GoogleSignInRestorer(),
            clock: ContinuousListeningClock()
        )
        if let refusal = await background.run().refusal {
            throw refusal
        }
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
