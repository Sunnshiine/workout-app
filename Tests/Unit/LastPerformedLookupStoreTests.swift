import Foundation
import SwiftData
import Testing

@testable import WorkoutTracker

@MainActor
@Test func lookupStorePublishesAndClearsFillProgress() throws {
    let container = try ModelContainer(
        for: LastPerformedEntry.self,
        configurations: ModelConfiguration(
            "lookup-store-fill-\(UUID().uuidString)",
            isStoredInMemoryOnly: true
        )
    )
    let store = LastPerformedLookupStore(context: container.mainContext)

    // No affordance before the fill publishes anything.
    #expect(store.fillProgress == nil)

    let progress = LastPerformedBackfillProgress(tab: "Block 25", tabsCompleted: 1, tabsToScan: 3)
    store.lastPerformedBackfillDidProgress(progress)
    #expect(store.fillProgress == progress)

    // The affordance disappears once the fill reaches coverage or exhausts the tabs.
    store.lastPerformedBackfillDidFinish()
    #expect(store.fillProgress == nil)
}
