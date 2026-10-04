import SnapshotTesting
import SwiftUI
import Testing

@testable import WorkoutTracker

/// The Superset stage against picks superset-stage4-a/-b (DESIGN.md §5.4), in both appearances:
/// the same editorial column as a single Exercise, but the Fraunces name gains a subordinate
/// "& partner" line (foliage green by Day, translucent foliage at Night — the manual focus switch)
/// and the branch becomes **one forked stem** — the focused Exercise climbs at full stroke and
/// alone carries the bud, while the partner grows along a shorter, bud-less drooping lateral.
@MainActor
@Suite(.snapshots(record: .never))
struct SupersetStageVisualTests {
    @Test func supersetStageMatchesVisualBaseline() throws {
        try assertSupersetSnapshot(appearance: .day, colorScheme: .light)
    }

    @Test func supersetStageMatchesNightVisualBaseline() throws {
        try assertSupersetSnapshot(appearance: .night, colorScheme: .dark)
    }

    private func assertSupersetSnapshot(
        appearance: Theme.Appearance,
        colorScheme: ColorScheme,
        fileID: StaticString = #fileID,
        file: StaticString = #filePath,
        testName: String = #function,
        line: UInt = #line,
        column: UInt = #column
    ) throws {
        let config = try makeSupersetConfig()
        let scenario = try WorkoutScenarios.freshConfiguredApp()
        VisualFixtureRetainer.retain(scenario)

        let view = ZStack {
            Theme.palette(for: appearance).paperBackground
                .ignoresSafeArea()

            VStack(spacing: 0) {
                ActiveSupersetSection(
                    config: config,
                    composition: .reading,
                    onFocusExercise: { _ in },
                    onShowHistory: { _ in },
                    onLog: { _, _ in },
                    onSkip: { _ in },
                    onDelete: { _ in },
                    onDismiss: {}
                )
                .padding(.horizontal)
                .padding(.top, Theme.sectionSpacing)

                Spacer(minLength: 0)
            }
        }
        .environment(LastPerformedLookupStore(context: scenario.context))
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
            fileID: fileID,
            file: file,
            testName: testName,
            line: line,
            column: column
        )
    }

    /// Reproduces the pick: DB Incline Press (Set 2 of 4, first Set logged 30×10 @8) forked with a
    /// resting Chest-Supported Row, the focus on the press.
    private func makeSupersetConfig() throws -> SessionSupersetRenderConfig {
        // The press is named "bench" and prescribed 20% so %1RM, which outranks the RPE target's
        // estimate, fills 30 from the Block's bench Training Max (150 × 20%) with no Load Basis
        // line, as the pick shows.
        let press = Exercise(
            name: "Incline Bench Press",
            baseName: "Incline Bench Press",
            cadence: nil,
            coachNote: "Keep the dumbbells honest at the bottom — full stretch, no rush.",
            order: 3
        )
        press.sets = (0..<4).map { index in
            let set = ExerciseSet(
                index: index,
                prescribedReps: "10",
                prescribedLoad: "RPE 8",
                percentOneRM: "20%",
                state: index == 0 ? .logged : .pending
            )
            if index == 0 {
                set.setLog = SetLog(weight: .pounds(30), reps: 10, rpe: .eight)
            }
            return set
        }

        let row = Exercise(
            name: "Chest-Supported Row",
            baseName: "Chest-Supported Row",
            cadence: nil,
            coachNote: nil,
            order: 4
        )
        row.sets = (0..<3).map { index in
            ExerciseSet(
                index: index,
                prescribedReps: "12",
                prescribedLoad: "RPE 8",
                percentOneRM: nil,
                state: index == 0 ? .logged : .pending
            )
        }
        row.sets[0].setLog = SetLog(weight: .pounds(50), reps: 12, rpe: .eight)

        let session = Session(dayNumber: 2, date: nil)
        session.exercises = [press, row]
        let week = Week(number: 2)
        week.sessions = [session]
        let block = Block(tabName: "Block 27", trainingMaxes: [.bench: 150])
        block.weeks = [week]

        let activeSetID = ActiveSetID(exerciseOrder: press.order, setIndex: 1)
        let presentation = try #require(
            ActiveSupersetPresentation(exercises: [press, row], activeSetID: activeSetID)
        )

        let lastPerformed = LastPerformedEntry(
            fullName: "Incline Bench Press",
            baseName: "Incline Bench Press",
            resultText: "30×10 @8 · 30×10 @8 · 30×9 @9",
            performedOn: .distantPast,
            source: "W1 D2"
        )

        return SessionSupersetRenderConfig(
            presentation: presentation,
            exercises: [press, row],
            visualFocusOwner: nil,
            activeSetTransition: nil,
            retiringTransition: nil,
            lastPerformedPresentation: LastPerformedCardPresentation(entry: lastPerformed)
        )
    }
}
