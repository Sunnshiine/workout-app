import Foundation
import Testing

@testable import WorkoutTracker

extension SessionStageTests {
    @Test func aFinishedExercisesRowJumpsToItsFirstLoggedSet() {
        let squat = makeExercise(name: "Squat", order: 0, setStates: [.skipped, .logged, .logged])
        let bench = makeExercise(name: "Bench Press", order: 1, setStates: [.pending])

        let row = makeStage([squat, bench]).queue.rows[0]

        #expect(row.isComplete)
        #expect(row.jumpTarget === squat.sets.first { $0.index == 1 })
    }

    @Test func aFinishedExerciseWithEverySetSkippedJumpsToItsFirstSet() {
        let squat = makeExercise(name: "Squat", order: 0, setStates: [.skipped, .skipped])
        let bench = makeExercise(name: "Bench Press", order: 1, setStates: [.pending])

        #expect(makeStage([squat, bench]).queue.rows[0].jumpTarget === squat.sets.first { $0.index == 0 })
    }

    @Test func everyFinishedExerciseOfACompleteSessionKeepsAJump() {
        let squat = makeExercise(name: "Squat", order: 0, setStates: [.logged])
        let bench = makeExercise(name: "Bench Press", order: 1, setStates: [.logged, .skipped])

        let rows = makeStage([squat, bench]).queue.rows

        #expect(rows.map { $0.jumpTarget != nil } == [true, true])
    }

    @Test func aFinishedSupersetsRowHasNoJumpBecauseItsStageShowsNoReview() {
        let press = makeExercise(name: "Press", order: 0, setStates: [.logged])
        let row = makeExercise(name: "Row", order: 1, setStates: [.logged])
        let squat = makeExercise(name: "Squat", order: 2, setStates: [.pending])

        let stage = makeStage([press, row, squat], supersets: [Superset(first: press, second: row)])

        #expect(stage.queue.rows[0].kind == .superset)
        #expect(stage.queue.rows[0].isComplete)
        #expect(stage.queue.rows[0].jumpTarget == nil)
    }
}
