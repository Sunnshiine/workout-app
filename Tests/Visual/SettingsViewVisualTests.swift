import Foundation
import SnapshotTesting
import SwiftUI
import Testing

@testable import WorkoutTracker

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
        VisualFixtureRetainer.retain(scenario)
        let sync = SyncCoordinator(client: VisualNoopSheetsClient(), context: scenario.context)

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
