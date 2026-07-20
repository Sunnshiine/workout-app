import SnapshotTesting
import SwiftUI
import Testing

@testable import WorkoutTracker

@MainActor
@Suite(.snapshots(record: .all))
struct SessionViewVisualTests {
    /// The living stage in both appearances — the Greenhouse room by Day and the same room re-lit at
    /// Night (DESIGN.md §5.1). Captured wholesale via the `-WORKOUT_THEME`-equivalent appearance pin.
    @Test func seededSessionViewMatchesVisualBaseline() throws {
        let scenario = try WorkoutScenarios.freshConfiguredApp()
        VisualBaselineFixtureRetainer.retain(scenario)
        let sync = SyncCoordinator(client: VisualBaselineNoopSheetsClient(), context: scenario.context)
        let lastPerformedLookup = LastPerformedLookupStore(context: scenario.context)

        assertGreenhouseBaselines(hosted: false) { _ in
            NavigationStack {
                SessionView()
            }
            .environment(scenario.store)
            .environment(sync)
            .environment(scenario.settings)
            .environment(lastPerformedLookup)
        }
    }
}
