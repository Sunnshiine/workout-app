import SnapshotTesting
import SwiftUI
import Testing

@testable import WorkoutTracker

/// The living-paper atmosphere against picks atmosphere2-i (Day) and atmosphere2-k (Night),
/// DESIGN.md §2. The wash — a layered sage base pair under four radial light washes, hand-lit per
/// appearance — is the room every Greenhouse surface sits in; it is exercised transitively behind
/// every other fixture. This suite gives the pick its **own** fixture and Day/Night baseline pair so
/// the coverage audit (PRD #497 slice 9) is literally complete rather than transitive: the full-bleed
/// `paperBackground` with no chrome on top, so a wash regression fails here directly.
@MainActor
@Suite(.snapshots(record: .never))
struct AtmosphereVisualTests {
    @Test func livingPaperMatchesVisualBaseline() {
        assertAtmosphereSnapshot(appearance: .day, colorScheme: .light)
    }

    @Test func livingPaperMatchesNightVisualBaseline() {
        assertAtmosphereSnapshot(appearance: .night, colorScheme: .dark)
    }

    private func assertAtmosphereSnapshot(
        appearance: Theme.Appearance,
        colorScheme: ColorScheme,
        fileID: StaticString = #fileID,
        file: StaticString = #filePath,
        testName: String = #function,
        line: UInt = #line,
        column: UInt = #column
    ) {
        let view = Theme.palette(for: appearance).paperBackground
            .ignoresSafeArea()
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
