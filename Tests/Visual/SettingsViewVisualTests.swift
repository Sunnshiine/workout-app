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
        try assertSettings(appearance: .day, colorScheme: .light, config: .workoutVisualBaseline)
    }

    @Test func settingsViewMatchesNightVisualBaseline() throws {
        try assertSettings(appearance: .night, colorScheme: .dark, config: .workoutVisualBaselineNight)
    }

    private func assertSettings(
        appearance: Theme.Appearance,
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
            .environment(SheetConnection(settings: scenario.settings, sync: sync) { scenario.store.reload() })
            .environment(scenario.store)
            .environment(\.themePalette, Theme.palette(for: appearance))
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
