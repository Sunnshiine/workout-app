import Foundation
import SnapshotTesting
import SwiftUI
import Testing

@testable import WorkoutTracker

@MainActor
@Suite(.snapshots(record: .never))
struct ExerciseHistorySheetVisualTests {
    /// A representative Movement history covering every content state the chip ledger renders
    /// (`DESIGN.md` §5.6): structured Sets as carved chips with muted RPE, a partial-skip entry whose
    /// skip hides behind the `*` well, a Legacy Log best-effort parsed with its rawness in the well,
    /// and a spelling-variant entry annotated in the well — all quiet reference material.
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
            .background(Theme.palette(for: .day).paperBackground)
            .environment(\.themePalette, Theme.palette(for: .day))
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
        .background(Theme.palette(for: .day).paperBackground)
        .environment(\.themePalette, Theme.palette(for: .day))
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
