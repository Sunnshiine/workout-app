import SnapshotTesting
import SwiftUI
import Testing

@testable import WorkoutTracker

@MainActor
@Suite(.snapshots(record: .never))
struct SessionViewVisualTests {
    @Test func seededSessionViewMatchesVisualBaseline() throws {
        try assertStageSnapshot(appearance: .day, colorScheme: .light)
    }

    @Test func seededSessionViewMatchesNightVisualBaseline() throws {
        try assertStageSnapshot(appearance: .night, colorScheme: .dark)
    }

    private func assertStageSnapshot(
        appearance: Theme.Appearance,
        colorScheme: ColorScheme,
        fileID: StaticString = #fileID,
        file: StaticString = #filePath,
        testName: String = #function,
        line: UInt = #line,
        column: UInt = #column
    ) throws {
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
        .environment(\.themePalette, Theme.palette(for: appearance))
        .environment(\.locale, Locale(identifier: WorkoutVisualBaseline.localeIdentifier))
        .environment(\.dynamicTypeSize, WorkoutVisualBaseline.dynamicTypeSize)
        .preferredColorScheme(colorScheme)

        assertSnapshot(
            of: view,
            as: .image(
                precision: WorkoutVisualBaseline.precision,
                layout: .device(config: .workoutVisualBaseline)
            ),
            fileID: fileID,
            file: file,
            testName: testName,
            line: line,
            column: column
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
