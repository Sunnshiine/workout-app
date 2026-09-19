import Testing

@testable import WorkoutTracker

@MainActor
@Test func syncStatusPresentationBuildsVisibleSyncQueueAndFailureStates() throws {
    let syncing = try #require(SyncStatusBannerPresentation(outcome: .clear, isSyncing: true))
    let queuedWrite = WorkoutScenarios.queuedWrite()
    let queued = try #require(
        SyncStatusBannerPresentation(outcome: .writesQueued([queuedWrite].count), isSyncing: false)
    )
    let offline = try #require(SyncStatusBannerPresentation(outcome: .sheetUnreachable, isSyncing: false))
    let failure = try #require(SyncStatusBannerPresentation(outcome: WorkoutScenarios.syncFailure(), isSyncing: false))

    #expect(syncing == SyncStatusBannerPresentation(text: "Syncing"))
    #expect(queued == SyncStatusBannerPresentation(text: "1 unsynced"))
    #expect(offline == SyncStatusBannerPresentation(text: "Offline"))
    #expect(
        failure
            == SyncStatusBannerPresentation(
                text: "The sheet changed, so your log was not written",
                detail: "Sheet write failed"
            )
    )
}

@MainActor
@Test func syncStatusPresentationHidesAClearSyncAndSpeaksOverAnyOutcomeWhileASyncRuns() throws {
    #expect(SyncStatusBannerPresentation(outcome: .clear, isSyncing: false) == nil)

    // A verdict the running step is about to replace is not worth a sentence, so the banner says
    // the one thing that is still true.
    let midSync = try #require(
        SyncStatusBannerPresentation(outcome: .writesRefused(["Squat: Expected '', found 'coach edited'"]), isSyncing: true)
    )
    #expect(midSync == SyncStatusBannerPresentation(text: "Syncing"))
}

/// The point of #589: the five results that used to arrive as `.conflict([String])` say five
/// different things, because each asks something different of the athlete. Two of them lost a Set
/// Log, one is a spreadsheet nobody set up, and two are a sync that worked with a footnote.
@MainActor
@Test func theFiveOutcomesThatUsedToReadAlikeNowReadDifferently() throws {
    let banners = try [
        SyncOutcome.localWriteFailed("the local store is full"),
        .writesRefused(["Squat: Expected '', found 'coach edited'"]),
        .noBlockTab,
        .parseWarnings(["Parse warning: no week sections (no 'Day N' headers) in Block 27"]),
        .historyFillFailed("the index is full")
    ].map { try #require(SyncStatusBannerPresentation(outcome: $0, isSyncing: false)) }

    #expect(
        banners.map(\.text) == [
            "Your log did not save on this phone",
            "The sheet changed, so your log was not written",
            "This sheet has no block tab",
            "Synced, with a note about the sheet",
            "Synced. Exercise History did not finish"
        ]
    )
    #expect(Set(banners.map(\.text)).count == banners.count)
    #expect(
        banners.map(\.detail) == [
            "the local store is full",
            "Squat: Expected '', found 'coach edited'",
            nil,
            "Parse warning: no week sections (no 'Day N' headers) in Block 27",
            "the index is full"
        ]
    )
}

/// VoiceOver reads the banner as one element, so the outcome and its message have to be in the
/// label or the athlete hears "Sync status" and nothing that tells the five apart.
@MainActor
@Test func theAccessibilityLabelCarriesBothTheOutcomeAndItsMessage() throws {
    let refused = try #require(
        SyncStatusBannerPresentation(outcome: .writesRefused(["Squat: Expected '', found 'coach edited'"]), isSyncing: false)
    )
    #expect(
        refused.accessibilityLabel
            == "Sync status: The sheet changed, so your log was not written. Squat: Expected '', found 'coach edited'"
    )

    let offline = try #require(SyncStatusBannerPresentation(outcome: .sheetUnreachable, isSyncing: false))
    #expect(offline.accessibilityLabel == "Sync status: Offline")

    // The string `.claude/skills/verify/features/log-a-set.md` greps for on the live app.
    let queued = try #require(SyncStatusBannerPresentation(outcome: .writesQueued(1), isSyncing: false))
    #expect(queued.accessibilityLabel == "Sync status: 1 unsynced")
}

/// Only the first message reaches the banner. The rest are in the CLI's `messages` array and on
/// each `PendingWrite` record; the banner is one line and picks the first.
@MainActor
@Test func aBannerShowsTheFirstOfSeveralRefusedWrites() throws {
    let many = try #require(
        SyncStatusBannerPresentation(outcome: .writesRefused(["First", "Second"]), isSyncing: false)
    )
    #expect(many.detail == "First")
}
