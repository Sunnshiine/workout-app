import GoogleSignIn
import SwiftData
import SwiftUI

@main
struct WorkoutTrackerApp: App {
    @State private var app: WorkoutApplication
    /// One Dictation per process: the card and the headless intent share the mic through it.
    @State private var dictation: SetDictation?
    /// One active Set per process: the card and the headless intent listen on the same one.
    @State private var focus: ActiveSetFocusManager
    /// One rest per process: whichever write starts it, the stage's pill, the Live Activity, and
    /// the rest-end notification read the same one.
    @State private var restTimer: RestTimer
    @State private var countdown: EffortCountdown
    /// One owner of the Live Activity per process, whichever surface asked for it.
    @State private var liveActivityAdapter: LiveActivityProductionAdapter
    @State private var entry: AppEntryInbox
    private let speechModelCaption: (@Sendable () -> String)?
    private let metricKit: DictationMetricKit

    init() {
        #if canImport(UserNotifications)
            RestNotificationCenterScheduler.shared.installForegroundDelegate()
        #endif
        // swiftlint:disable:next force_try
        let app = try! WorkoutApplication(environment: Self.launchEnvironment())
        _app = State(initialValue: app)
        metricKit = DictationMetricKit(journal: app.dictationJournal)
        let speech = Self.speech()
        let dictation = speech.map {
            SetDictation(
                transcriber: $0.live,
                reader: $0.recording,
                journal: app.dictationJournal,
                decisionDeadline: Self.decisionDeadline()
            )
        }
        speechModelCaption = speech?.caption
        _dictation = State(initialValue: dictation)
        let focus = ActiveSetFocusManager(session: nil)
        _focus = State(initialValue: focus)
        let restTimer = RestTimer(notificationScheduler: RestNotificationCenterScheduler.shared)
        _restTimer = State(initialValue: restTimer)
        _countdown = State(
            initialValue: EffortCountdown(clock: SystemRestClock(), scheduler: RestExpiryTimerScheduler(), cues: SpokenCountdownCues())
        )
        let liveActivityAdapter = LiveActivityProductionAdapter()
        _liveActivityAdapter = State(initialValue: liveActivityAdapter)
        let entry = AppEntryInbox()
        _entry = State(initialValue: entry)
        // Set before the first scene, so an intent that launches the app in the background, with
        // no scene at all, finds it.
        LogSetByVoiceIntent.performer = LogSetByVoicePerformer(
            app: app,
            dictation: dictation,
            focus: focus,
            restTimer: restTimer,
            liveActivity: liveActivityAdapter,
            entry: entry
        )
        UISegmentedControl.appearance().selectedSegmentTintColor = Theme.selectedSegmentFill
        #if DEBUG
            #if canImport(UIKit)
                if UITestFixture.disablesAnimations {
                    UIView.setAnimationsEnabled(false)
                }
            #endif
            if UITestFixture.launch.endsLiveActivities {
                liveActivityAdapter.end()
            }
        #endif
    }

    private static func launchEnvironment() -> AppEnvironment {
        #if DEBUG
            if UITestFixture.isEnabled {
                return .inMemory(sheets: UITestFixture.sheets, dictationRecords: .directory(AppEnvironment.deviceDictationRecords))
            }
        #endif
        return .device()
    }

    /// The two engines a press listens with, SpeechAnalyzer for the Live Transcript and Whisper for
    /// the Recording Transcript.
    private struct Speech {
        let live: any SetTranscriber
        let recording: any RecordingTranscriber
        /// The Settings row's words for the recording engine's model, where a real one runs.
        var caption: (@Sendable () -> String)?
    }

    /// SpeechAnalyzer does not run in the Simulator, so a Simulator card has a mic only when a
    /// fixture launch names what it hears. Only a phone makes the recording engine, so no Simulator
    /// or lane ever downloads its model.
    private static func speech() -> Speech? {
        #if DEBUG
            if UITestFixture.isEnabled {
                return UITestFixture.launch.dictatedTranscript.map(fixtureSpeech)
            }
        #endif
        #if targetEnvironment(simulator)
            return nil
        #else
            let engine = WhisperEngine(models: .applicationSupport)
            return Speech(live: SpeechAnalyzerSetTranscriber(), recording: engine, caption: { engine.caption })
        #endif
    }

    #if DEBUG
        /// A fixture's mic hears `transcript`. A Simulator proof launch also records a WAV file on
        /// each press and reads it with the real recording engine, its model from a host folder.
        private static func fixtureSpeech(hearing transcript: String) -> Speech {
            let launch = UITestFixture.launch
            let live = CannedSetTranscriber(candidates: [transcript], recording: launch.recordingPath.map(ProofLaunchFiles.recording) ?? [])
            guard let models = launch.speechModelsPath else {
                return Speech(live: live, recording: CannedRecordingTranscriber(answering: .missing(.modelNotReady(.absent))))
            }
            let engine = WhisperEngine(models: .host(ProofLaunchFiles.speechModels(at: models)))
            return Speech(live: live, recording: engine, caption: { engine.caption })
        }
    #endif

    /// A Simulator proof launch may wait longer for the Recording Transcript, which takes seconds
    /// there to decode.
    private static func decisionDeadline() -> Duration {
        #if DEBUG
            if UITestFixture.isEnabled {
                do {
                    return try UITestFixture.launch.decisionDeadline ?? SetDictation.decisionDeadline
                } catch {
                    fatalError("\(error)")
                }
            }
        #endif
        return SetDictation.decisionDeadline
    }

    /// Returns nil when there is no sign-in to write. A fixture launch already set it at init
    /// unless it asks to sign in late, and a late sign-in cancelled during its wait writes nothing.
    private static func restoreSignIn() async -> Bool? {
        #if DEBUG
            if UITestFixture.isEnabled {
                guard UITestFixture.launch.signsInLate else { return nil }
                do {
                    try await Task.sleep(for: .seconds(3))
                } catch {
                    return nil
                }
                return true
            }
        #endif
        return await GoogleAuth.restorePreviousSignIn()
    }

    var body: some Scene {
        WindowGroup {
            launchedRoot
                .environment(app.settings)
                .environment(app.workout)
                .environment(app.sync)
                .environment(app.lastPerformed)
                .environment(app.historyFill)
                .environment(app.connection)
                .environment(entry)
                .environment(\.speechModelCaption, speechModelCaption)
                .environment(\.exportDictationRecords, { try await app.exportDictations(into: .temporaryDirectory) })
                .environment(\.readBlockSheet, { try await app.sheet(tab: nil) })
                #if DEBUG
                    .transaction { transaction in
                        guard UITestFixture.disablesAnimations else { return }
                        // Clearing the animation stops withAnimation, and only disablesAnimations
                        // stops .animation(_:value:) adding one back. Either alone leaves motion.
                        transaction.animation = nil
                        transaction.disablesAnimations = true
                    }
                #endif
                .onOpenURL { url in
                    guard !entry.receive(url) else { return }
                    GIDSignIn.sharedInstance.handle(url)
                }
                .task {
                    guard let isSignedIn = await Self.restoreSignIn() else { return }
                    // A restore hands back a sign-in the athlete already had, so it must not
                    // animate. Only the athlete's own actions (a sheet commit, a manual sign-in,
                    // Sign Out) play the onboarding handoff.
                    withTransaction(\.disablesAnimations, true) {
                        app.settings.isSignedIn = isSignedIn
                    }
                }
        }
        .modelContainer(app.container)
    }

    @ViewBuilder private var launchedRoot: some View {
        #if DEBUG
            if UITestFixture.isEnabled {
                UITestFixtureBootGate(app: app) {
                    RootView(
                        dictation: dictation,
                        focus: focus,
                        restTimer: restTimer,
                        countdown: countdown,
                        liveActivityAdapter: liveActivityAdapter
                    )
                }
            } else {
                RootView(
                    dictation: dictation,
                    focus: focus,
                    restTimer: restTimer,
                    countdown: countdown,
                    liveActivityAdapter: liveActivityAdapter
                )
            }
        #else
            RootView(
                dictation: dictation,
                focus: focus,
                restTimer: restTimer,
                countdown: countdown,
                liveActivityAdapter: liveActivityAdapter
            )
        #endif
    }
}

#if DEBUG
    /// Shows nothing until `UITestFixture.boot` has filled the fixture application, so the first
    /// frame a UI test sees is the booted one.
    private struct UITestFixtureBootGate<Content: View>: View {
        let app: WorkoutApplication
        @ViewBuilder let content: () -> Content
        @State private var isBooted = false

        var body: some View {
            if isBooted {
                content()
            } else {
                Color.clear.task {
                    do {
                        try await UITestFixture.boot(app, launch: UITestFixture.launch, sheets: UITestFixture.sheets)
                    } catch {
                        fatalError("\(error)")
                    }
                    isBooted = true
                }
            }
        }
    }
#endif
