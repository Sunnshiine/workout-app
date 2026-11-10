import Foundation
import Testing

@testable import WorkoutTracker

private let firstSet = ActiveSetID(exerciseOrder: 0, setIndex: 0)
private let secondSet = ActiveSetID(exerciseOrder: 0, setIndex: 1)
private let thirdSet = ActiveSetID(exerciseOrder: 0, setIndex: 2)
private let logged235 = SetLog(weight: .pounds(235), reps: 5, rpe: .seven)

/// The card says a Set was logged by what it draws next: the next Set's rest, begun afresh, on a
/// face that arrives forward. Nothing on it reads `Logged`.
@MainActor
@Test func aLogBringsTheNextSetsRestForwardFromFull() async throws {
    let harness = try await BackgroundDictationHarness(hearing: [])
    try harness.restRunning()
    let ridden = try #require(harness.liveActivity.restContent)
    let chips = harness.chips
    _ = await harness.turn(to: .reps, pressing: harness.identity(), on: chips)
    _ = await harness.turn(to: .rpe(reps: 5), pressing: harness.identity(), on: chips)
    harness.clock.advance(by: RPEFaceSettle.duration)

    _ = await harness.press(harness.identity(), on: chips)

    let card = try #require(harness.liveActivity.islandReadbacks.last?.card)
    #expect(card.target?.setID == secondSet)
    #expect(card.face == .rest)
    #expect(card.turn == .forward)
    #expect(card.stats.map(\.value) == ["235", "5", "7"])
    let rest = try #require(harness.restTimer.interval)
    #expect(card.restStartDate == rest.start)
    #expect(card.restEndDate == rest.end)
    #expect(card.restStartDate != ridden.restStartDate, "the rest it rode is used up")
    #expect(harness.liveActivity.readbacks.isEmpty, "the card reads nothing back")
    #expect(harness.liveActivity.heldSets.isEmpty)
}

@MainActor
@Test func aLogBeforeADropSetRollsTheNumbersToTheWeightWorkedOut() async throws {
    let harness = try await BackgroundDictationHarness(hearing: [])
    let session = try #require(harness.app.workout.currentSession)
    let drop = try #require(session.exercises.first { $0.order == 0 }?.sets.first { $0.index == 1 })
    drop.prescribedLoad = "Drop 10%"

    _ = await harness.press(harness.identity(weight: .pounds(200)))

    let card = try #require(harness.liveActivity.islandReadbacks.last?.card)
    #expect(card.target?.setID == secondSet)
    #expect(card.stats.map(\.value) == ["180", "5", LockScreenStat.missingValue])
    #expect(card.turn == .forward)
    #expect(card.face == .rest)
}

@MainActor
@Test func aTurnBackSaysSoAndATurnOnSaysForward() async throws {
    let harness = try await BackgroundDictationHarness(hearing: [])
    try harness.restRunning()
    let chips = harness.chips

    _ = await harness.turn(to: .reps, pressing: harness.identity(), on: chips)
    #expect(harness.liveActivity.restContent?.turn == .forward)
    _ = await harness.turn(to: .rpe(reps: 6), pressing: harness.identity(), on: chips)
    #expect(harness.liveActivity.restContent?.turn == .forward)
    _ = await harness.turn(to: .reps, pressing: harness.identity(), on: chips)
    #expect(harness.liveActivity.restContent?.turn == .back)
    _ = await harness.turn(to: .rest, pressing: nil, on: chips)
    #expect(harness.liveActivity.restContent?.turn == .back)
    _ = await harness.turn(to: .reps, pressing: harness.identity(), on: chips)
    #expect(harness.liveActivity.restContent?.turn == .forward)

    try harness.expectNothingWritten()
}

/// The athlete can log the next Set while the island still reads the last one back. Its rest
/// arrives forward like any other, and the first hold running out leaves the second readback up.
@MainActor
@Test func aLogWhileTheIslandReadsBackBringsItsOwnRestForward() async throws {
    let harness = try await BackgroundDictationHarness(hearing: [])
    try harness.restRunning()
    let chips = harness.chips
    let first = harness.identity()
    let firstRun = Task { await chips.logSet(setIdentity: first, reps: 5, rpe: "7") }
    await harness.clock.waitUntilSleeping(
        until: harness.clock.now + LockScreenPress.readbackHold,
        orRecord: "The island's readback never held"
    )
    let firstHoldEnds = harness.clock.now + LockScreenPress.readbackHold
    let second = harness.identity(of: secondSet)
    _ = await chips.turn(to: .rpe(reps: 5), pressing: second)
    harness.clock.advance(by: RPEFaceSettle.duration)

    let secondRun = Task { await chips.logSet(setIdentity: second, reps: 5, rpe: "7") }
    await waitUntil({ harness.liveActivity.islandReadbacks.count == 2 }, orRecord: "The second Set never read back")

    let card = try #require(harness.liveActivity.islandReadbacks.last?.card)
    #expect(card.target?.setID == thirdSet)
    #expect(card.face == .rest)
    #expect(card.turn == .forward)
    #expect(card.restStartDate == harness.restTimer.interval?.start)

    harness.clock.advance(by: firstHoldEnds - harness.clock.now)
    #expect(await firstRun.value == .logged(logged235, at: firstSet))
    #expect(harness.liveActivity.replacements.isEmpty, "the island still reads the second Set Log back")
    await harness.clock.waitUntilSleeping(
        until: harness.clock.now + RPEFaceSettle.duration,
        orRecord: "The second readback never held"
    )
    harness.clock.advance(by: RPEFaceSettle.duration)
    #expect(await secondRun.value == .logged(logged235, at: secondSet))
    #expect(harness.liveActivity.replacements.map(\.readback) == [.logged("235×5 @7", to: try harness.squat(set: 2))])
}

/// An earlier day of the week still owes work, so the rest after the Session's last Set leads to
/// that day's Set. It arrives like any next Set, and only the app can log it.
@MainActor
@Test func aLogWhoseNextSetIsInAnotherSessionRollsToThatSet() async throws {
    let harness = try await BackgroundDictationHarness(hearing: [])
    let dayOne = try #require(harness.app.workout.currentSession?.placement.coordinate)
    harness.app.workout.moveOn()
    let session = try #require(harness.app.workout.currentSession)
    try #require(session.placement.coordinate != dayOne)
    let last = try #require(try harness.onItsLastSet(of: session))
    try harness.restRunning()
    let chips = harness.chips
    let identity = try harness.identity(of: last, in: session)
    _ = await harness.turn(to: .rpe(reps: 5), pressing: identity, on: chips)
    harness.clock.advance(by: RPEFaceSettle.duration)

    _ = await harness.press(identity, on: chips)

    let card = try #require(harness.liveActivity.islandReadbacks.last?.card)
    #expect(card.target == LiveActivityRestTarget(session: dayOne, setID: firstSet))
    #expect(card.exerciseName == "Back Squat")
    #expect(card.press == .needsApp)
    #expect(card.face == .rest)
    #expect(card.turn == .forward)
    #expect(card.restStartDate == harness.restTimer.interval?.start)
    #expect(harness.liveActivity.heldSets.isEmpty)
}

/// The Block has no Set left, so nothing rolls in. The card holds the Set Log's numbers with
/// nothing to press while the island reads it back, then goes.
@MainActor
@Test func theBlocksLastSetHoldsItsSetLogThenTakesTheCardDown() async throws {
    let harness = try await BackgroundDictationHarness(hearing: [])
    let session = try harness.onTheBlocksLastSession()
    try #require(session.placement.coordinate?.address == SessionAddress(week: 2, day: 2))
    let last = try #require(try harness.onItsLastSet(of: session))
    try harness.restRunning()
    let chips = harness.chips
    let identity = try harness.identity(of: last, in: session)
    _ = await harness.turn(to: .rpe(reps: 5), pressing: identity, on: chips)
    harness.clock.advance(by: RPEFaceSettle.duration)

    let run = Task { await chips.logSet(setIdentity: identity, reps: 5, rpe: "7") }
    await harness.clock.waitUntilSleeping(
        until: harness.clock.now + LockScreenPress.readbackHold,
        orRecord: "The island's readback never held"
    )

    let held = try #require(harness.liveActivity.heldSets.last)
    #expect(held.readback == .logged("235×5 @7", to: .init(last, in: session)))
    #expect(held.loggedSet.stats.map(\.value) == ["235", "5", "7"])
    #expect(held.loggedSet.set.setsDone == held.loggedSet.set.setsTotal)
    #expect(harness.liveActivity.islandReadbacks.isEmpty, "no card with chips goes up under the readback")
    #expect(harness.restTimer.interval == nil, "no rest follows the Block's last Set")
    #expect(harness.liveActivity.endedRests == 0)

    harness.clock.advance(by: LockScreenPress.readbackHold)
    #expect(await run.value == .logged(logged235, at: last.setID))
    #expect(harness.liveActivity.endedRests == 1)
    #expect(harness.liveActivity.restContent == nil)
}

extension BackgroundDictationHarness {
    /// Logs every Session the Block can still move on from, which leaves its last one current.
    fileprivate func onTheBlocksLastSession() throws -> Session {
        let block = try #require(app.workout.block)
        let tracker = SessionProgressTracker()
        while let session = app.workout.currentSession, case .advance = tracker.moveOnDestination(from: session, in: block) {
            for position in SessionSetOrder.orderedSets(in: session) {
                try app.workout.log(position.set, as: logged235)
            }
            app.workout.moveOn()
        }
        return try #require(app.workout.currentSession)
    }
}
