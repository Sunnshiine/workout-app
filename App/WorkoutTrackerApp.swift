import GoogleSignIn
import SwiftData
import SwiftUI

@main
struct WorkoutTrackerApp: App {
    @State private var app: WorkoutApplication

    init() {
        #if canImport(UserNotifications)
            RestNotificationCenterScheduler.shared.installForegroundDelegate()
        #endif
        // swiftlint:disable:next force_try
        let app = try! WorkoutApplication(environment: Self.launchEnvironment())
        _app = State(initialValue: app)
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

    /// Returns nil when there is nothing to restore. A fixture launch signs in up front unless it
    /// asks to sign in late.
    private static func restoreSignIn() async -> Bool? {
        #if DEBUG
            if UITestFixture.isEnabled {
                guard UITestFixture.launch.signsInLate else { return nil }
                try? await Task.sleep(for: .seconds(3))
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
            settings.isSignedIn = !UITestFixture.launch.signsInLate
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
            RootView()
                .environment(app.settings)
                .environment(app.workout)
                .environment(app.sync)
                .environment(app.lastPerformed)
                .environment(app.historyFill)
                .environment(app.connection)
                #if DEBUG
                    .transaction { transaction in
                        guard UITestFixture.disablesAnimations else { return }
                        // Clearing the animation stops withAnimation, and only disablesAnimations
                        // stops .animation(_:value:) adding one back. Either alone leaves motion.
                        transaction.animation = nil
                        transaction.disablesAnimations = true
                    }
                #endif
                .onOpenURL { GIDSignIn.sharedInstance.handle($0) }
                .task {
                    guard let isSignedIn = await Self.restoreSignIn() else { return }
                    // A restore hands back a sign-in the athlete already had, so RootView cuts to
                    // where they were. Only their own sheet commit plays the onboarding handoff.
                    withTransaction(\.disablesAnimations, true) {
                        app.settings.isSignedIn = isSignedIn
                    }
                }
        }
        .modelContainer(app.container)
    }
}
