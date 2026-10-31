import Foundation
import SwiftData
import Testing

@testable import WorkoutTracker

private struct OfflineSheetsClient: SheetsClient {
    func listTabTitles(spreadsheetId: String) async throws -> [String] {
        throw URLError(.notConnectedToInternet)
    }

    func fetchTabSnapshot(spreadsheetId: String, tabName: String) async throws -> SheetSnapshot {
        throw URLError(.notConnectedToInternet)
    }

    func write(_ cells: [SheetCellWrite], spreadsheetId: String) async throws {}
}

/// The app's assembly, built the way `RootView` builds it. `swift test` reaches it (ADR-0017)
/// only while nothing in it touches the notification center, which aborts a process with no app
/// bundle (#1006).
@MainActor
@Test func liveWiringSchedulesRestNotificationsThroughTheAppsScheduler() throws {
    let container = try ModelContainer(
        for: Block.self,
        configurations: ModelConfiguration(isStoredInMemoryOnly: true)
    )
    let context = container.mainContext
    let notifications = RecordingRestNotificationScheduler()
    let wiring = SessionWiring.live(
        workout: WorkoutStore(context: context, defaults: .inMemory()),
        sync: SyncCoordinator(client: OfflineSheetsClient(), context: context),
        settings: SettingsStore(defaults: .inMemory()),
        lastPerformed: LastPerformedLookupStore(context: context),
        entry: AppEntryInbox(),
        platform: SessionPlatform(
            liveActivity: InertSessionLiveActivity(),
            motion: ImmediateSessionMotion(),
            restTimer: RestTimer(notificationScheduler: notifications),
            countdown: EffortCountdown(clock: SystemRestClock(), scheduler: HeldRestExpiry(), cues: SilentCountdownCues())
        )
    )
    let coordinator = SessionCoordinator(wiring: wiring)

    coordinator.restTimer.start(duration: 90, origin: nil)
    defer { coordinator.restTimer.dismiss() }

    #expect(notifications.scheduledDeadlines.count == 1)
}
