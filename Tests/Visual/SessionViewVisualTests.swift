import SnapshotTesting
import SwiftUI
import Testing

@testable import WorkoutTracker

@MainActor
@Suite(.snapshots(record: .never))
struct SessionViewVisualTests {
    @Test func seededSessionViewMatchesVisualBaseline() throws {
        let scenario = try WorkoutScenarios.freshConfiguredApp()
        VisualFixtureRetainer.retain(scenario)
        let sync = SyncCoordinator(client: VisualNoopSheetsClient(), context: scenario.context)
        let lastPerformedLookup = LastPerformedLookupStore(context: scenario.context)

        let view = NavigationStack {
            SessionView()
        }
        .environment(scenario.store)
        .environment(sync)
        .environment(scenario.settings)
        .environment(lastPerformedLookup)
        .environment(\.themePalette, Theme.palette(for: .sageLight))
        .environment(\.locale, Locale(identifier: WorkoutVisualBaseline.localeIdentifier))
        .environment(\.dynamicTypeSize, WorkoutVisualBaseline.dynamicTypeSize)
        .preferredColorScheme(.light)

        assertSnapshot(
            of: view,
            as: .image(
                precision: WorkoutVisualBaseline.precision,
                layout: .device(config: .workoutVisualBaseline)
            )
        )
    }
}

@MainActor
private enum VisualFixtureRetainer {
    private static var retainedScenarios: [ConfiguredAppScenario] = []

    static func retain(_ scenario: ConfiguredAppScenario) {
        retainedScenarios.append(scenario)
    }
}

private actor VisualNoopSheetsClient: SheetsClient {
    func listTabTitles(spreadsheetId: String) async throws -> [String] {
        []
    }

    func fetchTabSnapshot(spreadsheetId: String, tabName: String) async throws -> SheetSnapshot {
        SheetSnapshot(values: [], rowVisibility: [:])
    }

    func updateCells(spreadsheetId: String, range: String, values: [[String]]) async throws {}
}
