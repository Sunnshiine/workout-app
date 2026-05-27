import Testing

@testable import WorkoutTracker

@MainActor
@Test func syncStatusPresentationBuildsVisibleSyncQueueAndFailureStates() throws {
    let syncing = try #require(SyncStatusBannerPresentation(state: .syncing))
    let queued = try #require(SyncStatusBannerPresentation(state: .pendingWrites(3)))
    let offline = try #require(SyncStatusBannerPresentation(state: .offline))
    let failure = try #require(SyncStatusBannerPresentation(state: .conflict(["Sheet write failed"])))

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
                text: "3 unsynced",
                symbol: "icloud.slash",
                accessibilityLabel: "Sync status: 3 unsynced"
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
