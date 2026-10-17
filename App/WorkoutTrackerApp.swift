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
    /// One owner of the Live Activity per process, whichever surface asked for it.
    @State private var liveActivityAdapter: LiveActivityProductionAdapter
    @State private var entry: AppEntryInbox

    init() {
        #if canImport(UserNotifications)
            RestNotificationCenterScheduler.shared.installForegroundDelegate()
        #endif
        // swiftlint:disable:next force_try
        let app = try! WorkoutApplication(environment: Self.launchEnvironment())
        _app = State(initialValue: app)
        let dictation = Self.setTranscriber().map { SetDictation(transcriber: $0) }
        _dictation = State(initialValue: dictation)
        let focus = ActiveSetFocusManager(session: nil)
        _focus = State(initialValue: focus)
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
            if UITestFixture.isEnabled {
                Self.applyUITestFixtures(to: app)
            }
        #endif
    }

    private static func launchEnvironment() -> AppEnvironment {
        #if DEBUG
            if UITestFixture.isEnabled {
                return .uiTestFixture(launch: UITestFixture.launch)
            }
        #endif
        return .device()
    }

    /// SpeechAnalyzer does not run in the Simulator, so a Simulator card has a mic only when a
    /// fixture launch names what it hears.
    private static func setTranscriber() -> (any SetTranscriber)? {
        #if DEBUG
            if UITestFixture.isEnabled {
                return UITestFixture.launch.dictatedTranscript.map { CannedSetTranscriber(candidates: [$0]) }
            }
        #endif
        #if targetEnvironment(simulator)
            return nil
        #else
            return SpeechAnalyzerSetTranscriber()
        #endif
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

    #if DEBUG
        private static func applyUITestFixtures(to app: WorkoutApplication) {
            let settings = app.settings
            // Pins the fixture's appearance regardless of the seeded Block, so screenshots stay deterministic.
            do {
                settings.setAppearance(try UITestFixture.launch.appearance)
            } catch {
                fatalError("\(error)")
            }
            // A late sign-in leaves the restore running, as a device does, until the launch task ends it.
            if !UITestFixture.launch.signsInLate {
                settings.isSignedIn = true
            }
            // Onboarding mode leaves the spreadsheet unset so the app lands on the sheet picker,
            // while the seeded (stale) Block stays in the store to prove it is never shown for the
            // newly selected sheet.
            if !UITestFixture.launch.startsInOnboarding {
                settings.setSpreadsheet(id: WorkoutFixtureScenarios.sheetId, title: "Fixture Training Log")
            }

            let workout = app.workout
            if UITestFixture.launch.startsWithCurrentSessionOverride {
                workout.show(SessionAddress(week: 1, day: 3))
                workout.makeViewedSessionCurrent()
            }
            if UITestFixture.launch.startsWithMoveOnCelebration || UITestFixture.launch.startsWithPerfectMoveOnCelebration {
                workout.requestMoveOnCelebration()
            }
            if UITestFixture.launch.startsInBlockOverview {
                workout.requestBlockOverviewPresentation()
            }
        }
    #endif

    var body: some Scene {
        WindowGroup {
            RootView(dictation: dictation, focus: focus, liveActivityAdapter: liveActivityAdapter)
                .environment(app.settings)
                .environment(app.workout)
                .environment(app.sync)
                .environment(app.lastPerformed)
                .environment(app.historyFill)
                .environment(app.connection)
                .environment(entry)
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
}
