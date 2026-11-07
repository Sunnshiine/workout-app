import SnapshotTesting
import SwiftUI
import Testing

@testable import WorkoutTracker

@MainActor
@Suite(.snapshots(record: .never))
struct WarmupRampSheetVisualTests {
    @Test func aWalkedRampMatchesVisualBaseline() {
        assertSheet(appearance: .day, colorScheme: .light, name: "Back Squat", top: 237.5, stepsWalked: 2)
    }

    @Test func aWalkedRampMatchesNightVisualBaseline() {
        assertSheet(appearance: .night, colorScheme: .dark, name: "Back Squat", top: 237.5, stepsWalked: 2)
    }

    @Test func theHeaviestLoadMatchesVisualBaseline() {
        assertSheet(appearance: .day, colorScheme: .light, name: "Back Squat", top: 1005, stepsWalked: 5)
    }

    @Test func aTopTheInventoryCannotBuildMatchesVisualBaseline() {
        assertSheet(appearance: .day, colorScheme: .light, name: "Back Squat", top: 47.5, stepsWalked: 0)
    }

    @Test func aRampWithNoTopYetMatchesVisualBaseline() {
        assertSheet(appearance: .day, colorScheme: .light, name: "Back Squat", top: nil, stepsWalked: 0)
    }

    @Test func aRampWithNoTopYetMatchesNightVisualBaseline() {
        assertSheet(appearance: .night, colorScheme: .dark, name: "Back Squat", top: nil, stepsWalked: 0)
    }

    @Test func aLongExerciseNameMatchesVisualBaseline() {
        let name = "Paused Low-Bar Competition Back Squat w/ Safety Squat Bar"
        assertSheet(appearance: .day, colorScheme: .light, name: name, top: 275, stepsWalked: 0)
    }

    @Test func theBarAndPlatesPageMatchesVisualBaseline() {
        assertPlatePage(appearance: .day, colorScheme: .light, config: .workoutVisualBaseline)
    }

    @Test func theBarAndPlatesPageMatchesNightVisualBaseline() {
        assertPlatePage(appearance: .night, colorScheme: .dark, config: .workoutVisualBaselineNight)
    }

    private func assertSheet(
        appearance: Theme.Appearance,
        colorScheme: ColorScheme,
        name: String,
        top: Double?,
        stepsWalked: Int,
        testName: String = #function
    ) {
        let settings = SettingsStore(defaults: .inMemory())
        let session = Session(dayNumber: 1, date: nil)
        let coordinator = SessionCoordinator(session: session, wiring: .fixture())
        let entry = WarmupEntry(exerciseOrder: 0, exerciseTitle: name, setNumber: 1, prefill: top)
        if stepsWalked > 0 {
            let steps = WarmupRampPresentation(entry: entry, inventory: settings.plateInventory, walk: coordinator.warmupWalk).steps
            coordinator.warmupWalk.tap(rowAt: stepsWalked - 1, of: steps, forExerciseOrder: entry.exerciseOrder)
        }
        // `.presentationBackground` is a no-op offscreen, so the host paints the living paper behind
        // the sheet content as the large detent would.
        let view = WarmupRampSheet(entry: entry, coordinator: coordinator)
            .frame(width: 393, height: 780)
            .background(Theme.palette(for: appearance).paperBackground)
            .environment(settings)
            .environment(\.themePalette, Theme.palette(for: appearance))
            .environment(\.locale, Locale(identifier: WorkoutVisualBaseline.localeIdentifier))
            .environment(\.dynamicTypeSize, WorkoutVisualBaseline.dynamicTypeSize)
            .preferredColorScheme(colorScheme)

        assertSnapshot(
            of: view,
            as: .image(
                precision: WorkoutVisualBaseline.labelAntialiasingPrecision,
                layout: .device(config: .workoutVisualBaseline)
            ),
            testName: testName
        )
    }

    private func assertPlatePage(
        appearance: Theme.Appearance,
        colorScheme: ColorScheme,
        config: ViewImageConfig,
        testName: String = #function
    ) {
        let view = NavigationStack { PlateInventoryView() }
            .environment(SettingsStore(defaults: .inMemory()))
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
