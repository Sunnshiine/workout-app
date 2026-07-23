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
        try assertCardSnapshot(appearance: .day, colorScheme: .light)
    }

    @Test func activeSetCardMatchesNightVisualBaseline() throws {
        try assertCardSnapshot(appearance: .night, colorScheme: .dark)
    }

    private func assertCardSnapshot(
        appearance: Theme.Appearance,
        colorScheme: ColorScheme,
        fileID: StaticString = #fileID,
        file: StaticString = #filePath,
        testName: String = #function,
        line: UInt = #line,
        column: UInt = #column
    ) throws {
        let (exercise, set) = makeCardScenario()

        let view = ZStack {
            Theme.palette(for: appearance).paperBackground
                .ignoresSafeArea()

            VStack {
                Spacer(minLength: 0)
                ActiveSetCard(
                    exercise: exercise,
                    set: set,
                    setOrdinal: 3,
                    setCount: 5,
                    onLog: { _ in },
                    onSkip: {},
                    onDelete: {}
                )
                .padding(.horizontal, 16)
                Spacer(minLength: 0)
            }
        }
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
                set.setLog = SetLog(weight: .pounds(90), reps: 5, rpe: 8)
            }
            return set
        }

        let session = Session(dayNumber: 2, date: nil)
        session.exercises = [exercise]
        let week = Week(number: 2)
        week.sessions = [session]
        let block = Block(tabName: "Block 27", squatTM: nil, benchTM: 150, deadliftTM: nil)
        block.weeks = [week]

        return (exercise, exercise.sets[2])
    }
}
