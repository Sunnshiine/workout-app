import GoogleSignIn
import SwiftData
import SwiftUI

@main
struct WorkoutTrackerApp: App {
    let container: ModelContainer
    @State private var settings: SettingsStore
    @State private var workout: WorkoutStore
    @State private var sync: SyncCoordinator

    init() {
        #if DEBUG
            if UITestFixture.isEnabled {
                let container = UITestFixture.makeContainer()
                self.container = container
                let ctx = container.mainContext
                let settings = SettingsStore()
                settings.isSignedIn = true
                settings.setSheetURL(UITestFixture.sheetURL)
                let workout = WorkoutStore(context: ctx)
                workout.reload()
                _settings = State(initialValue: settings)
                _workout = State(initialValue: workout)
                _sync = State(initialValue: SyncCoordinator(client: GoogleSheetsClient(), context: ctx))
                return
            }
        #endif
        // swiftlint:disable:next force_try
        let container = try! ModelContainer(for: Block.self, PendingWrite.self)
        self.container = container
        let ctx = container.mainContext
        _settings = State(initialValue: SettingsStore())
        _workout = State(initialValue: WorkoutStore(context: ctx))
        _sync = State(initialValue: SyncCoordinator(client: GoogleSheetsClient(), context: ctx))
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(settings)
                .environment(workout)
                .environment(sync)
                .onOpenURL { GIDSignIn.sharedInstance.handle($0) }
                .task {
                    settings.isSignedIn = await GoogleAuth.restorePreviousSignIn()
                }
        }
        .modelContainer(container)
    }
}
