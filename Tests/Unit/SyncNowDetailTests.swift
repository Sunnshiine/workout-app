import Testing

@testable import WorkoutTracker

@Test(arguments: [
    (SyncOutcome.clear, false, true, "Refresh workout state"),
    (.clear, false, false, "Connect a sheet first"),
    (.clear, true, true, "Syncing..."),
    (.writesQueued(2), true, true, "Syncing..."),
    (.sheetUnreachable, false, true, "Offline"),
    (.writesQueued(1), false, true, "1 unsynced log"),
    (.writesQueued(3), false, true, "3 unsynced logs"),
    (.localWriteFailed("disk"), false, true, "Log not saved"),
    (.writesRefused(["moved"]), false, true, "Log not written"),
    (.noBlockTab, false, true, "No block tab"),
    (.parseWarnings(["note"]), false, true, "Synced with a note"),
    (.historyFillFailed("x"), false, true, "History incomplete"),
])
func syncNowDetailNamesEveryOutcome(outcome: SyncOutcome, isSyncing: Bool, hasSheet: Bool, expected: String) {
    #expect(SyncNowDetail.text(outcome: outcome, isSyncing: isSyncing, hasSheet: hasSheet) == expected)
}
