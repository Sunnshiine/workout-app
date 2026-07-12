import Foundation
import SnapshotTesting
import SwiftUI
import Testing

@testable import WorkoutTracker

@MainActor
@Suite(.snapshots(record: .never))
struct ExerciseHistorySheetVisualTests {
    /// A representative Movement history covering every content state the sheet renders: structured
    /// Sets with muted RPE, an inline partial-skip marker, a Legacy Log *as entered*, and a
    /// spelling-variant entry annotated *as "…"* — all quiet, no mint (revised `DESIGN.md`).
    private func historyEntry(
        fullName: String,
        baseName: String,
        resultText: String,
        source: String,
        daysAgo: Int
    ) -> ExerciseHistoryEntry {
        ExerciseHistoryEntry(
            fullName: fullName,
            baseName: baseName,
            resultText: resultText,
            source: source,
            performedOn: Date(timeIntervalSinceReferenceDate: 1_000_000) - Double(daysAgo) * 86_400
        )
    }

    @Test func exerciseHistorySheetMatchesVisualBaseline() {
        let presentation = ExerciseHistorySheetPresentation(
            anchorBaseName: "Bench Press",
            entries: [
                historyEntry(fullName: "Bench Press", baseName: "Bench Press",
                             resultText: "27.5x10@8, 27.5x10@8, 27.5x9@9",
                             source: "Block 27 · W2 D1", daysAgo: 1),
                historyEntry(fullName: "2-0:1:0 Bench Press", baseName: "Bench Press",
                             resultText: "185x5@8, skip, 185x4@9",
                             source: "Block 27 · W1 D1", daysAgo: 8),
                historyEntry(fullName: "Benh Press", baseName: "Benh Press",
                             resultText: "180x5@8",
                             source: "Block 26 · W2 D1", daysAgo: 30),
                historyEntry(fullName: "Bench Press", baseName: "Bench Press",
                             resultText: "worked up to 315, felt smooth",
                             source: "Block 26 · W1 D1", daysAgo: 37),
            ]
        )

        let view = ExerciseHistorySheet(presentation: presentation)
            .frame(width: 393, height: 420)
            .background(Theme.palette(for: .sageLight).gradient)
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
                             source: "Block 27 · W1 D1", daysAgo: 8),
            ]
        )

        let view = ExerciseHistorySheet(
            presentation: presentation,
            fillProgress: HistoryFillProgressPresentation(
                LastPerformedBackfillProgress(tab: "Block 26", tabsCompleted: 1, tabsToScan: 3)
            )
        )
        .frame(width: 393, height: 420)
        .background(Theme.palette(for: .sageLight).gradient)
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
