import SnapshotTesting
import SwiftUI
import Testing

@testable import WorkoutTracker

@MainActor
@Suite(.snapshots(record: .never))
struct SupersetStageVisualTests {
    @Test func supersetStageMatchesVisualBaseline() throws {
        try assertSupersetSnapshot(focus: .press, appearance: .day, colorScheme: .light)
    }

    @Test func supersetStageMatchesNightVisualBaseline() throws {
        try assertSupersetSnapshot(focus: .press, appearance: .night, colorScheme: .dark)
    }

    @Test func supersetStageFocusedOnTheLateralMatchesVisualBaseline() throws {
        try assertSupersetSnapshot(focus: .row, appearance: .day, colorScheme: .light)
    }

    @Test func supersetStageFocusedOnTheLateralMatchesNightVisualBaseline() throws {
        try assertSupersetSnapshot(focus: .row, appearance: .night, colorScheme: .dark)
    }

    private enum Focus {
        case press
        case row
    }

    private func assertSupersetSnapshot(
        focus: Focus,
        appearance: Theme.Appearance,
        colorScheme: ColorScheme,
        fileID: StaticString = #fileID,
        file: StaticString = #filePath,
        testName: String = #function,
        line: UInt = #line,
        column: UInt = #column
    ) throws {
        let (stage, session) = try makeSupersetStage(focus: focus)
        let scenario = try WorkoutScenarios.freshConfiguredApp()
        VisualFixtureRetainer.retain(scenario)

        let view = ZStack {
            Theme.palette(for: appearance).paperBackground
                .ignoresSafeArea()

            VStack(spacing: 0) {
                ActiveSupersetSection(
                    stage: stage,
                    session: session,
                    coordinator: SessionCoordinator(session: session, wiring: .fixture()),
                    composition: .reading,
                    onShowHistory: { _ in }
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

    private func makeSupersetStage(focus: Focus) throws -> (SupersetStage, Session) {
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

        let lastPerformed = LastPerformedOccurrence(
            fullName: "Incline Bench Press",
            baseName: "Incline Bench Press",
            resultText: "30×10 @8 · 30×10 @8 · 30×9 @9",
            performedOn: .distantPast,
            source: "W1 D2"
        )
        let stage = SessionStage(
            session: session,
            focus: SessionFocusSnapshot(
                visualFocusOwner: .activeSet(
                    ActiveSetID(exerciseOrder: focus == .press ? press.order : row.order, setIndex: 1)
                ),
                supersets: [Superset(first: press, second: row)],
                pairableExerciseOrders: []
            ),
            savedLoggedSetID: nil,
            pairingMode: .inactive,
            liveEdge: .browsedAway,
            lookup: LastPerformedLookupSnapshot(occurrences: [lastPerformed])
        )
        let superset: SupersetStage? = if case .superset(let superset) = stage.focus { superset } else { nil }
        return (try #require(superset), session)
    }
}
