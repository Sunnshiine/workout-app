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
        #if DEBUG
            if UITestFixture.isEnabled {
                Self.applyUITestFixtures(to: app)
            }
        #endif
    }

    private static func launchEnvironment() -> AppEnvironment {
        #if DEBUG
            if UITestFixture.isEnabled {
                return .uiTestFixture()
            }
        #endif
        return .device()
    }

    #if DEBUG
        private static func applyUITestFixtures(to app: WorkoutApplication) {
            let settings = app.settings
            // Pins the fixture's appearance regardless of the seeded Block, so screenshots stay deterministic.
            settings.setAppearance(UITestFixture.appearanceOverride ?? .system)
            settings.isSignedIn = true
            // Onboarding mode leaves the spreadsheet unset so the app lands on the sheet picker,
            // while the seeded (stale) Block stays in the store to prove it is never shown for the
            // newly selected sheet.
            if !UITestFixture.startsInOnboarding {
                settings.setSpreadsheet(id: WorkoutFixtureScenarios.sheetId, title: "Fixture Training Log")
            }

            let workout = app.workout
            if UITestFixture.startsWithCurrentSessionOverride {
                workout.show(week: 1, day: 3)
                workout.makeDisplayedSessionCurrent()
            }
            if UITestFixture.startsWithMoveOnCelebration || UITestFixture.startsWithPerfectMoveOnCelebration {
                workout.requestMoveOnCelebration()
            }
            if UITestFixture.startsInBlockOverview {
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
                .onOpenURL { GIDSignIn.sharedInstance.handle($0) }
                .task {
                    #if DEBUG
                        if UITestFixture.isEnabled { return }
                    #endif
                    app.settings.isSignedIn = await GoogleAuth.restorePreviousSignIn()
                }
        }
        .modelContainer(app.container)
    }
}
