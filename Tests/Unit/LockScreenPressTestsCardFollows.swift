import Foundation
import Testing

@testable import WorkoutTracker

private let logged235 = SetLog(weight: .pounds(235), reps: 5, rpe: .seven)

/// A press in a Superset moves the card as a tap on the app's Log button would, and the rest it
/// starts names that same Set.
@MainActor
@Test func aChipInASupersetLeadsTheRestWhereTheCardGoes() async throws {
    let harness = try await BackgroundDictationHarness(hearing: [])
    let session = try #require(harness.app.workout.currentSession)
    let stage = harness.stage(on: session)
    let squat = try #require(session.exercises.first { $0.order == 0 })
    let rdl = try #require(session.exercises.first { $0.order == 1 })
    #expect(stage.createSuperset(from: squat, to: rdl, in: session))
    stage.log(try #require(squat.sets.first { $0.index == 0 }), as: logged235)
    let pressed = ActiveSetID(exerciseOrder: rdl.order, setIndex: 0)
    #expect(stage.activeSetID == pressed)

    let outcome = await harness.press(harness.identity(of: pressed))

    #expect(outcome == .logged(logged235, at: pressed))
    let next = ActiveSetID(exerciseOrder: squat.order, setIndex: 1)
    #expect(stage.activeSetID == next, "the Superset alternates back, as a tap would")
    #expect(harness.liveActivity.islandReadbacks.last?.card.target?.setID == next)
}

/// A press on an Exercise picked out of order leads the rest to that Exercise's next Set, where the
/// card goes, not to the first Pending Set in the Session (#1233).
@MainActor
@Test func aChipOnAnExercisePickedOutOfOrderLeadsTheRestWhereTheCardGoes() async throws {
    let harness = try await BackgroundDictationHarness(hearing: [])
    let session = try #require(harness.app.workout.currentSession)
    let stage = harness.stage(on: session)
    let rdl = try #require(session.exercises.first { $0.order == 1 })
    stage.focus(on: try #require(rdl.sets.first { $0.index == 0 }))
    let pressed = ActiveSetID(exerciseOrder: rdl.order, setIndex: 0)

    let outcome = await harness.press(harness.identity(of: pressed))

    #expect(outcome == .logged(logged235, at: pressed))
    let next = ActiveSetID(exerciseOrder: rdl.order, setIndex: 1)
    #expect(stage.activeSetID == next)
    #expect(harness.liveActivity.islandReadbacks.last?.card.target?.setID == next)
}
