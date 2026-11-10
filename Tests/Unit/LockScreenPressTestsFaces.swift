import Foundation
import Testing

@testable import WorkoutTracker

private let firstSet = ActiveSetID(exerciseOrder: 0, setIndex: 0)
private let secondSet = ActiveSetID(exerciseOrder: 0, setIndex: 1)
private let logged235 = SetLog(weight: .pounds(235), reps: 5, rpe: .seven)

/// Log, a Reps Chip, and back only turn the card, so a Set half chosen writes nothing.
@MainActor
@Test func logThenARepsChipTurnTheCardToRepsThenRPEAndWriteNothing() async throws {
    let harness = try await BackgroundDictationHarness(hearing: [])
    try harness.restRunning()
    let chips = harness.chips

    #expect(await harness.turn(to: .reps, pressing: harness.identity(), on: chips) == .turned(to: .reps))
    #expect(harness.face == .reps)
    #expect(await harness.turn(to: .rpe(reps: 6), pressing: harness.identity(), on: chips) == .turned(to: .rpe(reps: 6)))
    #expect(harness.face == .rpe(reps: 6))

    #expect(harness.liveActivity.refreshes.count == 2)
    #expect(harness.liveActivity.readbacks.isEmpty)
    try harness.expectNothingWritten()
}

@MainActor
@Test func backTurnsTheCardFromRPEToRepsAndFromRepsToItsRestFace() async throws {
    let harness = try await BackgroundDictationHarness(hearing: [])
    try harness.restRunning()
    let chips = harness.chips
    _ = await harness.turn(to: .rpe(reps: 6), pressing: harness.identity(), on: chips)

    #expect(await harness.turn(to: .reps, pressing: harness.identity(), on: chips) == .turned(to: .reps))
    #expect(harness.face == .reps)
    #expect(await harness.turn(to: .rest, pressing: nil, on: chips) == .turned(to: .rest))
    #expect(harness.face == .rest)

    #expect(harness.liveActivity.readbacks.isEmpty)
    try harness.expectNothingWritten()
}

@MainActor
@Test func theNoteButtonOpensTheCoachNoteAndCloseBringsTheNumbersBack() async throws {
    let harness = try await BackgroundDictationHarness(hearing: [])
    try #require(harness.app.workout.currentSession).exercises.first { $0.order == 0 }?.coachNote = "Pause on the chest."
    try harness.restRunning()
    let chips = harness.chips

    #expect(await harness.turn(to: .coachNote, pressing: nil, on: chips) == .turned(to: .coachNote))
    #expect(harness.face == .coachNote)
    #expect(await harness.turn(to: .rest, pressing: nil, on: chips) == .turned(to: .rest))
    #expect(harness.face == .rest)

    #expect(harness.liveActivity.readbacks.isEmpty)
    try harness.expectNothingWritten()
}

/// A card with no Coach Note draws no note button, so only a stale tap gets here.
@MainActor
@Test func aSetWithNoCoachNoteHasNoNoteToOpen() async throws {
    let harness = try await BackgroundDictationHarness(hearing: [])
    try harness.restRunning()

    let outcome = await harness.turn(to: .coachNote, pressing: nil)

    #expect(outcome == .turned(to: .rest))
    #expect(harness.liveActivity.refreshes.isEmpty)
}

/// A press can land twice, as a chalky double tap presses it. Each control names the face it turns
/// to, so the second press finds the card already there.
@MainActor
@Test func theSameControlTwiceDrawsTheCardOnce() async throws {
    let harness = try await BackgroundDictationHarness(hearing: [])
    try harness.restRunning()
    let chips = harness.chips

    _ = await harness.turn(to: .reps, pressing: harness.identity(), on: chips)
    let outcome = await harness.turn(to: .reps, pressing: harness.identity(), on: chips)

    #expect(outcome == .turned(to: .reps))
    #expect(harness.liveActivity.refreshes.count == 1)
}

/// The second tap of a double tap on a Reps Chip lands on the RPE Chip that took its place, and
/// must not log Reps the athlete tapped and an RPE they never chose. It says so, and the card that
/// follows still offers RPE for those Reps.
@MainActor
@Test func anRPEChipAsTheCardTurnsWritesNothingAndOneAfterItLogs() async throws {
    let harness = try await BackgroundDictationHarness(hearing: [])
    try harness.restRunning()
    let chips = harness.chips
    _ = await harness.turn(to: .rpe(reps: 6), pressing: harness.identity(), on: chips)
    harness.clock.advance(by: .milliseconds(400))

    let early = await harness.press(harness.identity(), reps: 6, rpe: "7", on: chips)

    try #require(early == .notLogged(.tooSoonAfterReps))
    #expect(harness.liveActivity.readbacks == [.notLogged("Too soon after the Reps. Tap the RPE again")])
    #expect(harness.liveActivity.replacements.count == 1)
    #expect(harness.face == .rpe(reps: 6), "the card that follows the readback stays on RPE")
    try harness.expectNothingWritten()

    let outcome = await harness.press(harness.identity(), reps: 6, rpe: "7", on: chips)

    #expect(outcome == .logged(SetLog(weight: .pounds(235), reps: 6, rpe: .seven), at: firstSet))
}

/// Log, Reps, then RPE logs the Set the card showed, and the next Set's card comes up on its rest
/// face under a readback only the island reads.
@MainActor
@Test func logThenRepsThenRPELogsTheSetAndShowsTheNextSetsRest() async throws {
    let harness = try await BackgroundDictationHarness(hearing: [])
    try harness.restRunning()
    let chips = harness.chips
    _ = await harness.turn(to: .reps, pressing: harness.identity(), on: chips)
    _ = await harness.turn(to: .rpe(reps: 6), pressing: harness.identity(), on: chips)
    harness.clock.advance(by: LockScreenRows.rpeFaceSettle)

    let outcome = await harness.press(harness.identity(), reps: 6, rpe: "8", on: chips)

    #expect(outcome == .logged(SetLog(weight: .pounds(235), reps: 6, rpe: .eight), at: firstSet))
    #expect(try harness.app.session(nil).exercises[0].sets[0].setLog == "235x6@8")
    #expect(harness.liveActivity.shown.map(\.content.staysOffTheCard) == [true])
    #expect(harness.liveActivity.restsShown.first?.face == .rest, "the card left its RPE face as the Set logged")
    let card = try #require(harness.liveActivity.restContent)
    #expect(card.target?.setID == secondSet)
    #expect(card.face == .rest)
    #expect(card.restEndDate == harness.restTimer.interval?.end)
}

@MainActor
@Test(arguments: [LockScreenFace.reps, .rpe(reps: 6)])
func aPressTowardTheChoicesOfALoggedSetWritesNothingAndSaysSo(face: LockScreenFace) async throws {
    let harness = try await BackgroundDictationHarness(hearing: [])
    let identity = harness.identity()
    _ = await harness.press(identity)

    let outcome = await harness.turn(to: face, pressing: identity)

    #expect(outcome == .notLogged(.setSettled(setLog: "235×5 @7", set: try harness.squat(set: 1))))
    #expect(harness.liveActivity.readbacks.last == .settled(setLog: "235×5 @7", try harness.squat(set: 1)))
    #expect(harness.face == .rest)
}

@MainActor
@Test(
    arguments: [
        ("Block 26", LockScreenFace.reps, LockScreenPress.NotLogged.sessionChanged),
        ("Block 26", .rpe(reps: 6), .sessionChanged),
        ("Block 27", .rpe(reps: 0), .unreadable),
        ("Block 27", .rpe(reps: 101), .unreadable),
        (nil, .reps, .unreadable)
    ] as [(String?, LockScreenFace, LockScreenPress.NotLogged)]
)
func aPressThatCannotTurnTheCardToItsChoicesWritesNothingAndSaysSo(
    blockTab: String?,
    face: LockScreenFace,
    why: LockScreenPress.NotLogged
) async throws {
    let harness = try await BackgroundDictationHarness(hearing: [])
    try harness.restRunning()

    let outcome = await harness.turn(to: face, pressing: blockTab.map { harness.identity(blockTab: $0) })

    #expect(outcome == .notLogged(why))
    #expect(harness.liveActivity.readbacks.first == .notLogged(why.caption))
    #expect(harness.liveActivity.refreshes.isEmpty)
    #expect(harness.face == .rest)
    try harness.expectNothingWritten()
}

/// A flush that lands redraws the card to drop its count, and the island's readback ends. The
/// athlete may have pressed Log meanwhile, and neither turns the card back under their thumb.
@MainActor
@Test func aFlushThatLandsKeepsTheFaceTheAthleteTurnedTo() async throws {
    let sheet = HeldWriteSheetsClient()
    let harness = try await BackgroundDictationHarness(hearing: [], sheet: sheet)
    let chips = harness.chips
    let identity = harness.identity()
    let run = Task { await chips.logSet(setIdentity: identity, reps: 5, rpe: "7") }
    await sheet.waitUntilHeld(orRecord: "The flush never reached the Sheet")

    _ = await chips.turn(to: .reps, pressing: harness.identity(of: secondSet))
    #expect(harness.liveActivity.restContent?.pendingWrites == 1)
    await harness.clock.waitUntilSleeping(
        until: harness.clock.now + LockScreenPress.readbackHold,
        orRecord: "The readback never held"
    )
    harness.clock.advance(by: LockScreenPress.readbackHold)
    sheet.release()

    #expect(await run.value == .logged(logged235, at: firstSet))
    #expect(harness.face == .reps)
    #expect(harness.liveActivity.restContent?.pendingWrites == 0)
}

/// A locked phone has no header, so a press that logged nothing still shows the writes the Sheet
/// does not have yet.
@MainActor
@Test func aReadbackThatLoggedNothingCountsTheWritesStillQueued() async throws {
    let harness = try await BackgroundDictationHarness(hearing: [])
    let session = try #require(harness.app.workout.currentSession)
    try harness.app.workout.log(try #require(SessionSetOrder.orderedSets(in: session).first).set, as: logged235)

    _ = await harness.press(harness.identity(of: secondSet, blockTab: "Block 26"))

    guard case .set(let set) = harness.liveActivity.subjects.last else {
        Issue.record("The readback showed \(String(describing: harness.liveActivity.subjects.last))")
        return
    }
    #expect(set.pendingWrites == 1)
}
