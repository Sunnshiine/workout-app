import GoogleSignIn
import SwiftData
import SwiftUI

@main
struct WorkoutTrackerApp: App {
    let container: ModelContainer
    @State private var settings: SettingsStore
    @State private var workout: WorkoutStore
    @State private var sync: SyncCoordinator
    @State private var lastPerformedLookup: LastPerformedLookupStore

    init() {
        #if canImport(UserNotifications)
            RestNotificationCenterScheduler.shared.installForegroundDelegate()
        #endif
        #if DEBUG
            if UITestFixture.isEnabled {
                let container = UITestFixture.makeContainer()
                self.container = container
                let ctx = container.mainContext
                let defaults = UITestFixture.makeDefaults()
                let settings = Self.makeUITestSettings(defaults: defaults)
                let lastPerformedLookup = LastPerformedLookupStore(context: ctx)
                let workout = WorkoutStore(
                    context: ctx,
                    defaults: defaults,
                    lastPerformedLookupRefresher: lastPerformedLookup
                )
                workout.reload()
                Self.applyUITestNavigationFixtures(to: workout)
                _settings = State(initialValue: settings)
                _workout = State(initialValue: workout)
                _sync = State(
                    initialValue: SyncCoordinator(
                        client: UITestFixture.makeSheetsClient(),
                        context: ctx,
                        lastPerformedLookupRefresher: lastPerformedLookup
                    )
                )
                _lastPerformedLookup = State(initialValue: lastPerformedLookup)
                return
            }
        #endif
        // swiftlint:disable:next force_try
        let container = try! ModelContainer(
            for: Block.self, PendingWrite.self, WriteTargetAuditEntry.self, LastPerformedEntry.self, HistoryFillCursor.self
        )
        self.container = container
        let ctx = container.mainContext
        let lastPerformedLookup = LastPerformedLookupStore(context: ctx)
        _settings = State(initialValue: SettingsStore(hasPriorAppState: Self.hasPriorAppState(in: ctx)))
        _workout = State(
            initialValue: WorkoutStore(
                context: ctx,
                lastPerformedLookupRefresher: lastPerformedLookup
            )
        )
        _sync = State(
            initialValue: SyncCoordinator(
                client: GoogleSheetsClient(),
                context: ctx,
                lastPerformedLookupRefresher: lastPerformedLookup
            )
        )
        _lastPerformedLookup = State(initialValue: lastPerformedLookup)
    }

    @MainActor
    private static func hasPriorAppState(in context: ModelContext) -> Bool {
        ((try? context.fetch(FetchDescriptor<Block>()).isEmpty) == false)
    }

    #if DEBUG
        private static func applyUITestNavigationFixtures(to workout: WorkoutStore) {
            applyCurrentSessionOverrideFixture(to: workout)
            if UITestFixture.startsWithMoveOnCelebration || UITestFixture.startsWithPerfectMoveOnCelebration {
                workout.requestMoveOnCelebration()
            }
            if UITestFixture.startsInBlockOverview {
                workout.requestBlockOverviewPresentation()
            }
        }

        private static func makeUITestSettings(defaults: UserDefaults) -> SettingsStore {
            let settings = SettingsStore(defaults: defaults)
            if let appearanceOverride = UITestFixture.appearanceOverride {
                settings.setAppearance(appearanceOverride)
            }
            settings.isSignedIn = true
            // Onboarding mode leaves the spreadsheet unset so the app lands on the sheet picker,
            // while the seeded (stale) Block stays in the store to prove it is never shown for the
            // newly selected sheet.
            if !UITestFixture.startsInOnboarding {
                settings.setSpreadsheet(id: WorkoutFixtureScenarios.sheetId, title: "Fixture Training Log")
            }
            return settings
        }

        private static func applyCurrentSessionOverrideFixture(to workout: WorkoutStore) {
            guard UITestFixture.startsWithCurrentSessionOverride else { return }
            workout.show(week: 1, day: 3)
            workout.makeDisplayedSessionCurrent()
        }
    #endif

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(settings)
                .environment(workout)
                .environment(sync)
                .environment(lastPerformedLookup)
                .onOpenURL { GIDSignIn.sharedInstance.handle($0) }
                .task {
                    #if DEBUG
                        if UITestFixture.isEnabled { return }
                    #endif
                    settings.isSignedIn = await GoogleAuth.restorePreviousSignIn()
                }
        }
        .modelContainer(container)
    }
}
