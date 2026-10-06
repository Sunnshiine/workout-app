import SnapshotTesting
import SwiftUI
import Testing

@testable import WorkoutTracker

@MainActor
@Suite(.snapshots(record: .never))
struct SessionQueueSheetVisualTests {
    /// Browsing the day's queue: two completed Exercises (no checkmark), the Exercise on stage marked
    /// "Now", and two still-pending — the living-paper hero shot.
    @Test func queueSheetBrowsingMatchesVisualBaseline() {
        assertQueueSheet(appearance: .day, colorScheme: .light) {
            browsingSheet()
        }
    }

    @Test func queueSheetBrowsingMatchesNightVisualBaseline() {
        assertQueueSheet(appearance: .night, colorScheme: .dark) {
            browsingSheet()
        }
    }

    @Test func queueSheetPairingConfirmationMatchesVisualBaseline() {
        assertQueueSheet(appearance: .day, colorScheme: .light) {
            pairingSheet()
        }
    }

    @Test func queueSheetPairingConfirmationMatchesNightVisualBaseline() {
        assertQueueSheet(appearance: .night, colorScheme: .dark) {
            pairingSheet()
        }
    }

    private func browsingSheet() -> SessionQueueSheet {
        queueSheet(pairable: [], pairingMode: .inactive)
    }

    private func pairingSheet() -> SessionQueueSheet {
        queueSheet(pairable: [2, 3, 4], pairingMode: .confirming(sourceOrder: 2, targetOrder: 3))
    }

    private func queueSheet(pairable: Set<Int>, pairingMode: PairingMode) -> SessionQueueSheet {
        let session = Session(dayNumber: 1, date: nil)
        session.exercises = [
            makeExercise(name: "Competition Bench Press", order: 0, setStates: [.logged, .logged, .logged, .logged, .logged]),
            makeExercise(name: "Larsen Press", order: 1, setStates: [.logged, .logged, .logged]),
            makeExercise(name: "DB Incline Press", order: 2, setStates: [.logged, .pending, .pending, .pending]),
            makeExercise(name: "Chest-Supported Row", order: 3, setStates: [.pending, .pending, .pending]),
            makeExercise(name: "Seated DB OHP", order: 4, setStates: [.pending, .pending])
        ]
        let stage = SessionStage(
            session: session,
            focus: SessionFocusSnapshot(
                activeSetID: nil,
                expandedLoggedSetID: nil,
                supersets: [],
                pairableExerciseOrders: pairable
            ),
            savedLoggedSetID: nil,
            pairingMode: pairingMode,
            liveEdge: .browsedAway,
            lookup: .empty
        )
        return SessionQueueSheet(queue: stage.queue, session: session, coordinator: SessionCoordinator(session: session))
    }

    private func makeExercise(name: String, order: Int, setStates: [SetState]) -> Exercise {
        let exercise = Exercise(name: name, baseName: name, cadence: nil, coachNote: nil, order: order)
        exercise.sets = setStates.enumerated().map { index, state in
            ExerciseSet(index: index, prescribedReps: "5", prescribedLoad: "RPE 8", percentOneRM: nil, state: state)
        }
        return exercise
    }

    private func assertQueueSheet(
        appearance: Theme.Appearance,
        colorScheme: ColorScheme,
        height: CGFloat = 520,
        testName: String = #function,
        @ViewBuilder _ content: () -> some View
    ) {
        // `.presentationBackground` is a no-op offscreen, so the fixture host paints the living paper
        // behind the sheet content exactly as the medium detent would (matching ExerciseHistorySheet).
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
