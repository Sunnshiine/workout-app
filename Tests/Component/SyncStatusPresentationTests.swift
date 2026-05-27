import Testing

@testable import WorkoutTracker

@MainActor
@Test func syncStatusPresentationBuildsVisibleSyncQueueAndFailureStates() throws {
    let syncing = try #require(SyncStatusBannerPresentation(state: .syncing))
    let queuedWrite = WorkoutScenarios.queuedWrite()
    let queued = try #require(SyncStatusBannerPresentation(state: .pendingWrites([queuedWrite].count)))
    let offline = try #require(SyncStatusBannerPresentation(state: .offline))
    let failure = try #require(SyncStatusBannerPresentation(state: WorkoutScenarios.syncFailure()))

    #expect(
        syncing
            == SyncStatusBannerPresentation(
                text: "Syncing",
                symbol: "arrow.triangle.2.circlepath",
                accessibilityLabel: "Sync status: Syncing"
            )
    )
    #expect(
        queued
            == SyncStatusBannerPresentation(
                text: "1 unsynced",
                symbol: "icloud.slash",
                accessibilityLabel: "Sync status: 1 unsynced"
            )
    )
    #expect(
        offline
            == SyncStatusBannerPresentation(
                text: "Offline",
                symbol: "wifi.slash",
                accessibilityLabel: "Sync status: Offline"
            )
    )
    #expect(
        failure
            == SyncStatusBannerPresentation(
                text: "Sheet write failed",
                symbol: "exclamationmark.triangle",
                accessibilityLabel: "Sync status: Sheet write failed"
            )
    )
}
