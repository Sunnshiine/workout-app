import Foundation
import Testing

@testable import WorkoutTracker

@MainActor
private func finishedSquatRow(_ coordinator: SessionCoordinator, in session: Session) throws -> SessionQueue.Row {
    try #require(coordinator.stage(in: session, lookup: .empty).queue.rows.first { $0.id == "exercise-0" })
}

@MainActor
@Test func aJumpFromTheQueueToAFinishedExerciseOpensItsLoggedSetForReview() throws {
    let session = makeCoordinatorSession()
    let coordinator = SessionCoordinator(session: session, wiring: .fixture())
    let row = try finishedSquatRow(coordinator, in: session)
    #expect(row.isComplete)

    coordinator.jump(to: try #require(row.jumpTarget))

    let stage = try #require(exerciseStage(coordinator, in: session))
    #expect(stage.exercise.order == 0)
    #expect(stage.card?.mode == .reviewingLogged(showsSavedConfirmation: false))
    #expect(try finishedSquatRow(coordinator, in: session).isOnStage)
}

@MainActor
@Test func aSecondJumpToTheFinishedExerciseOnStageKeepsItsReviewOpen() throws {
    let session = makeCoordinatorSession()
    let coordinator = SessionCoordinator(session: session, wiring: .fixture())
    let target = try #require(try finishedSquatRow(coordinator, in: session).jumpTarget)

    coordinator.jump(to: target)
    coordinator.jump(to: target)

    #expect(exerciseStage(coordinator, in: session)?.card?.mode == .reviewingLogged(showsSavedConfirmation: false))
}

@MainActor
@Test func aJumpToAnUnfinishedExerciseFocusesItsNextPendingSet() throws {
    let session = makeCoordinatorSession()
    let coordinator = SessionCoordinator(session: session, wiring: .fixture())
    let row = try #require(coordinator.stage(in: session, lookup: .empty).queue.rows.first { $0.id == "exercise-2" })

    coordinator.jump(to: try #require(row.jumpTarget))

    #expect(coordinator.activeSetID == ActiveSetID(exerciseOrder: 2, setIndex: 0))
    #expect(exerciseStage(coordinator, in: session)?.card?.mode == .logging)
}
