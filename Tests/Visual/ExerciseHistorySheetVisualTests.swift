import Foundation
import SnapshotTesting
import SwiftUI
import Testing

@testable import WorkoutTracker

@MainActor
@Suite(.snapshots(record: .never))
struct ExerciseHistorySheetVisualTests {
    private func historyEntry(
        fullName: String,
        baseName: String,
        resultText: String,
        source: String,
        daysAgo: Int
    ) -> LastPerformedOccurrence {
        LastPerformedOccurrence(
            fullName: fullName,
            baseName: baseName,
            resultText: resultText,
            performedOn: Date(timeIntervalSinceReferenceDate: 1_000_000) - Double(daysAgo) * 86_400,
            source: source
        )
    }

    private var historyPresentation: ExerciseHistorySheetPresentation {
        ExerciseHistorySheetPresentation(
            anchorBaseName: "Bench Press",
            entries: [
                historyEntry(fullName: "Bench Press", baseName: "Bench Press",
                             resultText: "27.5x10@8, 27.5x10@8, 27.5x9@9",
                             source: "Block 27 · W2 D1", daysAgo: 1),
                historyEntry(fullName: "2-0:1:0 Bench Press", baseName: "Bench Press",
                             resultText: "185x5@8, skip, 185x4@9, felt heavy",
                             source: "Block 27 · W1 D1", daysAgo: 8),
                historyEntry(fullName: "Benh Press", baseName: "Benh Press",
                             resultText: "180x5@8",
                             source: "Block 26 · W2 D1", daysAgo: 30),
                historyEntry(fullName: "Bench Press", baseName: "Bench Press",
                             resultText: "worked up to 315, felt smooth",
                             source: "Block 26 · W1 D1", daysAgo: 37)
            ]
        )
    }

    @Test func exerciseHistorySheetMatchesVisualBaseline() {
        assertSheet(appearance: .day, colorScheme: .light) {
            ExerciseHistorySheet(presentation: historyPresentation)
        }
    }

    @Test func exerciseHistorySheetMatchesNightVisualBaseline() {
        assertSheet(appearance: .night, colorScheme: .dark) {
            ExerciseHistorySheet(presentation: historyPresentation)
        }
    }

    @Test func exerciseHistoryVolumeChartMatchesVisualBaseline() {
        assertSheet(appearance: .day, colorScheme: .light, height: 560) {
            ExerciseHistorySheet(presentation: historyPresentation, showVolume: true)
        }
    }

    @Test func exerciseHistoryVolumeChartMatchesNightVisualBaseline() {
        assertSheet(appearance: .night, colorScheme: .dark, height: 560) {
            ExerciseHistorySheet(presentation: historyPresentation, showVolume: true)
        }
    }

    /// The Night raised Volume control's 1pt inset rim moves too few pixels for the sheet baseline's
    /// label-antialiasing budget, so this crop of the header holds it at exact precision.
    @Test func exerciseHistoryRaisedVolumeControlMatchesNightVisualBaseline() {
        assertSheet(appearance: .night, colorScheme: .dark, height: 80, precision: WorkoutVisualBaseline.precision) {
            ExerciseHistorySheet(presentation: historyPresentation)
        }
    }

    /// The fill-in-progress affordance: a warm-voice line, a muted determinate bar, and an honest
    /// per-tab detail shown above readable entries — never mint, never a dead spinner (#366).
    @Test func exerciseHistorySheetFillInProgressMatchesVisualBaseline() {
        let presentation = ExerciseHistorySheetPresentation(
            anchorBaseName: "Bench Press",
            entries: [
                historyEntry(fullName: "Bench Press", baseName: "Bench Press",
                             resultText: "27.5x10@8, 27.5x10@8, 27.5x9@9",
                             source: "Block 27 · W2 D1", daysAgo: 1),
                historyEntry(fullName: "2-0:1:0 Bench Press", baseName: "Bench Press",
                             resultText: "185x5@8, skip, 185x4@9",
                             source: "Block 27 · W1 D1", daysAgo: 8)
            ]
        )

        assertSheet(appearance: .day, colorScheme: .light) {
            ExerciseHistorySheet(
                presentation: presentation,
                fillProgress: HistoryFillProgressPresentation(
                    ExerciseHistoryFill.Progress(tab: "Block 26", tabsCompleted: 1, tabsToScan: 3)
                )
            )
        }
    }

    private func assertSheet(
        appearance: Theme.Appearance,
        colorScheme: ColorScheme,
        height: CGFloat = 420,
        precision: Float = WorkoutVisualBaseline.labelAntialiasingPrecision,
        testName: String = #function,
        @ViewBuilder _ content: () -> some View
    ) {
        let view = content()
            .frame(width: 393, height: height)
            .background(Theme.palette(for: appearance).paperBackground)
            .environment(\.themePalette, Theme.palette(for: appearance))
            .environment(\.locale, Locale(identifier: WorkoutVisualBaseline.localeIdentifier))
            .environment(\.dynamicTypeSize, WorkoutVisualBaseline.dynamicTypeSize)
            .preferredColorScheme(colorScheme)

        assertSnapshot(
            of: view,
            as: .image(
                precision: precision,
                layout: .device(config: .workoutVisualBaseline)
            ),
            testName: testName
        )
    }
}
