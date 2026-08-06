import Foundation
import SnapshotTesting
import SwiftUI
import Testing

@testable import WorkoutTracker

/// The Exercise History sheet — the chip ledger (DESIGN.md §5.6, picks exercise-history6-a/-b), in
/// both appearances. Every Set is a carved chip that reads *below* the sheet — a dark top inner
/// shadow with a light bottom edge, not a soft-raised highlight (ledger §7.1) — under quiet
/// sentence-case Block headers (§7.4). The athlete-summoned volume chart draws its ink line with
/// paper-cored data dots, a hollow `≈` dot where a Legacy Log makes the total best-effort, and a
/// dotted Block seam (§7.3); the Volume control raises on the cream recipe at rest (§7.2).
///
/// The sheet is one of the two surfaces never re-prototyped at Night; the map required its Night
/// appearance validated on the pinned iPhone 17 Pro simulator against the Room Re-lights Rule before
/// its baseline locks (carried slice-8 debt, PRD #497 §11, DESIGN.md §2 / §5.6). The Night baselines
/// below are that validation's pixel record; `Tests/Component/ThemeTests.swift`
/// (`nightExerciseHistorySheetObeysTheRoomRelightsRule`) is its programmatic half.
///
/// Closes the fixture gap (§11): before this the suite rendered the ledger only — the volume-chart-on
/// state (pick exercise-history6-b) had no fixture.
@MainActor
@Suite(.snapshots(record: .never))
struct ExerciseHistorySheetVisualTests {
    /// A representative Movement history covering every content state the chip ledger renders
    /// (`DESIGN.md` §5.6): structured Sets as carved chips with muted RPE; a mixed entry whose skip
    /// and Legacy rawness hide behind the `*` well while its total plots as a hollow `≈` dot; a
    /// spelling-variant entry annotated in the well; and a fully-unparseable Legacy Log that carries
    /// only its `*` well — never chipless (addendum §7.5). Two Blocks give the chart its dotted seam.
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
                             source: "Block 26 · W1 D1", daysAgo: 37),
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

    /// The volume chart summoned on (pick exercise-history6-b): the ink line over paper-cored dots, a
    /// hollow `≈` dot for the best-effort total, and the dotted Block seam — closing the §11 gap.
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

        assertSheet(appearance: .day, colorScheme: .light) {
            ExerciseHistorySheet(
                presentation: presentation,
                fillProgress: HistoryFillProgressPresentation(
                    LastPerformedBackfillProgress(tab: "Block 26", tabsCompleted: 1, tabsToScan: 3)
                )
            )
        }
    }

    private func assertSheet(
        appearance: Theme.Appearance,
        colorScheme: ColorScheme,
        height: CGFloat = 420,
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
                precision: WorkoutVisualBaseline.labelAntialiasingPrecision,
                layout: .device(config: .workoutVisualBaseline)
            ),
            testName: testName
        )
    }
}
