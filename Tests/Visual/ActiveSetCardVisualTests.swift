import SnapshotTesting
import SwiftUI
import Testing

@testable import WorkoutTracker

/// The Active Set Card & input block against pick input-block3-c (DESIGN.md §5.2), in both
/// appearances: the one soft container, weight leading as the biggest number flanked by round
/// steppers, Reps and RPE on side-by-side one-tap rails, and the true Log capsule.
@MainActor
@Suite(.snapshots(record: .never))
struct ActiveSetCardVisualTests {
    @Test func activeSetCardMatchesVisualBaseline() throws {
        try assertCardSnapshot(makeCardScenario(), setOrdinal: 3, history: [], appearance: .day, colorScheme: .light)
    }

    @Test func activeSetCardMatchesNightVisualBaseline() throws {
        try assertCardSnapshot(makeCardScenario(), setOrdinal: 3, history: [], appearance: .night, colorScheme: .dark)
    }

    @Test func activeSetCardWithAHistoryEstimateMatchesVisualBaseline() throws {
        let lastBlock = LastPerformedEntry(
            fullName: "Competition Bench Press",
            baseName: "Competition Bench Press",
            resultText: "185x5@7, 195x5@8",
            performedOn: Date(timeIntervalSinceReferenceDate: 0),
            source: "Block 26 · W4 D1"
        )

        try assertCardSnapshot(
            makeHistoryEstimateScenario(),
            setOrdinal: 1,
            history: [lastBlock],
            appearance: .day,
            colorScheme: .light
        )
    }

    private func assertCardSnapshot(
        _ card: (exercise: Exercise, set: ExerciseSet),
        setOrdinal: Int,
        history: [LastPerformedEntry],
        appearance: Theme.Appearance,
        colorScheme: ColorScheme,
        fileID: StaticString = #fileID,
        file: StaticString = #filePath,
        testName: String = #function,
        line: UInt = #line,
        column: UInt = #column
    ) throws {
        let scenario = try WorkoutScenarios.freshConfiguredApp()
        VisualFixtureRetainer.retain(scenario)
        let lastPerformed = LastPerformedLookupStore(context: scenario.context)
        try lastPerformed.ingest(history)

        let view = ZStack {
            Theme.palette(for: appearance).paperBackground
                .ignoresSafeArea()

            VStack {
                Spacer(minLength: 0)
                ActiveSetCard(
                    set: card.set,
                    setOrdinal: setOrdinal,
                    setCount: 5,
                    onLog: { _ in },
                    onSkip: {},
                    onDelete: {}
                )
                .padding(.horizontal, 16)
                Spacer(minLength: 0)
            }
        }
        .environment(lastPerformed)
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
        withExtendedLifetime(card.exercise) {}
    }

    /// Reproduces the pick: Set 3 of 5 of a bench press, weight prefilled to 90 (60% of a 150
    /// training max), reps 5 and RPE 8 prescribed and prefilled.
    private func makeCardScenario() -> (Exercise, ExerciseSet) {
        let exercise = Exercise(
            name: "Competition Bench Press",
            baseName: "Competition Bench Press",
            cadence: nil,
            coachNote: nil,
            order: 0
        )
        exercise.sets = (0..<5).map { index in
            let set = ExerciseSet(
                index: index,
                prescribedReps: "5",
                prescribedLoad: "RPE 8",
                percentOneRM: "60%",
                state: index < 2 ? .logged : .pending
            )
            if index < 2 {
                set.setLog = SetLog(weight: .pounds(90), reps: 5, rpe: .eight)
            }
            return set
        }

        let session = Session(dayNumber: 2, date: nil)
        session.exercises = [exercise]
        let week = Week(number: 2)
        week.sessions = [session]
        let block = Block(tabName: "Block 27", trainingMaxes: [.bench: 150])
        block.weeks = [week]

        return (exercise, exercise.sets[2])
    }

    /// Set 1 of 5 of a bench press at an RPE target with no %1RM, so the card estimates from the
    /// last Block's entry and names it as its Load Basis.
    private func makeHistoryEstimateScenario() -> (Exercise, ExerciseSet) {
        let exercise = Exercise(
            name: "Competition Bench Press",
            baseName: "Competition Bench Press",
            cadence: nil,
            coachNote: nil,
            order: 0
        )
        exercise.sets = (0..<5).map { index in
            ExerciseSet(index: index, prescribedReps: "5", prescribedLoad: "RPE 7", percentOneRM: nil, state: .pending)
        }

        let session = Session(dayNumber: 2, date: nil)
        session.exercises = [exercise]
        let week = Week(number: 2)
        week.sessions = [session]
        let block = Block(tabName: "Block 27")
        block.weeks = [week]

        return (exercise, exercise.sets[0])
    }
}
