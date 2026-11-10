import Foundation
import Testing

@testable import WorkoutTracker

private let firstSet = ActiveSetID(exerciseOrder: 0, setIndex: 0)
private let secondSet = ActiveSetID(exerciseOrder: 0, setIndex: 1)
private let logged235 = SetLog(weight: .pounds(235), reps: 5, rpe: .seven)

/// The card is the athlete's to turn while the island reads the Set Log back. The readback stays
/// for its whole hold, and comes off over the face they turned to.
@MainActor
@Test func aTurnWhileTheIslandReadsBackKeepsTheReadbackAndTheFace() async throws {
    let harness = try await BackgroundDictationHarness(hearing: [])
    try harness.restRunning()
    let chips = harness.chips
    let identity = harness.identity()
    let run = Task { await chips.logSet(setIdentity: identity, reps: 5, rpe: "7") }
    await harness.clock.waitUntilSleeping(
        until: harness.clock.now + LockScreenPress.readbackHold,
        orRecord: "The island's readback never held"
    )

    let turned = await chips.turn(to: .reps, pressing: harness.identity(of: secondSet))

    #expect(turned == .turned(to: .reps))
    #expect(harness.liveActivity.replacements.isEmpty, "the island still reads the Set Log back")
    harness.clock.advance(by: LockScreenPress.readbackHold)
    #expect(await run.value == .logged(logged235, at: firstSet))
    #expect(harness.liveActivity.replacements.count == 1)
    let replacement = try #require(harness.liveActivity.replacements.first)
    #expect(replacement.readback == .logged("235×5 @7", to: try harness.squat(set: 1)))
    #expect(replacement.card.face == .reps)
    #expect(harness.face == .reps)
}

/// No rest follows the Session's last Set, so the card has no next Set to draw. The island reads
/// the Set Log back over the card as it was, and the card goes once the hold is over. Nothing
/// reads back on the card.
@MainActor
@Test func theSessionsLastSetReadsBackOnTheIslandThenTakesTheCardDown() async throws {
    let harness = try await BackgroundDictationHarness(hearing: [])
    let session = try #require(harness.app.workout.currentSession)
    let last = try #require(try harness.onItsLastSet(of: session))
    try harness.restRunning()
    let chips = harness.chips
    let identity = harness.identity(of: last.setID)
    _ = await harness.turn(to: .rpe(reps: 5), pressing: identity, on: chips)
    harness.clock.advance(by: RPEFaceSettle.duration)

    let run = Task { await chips.logSet(setIdentity: identity, reps: 5, rpe: "7") }
    await harness.clock.waitUntilSleeping(
        until: harness.clock.now + LockScreenPress.readbackHold,
        orRecord: "The island's readback never held"
    )
    let islandReadback = try #require(harness.liveActivity.islandReadbacks.last)
    #expect(islandReadback.readback == .logged("235×5 @7", to: .init(last, in: session)))
    #expect(islandReadback.card.face == .rpe(reps: 5), "the card stays on the face it was on")
    #expect(islandReadback.card.target?.setID == last.setID)
    #expect(harness.liveActivity.endedRests == 0)

    harness.clock.advance(by: LockScreenPress.readbackHold)
    #expect(await run.value == .logged(logged235, at: last.setID))
    #expect(harness.liveActivity.endedRests == 1)
    #expect(harness.liveActivity.restContent == nil)
    #expect(harness.liveActivity.readbacks.isEmpty)
}

/// With no card up there is nothing for the island to read over, so the press only writes.
@MainActor
@Test func theSessionsLastSetWithNoCardUpOnlyWrites() async throws {
    let harness = try await BackgroundDictationHarness(hearing: [])
    let session = try #require(harness.app.workout.currentSession)
    let last = try #require(try harness.onItsLastSet(of: session))

    let outcome = await harness.chips.logSet(setIdentity: harness.identity(of: last.setID), reps: 5, rpe: "7")

    #expect(outcome == .logged(logged235, at: last.setID))
    #expect(harness.liveActivity.islandReadbacks.isEmpty)
    #expect(harness.liveActivity.readbacks.isEmpty)
    #expect(try harness.app.sync.fetchPendingWriteRecords().isEmpty)
}

extension BackgroundDictationHarness {
    /// Logs every Set of `session` but the last, which the card then offers.
    fileprivate func onItsLastSet(of session: Session) throws -> SessionSetPosition? {
        let sets = SessionSetOrder.orderedSets(in: session)
        for position in sets.dropLast() {
            try app.workout.log(position.set, as: logged235)
        }
        focus.reset(to: session)
        return sets.last
    }
}
