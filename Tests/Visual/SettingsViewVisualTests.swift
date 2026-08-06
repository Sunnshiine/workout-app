import Foundation
import SnapshotTesting
import SwiftUI
import Testing

@testable import WorkoutTracker

/// Native Settings (DESIGN.md §5.9, ledger §10.4), in both appearances. Settings is built of
/// system-owned `Form` rows with native text styles and normal Dynamic Type — no glass card, no
/// hand-built role table. Appearance (System / Light / Night) and the `Sync now` row live here.
///
/// Settings leaves `GlassBearingViewsVisualTests` because it no longer bears glass; this suite is its
/// replacement coverage, and it adds the Night appearance the glass suite never rendered.
@MainActor
@Suite(.snapshots(record: .never))
struct SettingsViewVisualTests {
    @Test func settingsViewMatchesVisualBaseline() throws {
        try assertSettings(colorScheme: .light, config: .workoutVisualBaseline)
    }

    @Test func settingsViewMatchesNightVisualBaseline() throws {
        try assertSettings(colorScheme: .dark, config: .workoutVisualBaselineNight)
    }

    private func assertSettings(
        colorScheme: ColorScheme,
        config: ViewImageConfig,
        testName: String = #function
    ) throws {
        let scenario = try WorkoutScenarios.freshConfiguredApp()
        SettingsVisualFixtureRetainer.retain(scenario)
        let sync = SyncCoordinator(client: SettingsVisualNoopSheetsClient(), context: scenario.context)

        let view = SettingsView()
            .environment(scenario.settings)
            .environment(sync)
            .environment(scenario.store)
            .environment(\.locale, Locale(identifier: WorkoutVisualBaseline.localeIdentifier))
            .environment(\.dynamicTypeSize, WorkoutVisualBaseline.dynamicTypeSize)
            .preferredColorScheme(colorScheme)

        assertSnapshot(
            of: view,
            as: .image(
                precision: WorkoutVisualBaseline.precision,
                perceptualPrecision: 1,
                layout: .device(config: config)
            ),
            testName: testName
        )
    }
}

@MainActor
private enum SettingsVisualFixtureRetainer {
    private static var retainedScenarios: [ConfiguredAppScenario] = []

    static func retain(_ scenario: ConfiguredAppScenario) {
        retainedScenarios.append(scenario)
    }
}

private actor SettingsVisualNoopSheetsClient: SheetsClient {
    func listTabTitles(spreadsheetId: String) async throws -> [String] {
        []
    }

    func fetchTabSnapshot(spreadsheetId: String, tabName: String) async throws -> SheetSnapshot {
        SheetSnapshot(values: [], rowVisibility: [:])
    }

    func updateCells(spreadsheetId: String, range: String, values: [[String]]) async throws {}
}
