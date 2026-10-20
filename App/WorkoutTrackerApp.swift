import AppIntents
import GoogleSignIn
import SwiftData
import SwiftUI

@main
struct WorkoutTrackerApp: App {
    @State private var app: WorkoutApplication
    @State private var transcriber = Self.setTranscriber()
    @State private var entry: AppEntryInbox

    init() {
        #if canImport(UserNotifications)
            RestNotificationCenterScheduler.shared.installForegroundDelegate()
        #endif
        // swiftlint:disable:next force_try
        let app = try! WorkoutApplication(environment: Self.launchEnvironment())
        _app = State(initialValue: app)
        // Registered before the first scene, so an intent that cold-launches the app finds it.
        let entry = AppEntryInbox()
        _entry = State(initialValue: entry)
        AppDependencyManager.shared.add(dependency: entry)
        UISegmentedControl.appearance().selectedSegmentTintColor = Theme.selectedSegmentFill
        #if DEBUG
            #if canImport(UIKit)
                if UITestFixture.disablesAnimations {
                    UIView.setAnimationsEnabled(false)
                }
            #endif
        #endif
    }

    private static func launchEnvironment() -> AppEnvironment {
        #if DEBUG
            if UITestFixture.isEnabled {
                return .inMemory(sheets: UITestFixture.sheets)
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
                UITestFixtureBootGate(app: app) { RootView(transcriber: transcriber) }
            } else {
                RootView(transcriber: transcriber)
            }
        #else
            RootView(transcriber: transcriber)
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
