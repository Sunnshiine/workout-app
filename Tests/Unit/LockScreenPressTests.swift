import Foundation
import Testing

@testable import WorkoutTracker

private let firstSet = ActiveSetID(exerciseOrder: 0, setIndex: 0)
private let secondSet = ActiveSetID(exerciseOrder: 0, setIndex: 1)
private let logged235 = SetLog(weight: .pounds(235), reps: 5, rpe: .seven)

@MainActor
@Test func aChipLogsWhatTheLockScreenShowedStartsTheRestAndFlushes() async throws {
    let harness = try await BackgroundDictationHarness(hearing: [])

    let outcome = await harness.press(harness.identity())

    #expect(outcome == .logged(logged235, at: firstSet))
    #expect(harness.liveActivity.readbacks == [.logged("235×5 @7", to: try harness.squat(set: 1))])
    #expect(try harness.app.session(nil).exercises[0].sets[0].setLog == "235x5@7")
    #expect(try await harness.app.sheet(tab: nil).cells["K15"] == "235x5@7")
    #expect(try harness.app.sync.fetchPendingWriteRecords().isEmpty)
    #expect(harness.restTimer.interval != nil)
    #expect(harness.signIn.restores == 1)
    let session = try #require(harness.app.workout.currentSession)
    #expect(harness.focus.activeSet(in: session)?.setID == secondSet)
    guard case .rest(let rest) = harness.liveActivity.subjects.last else {
        Issue.record("Logged showed \(String(describing: harness.liveActivity.subjects.last)), not the rest")
        return
    }
    #expect(rest.target?.setID == secondSet)
    #expect(rest.restStartDate == harness.restTimer.interval?.start)
}

/// The readback holds with no chip under the thumb, so the second tap of a double tap cannot log
/// the next Set. Then the Lock Screen offers the Set the card moved to.
@MainActor
@Test func theNextSetsCardWaitsOutTheReadback() async throws {
    let harness = try await BackgroundDictationHarness(hearing: [])
    let chips = harness.chips
    let identity = harness.identity()

    let run = Task { await chips.logSet(setIdentity: identity, reps: 5, rpe: "7") }
    await harness.clock.waitUntilSleeping(
        until: harness.clock.now + LockScreenPress.readbackHold,
        orRecord: "The readback never held"
    )
    #expect(harness.liveActivity.replacements.isEmpty)
    await waitUntil(
        { (try? harness.app.sync.fetchPendingWriteRecords().isEmpty) == true },
        orRecord: "The flush never landed"
    )

    harness.clock.advance(by: LockScreenPress.readbackHold)
    #expect(await run.value == .logged(logged235, at: firstSet))

    let replacement = try #require(harness.liveActivity.replacements.first)
    #expect(replacement.readback == .logged("235×5 @7", to: try harness.squat(set: 1)))
    #expect(replacement.card.target?.setID == secondSet)
    #expect(replacement.card.restEndDate == harness.restTimer.interval?.end)
    #expect(replacement.card.pendingWrites == 0, "the flush landed during the hold")
    #expect(harness.liveActivity.refreshes.isEmpty)
}

/// A slow flush must not keep the readback on screen past its hold.
@MainActor
@Test func theNextSetsCardShowsWhileTheFlushIsStillGoing() async throws {
    let sheet = HeldWriteSheetsClient()
    let harness = try await BackgroundDictationHarness(hearing: [], sheet: sheet)
    let chips = harness.chips
    let identity = harness.identity()

    let run = Task { await chips.logSet(setIdentity: identity, reps: 5, rpe: "7") }
    await sheet.waitUntilHeld(orRecord: "The flush never reached the Sheet")
    await harness.clock.waitUntilSleeping(
        until: harness.clock.now + LockScreenPress.readbackHold,
        orRecord: "The readback never held"
    )
    harness.clock.advance(by: LockScreenPress.readbackHold)
    await waitUntil({ !harness.liveActivity.replacements.isEmpty }, orRecord: "The card waited for the flush")

    sheet.release()
    #expect(await run.value == .logged(logged235, at: firstSet))
    #expect(try await harness.app.sheet(tab: nil).cells["K15"] == "235x5@7")
}

/// A locked phone has no header, so the card counts a write the Sheet does not have yet, and
/// stops once a slow flush lands it.
@MainActor
@Test func theCardCountsAWriteUntilTheFlushLandsIt() async throws {
    let sheet = HeldWriteSheetsClient()
    let harness = try await BackgroundDictationHarness(hearing: [], sheet: sheet)
    let chips = harness.chips
    let identity = harness.identity()

    let run = Task { await chips.logSet(setIdentity: identity, reps: 5, rpe: "7") }
    await sheet.waitUntilHeld(orRecord: "The flush never reached the Sheet")
    await harness.clock.waitUntilSleeping(
        until: harness.clock.now + LockScreenPress.readbackHold,
        orRecord: "The readback never held"
    )
    harness.clock.advance(by: LockScreenPress.readbackHold)
    await waitUntil({ !harness.liveActivity.replacements.isEmpty }, orRecord: "The card waited for the flush")
    #expect(harness.liveActivity.replacements.first?.card.pendingWrites == 1)

    sheet.release()
    #expect(await run.value == .logged(logged235, at: firstSet))
    #expect(harness.liveActivity.refreshes.map(\.pendingWrites) == [0])
}

@MainActor
@Test func theSameChipTwiceWritesOnceAndKeepsTheReadback() async throws {
    let harness = try await BackgroundDictationHarness(hearing: [])
    let identity = harness.identity()
    _ = await harness.press(identity)
    let shown = harness.liveActivity.readbacks

    let outcome = await harness.chips.logSet(setIdentity: identity, reps: 5, rpe: "7")

    #expect(outcome == .sameSetLog(at: firstSet))
    #expect(harness.liveActivity.readbacks == shown)
    #expect(harness.signIn.restores == 1)
    #expect(try harness.app.session(nil).exercises[0].sets[0].setLog == "235x5@7")
}

@MainActor
@Test func anotherChipOnALoggedSetKeepsItsSetLogAndSaysSo() async throws {
    let harness = try await BackgroundDictationHarness(hearing: [])
    let identity = harness.identity()
    _ = await harness.press(identity)

    let outcome = await harness.press(identity, rpe: "8")

    #expect(outcome == .notLogged(.setSettled(setLog: "235×5 @7", set: try harness.squat(set: 1))))
    #expect(harness.liveActivity.readbacks.last == .settled(setLog: "235×5 @7", try harness.squat(set: 1)))
    #expect(try harness.app.session(nil).exercises[0].sets[0].setLog == "235x5@7")
}

/// The card moved past a Skipped Set elsewhere, so a chip for it finds nothing to log.
@MainActor
@Test func aChipOnASkippedSetWritesNothingAndSaysSo() async throws {
    let harness = try await BackgroundDictationHarness(hearing: [])
    let set = try harness.app.resolveSet(try #require(SetAddress("w1d1.e0.s0")))
    try harness.app.workout.skip(set)

    let outcome = await harness.press(harness.identity())

    #expect(outcome == .notLogged(.setSettled(setLog: nil, set: try harness.squat(set: 1))))
    #expect(harness.liveActivity.readbacks.last == .settled(setLog: nil, try harness.squat(set: 1)))
}

@MainActor
@Test func aChipForASetTheCardMovedPastWritesNothingAndSaysSo() async throws {
    let harness = try await BackgroundDictationHarness(hearing: [])
    let session = try #require(harness.app.workout.currentSession)
    harness.focus.reset(to: session)
    harness.focus.focus(on: try #require(SessionSetOrder.orderedSets(in: session).first { $0.setID == secondSet }).set)

    let outcome = await harness.press(harness.identity())

    #expect(outcome == .notLogged(.cardMovedOn))
    #expect(harness.liveActivity.readbacks == [.notLogged("The card moved to another Set")])
    try harness.expectNothingWritten()
}

@MainActor
@Test func aChipForASetTheSheetNoLongerHoldsWritesNothingAndSaysSo() async throws {
    let harness = try await BackgroundDictationHarness(hearing: [])

    let outcome = await harness.press(harness.identity(of: ActiveSetID(exerciseOrder: 99, setIndex: 0)))

    #expect(outcome == .notLogged(.cardMovedOn))
    try harness.expectNothingWritten()
}

@MainActor
@Test func aChipFromAnotherSessionWritesNothingAndSaysSo() async throws {
    let harness = try await BackgroundDictationHarness(hearing: [])

    let outcome = await harness.press(harness.identity(blockTab: "Block 26"))

    #expect(outcome == .notLogged(.sessionChanged))
    #expect(harness.liveActivity.readbacks == [.notLogged("The Session changed. Open to log")])
    try harness.expectNothingWritten()
}

@MainActor
@Test(arguments: [("not an identity", 5, "7"), ("identity", 5, "7.25"), ("identity", 5, ""), ("identity", 0, "7"), ("identity", 101, "7")])
func aPressThisBuildCannotReadWritesNothing(identity: String, reps: Int, rpe: String) async throws {
    let harness = try await BackgroundDictationHarness(hearing: [])
    let pressed = identity == "identity" ? harness.identity() : identity

    let outcome = await harness.press(pressed, reps: reps, rpe: rpe)

    #expect(outcome == .notLogged(.unreadable))
    try harness.expectNothingWritten()
}

@MainActor
@Test func aChipWithNoSessionToLogIntoSaysSo() async throws {
    let harness = try await BackgroundDictationHarness(hearing: [], selectingSpreadsheet: false)

    let outcome = await harness.press(harness.identity())

    #expect(outcome == .notLogged(.noCurrentSession))
    #expect(harness.liveActivity.noSets == [.noCurrentSession])
}

/// The stage's card holds another weight than the Lock Screen showed, which only the athlete can
/// settle, since the Lock Screen cannot choose one.
@MainActor
@Test func aChipOverACardWhoseWeightChangedWritesNothingAndSaysSo() async throws {
    let harness = try await BackgroundDictationHarness(hearing: [])
    harness.focus.cardShows(SetLogDraft(weight: .pounds(240), reps: nil, rpe: nil), for: firstSet)

    let outcome = await harness.press(harness.identity())

    #expect(outcome == .notLogged(.cardChanged))
    #expect(harness.liveActivity.readbacks == [.notLogged("The weight changed. Open to log")])
    try harness.expectNothingWritten()
}

/// The card's Reps and RPE are a pre-fill, and the tapped chips are the athlete's report.
@MainActor
@Test func aChipOverACardShowingTheSameWeightLogsTheTappedRepsAndRPE() async throws {
    let harness = try await BackgroundDictationHarness(hearing: [])
    harness.focus.cardShows(SetLogDraft(weight: .pounds(235), reps: 3, rpe: .nine), for: firstSet)

    let outcome = await harness.press(harness.identity())

    #expect(outcome == .logged(logged235, at: firstSet))
}

/// After the system ended the app no card has reported anything, so what the Lock Screen showed
/// stands, even where it differs from the first pre-fill.
@MainActor
@Test func aChipWithNoCardReportLogsWhatTheLockScreenShowed() async throws {
    let harness = try await BackgroundDictationHarness(hearing: [])

    let outcome = await harness.press(harness.identity(weight: .pounds(999)))

    #expect(outcome == .logged(SetLog(weight: .pounds(999), reps: 5, rpe: .seven), at: firstSet))
}

@MainActor
@Test func aChipWhileTheMicListensLeavesTheSetToTheMic() async throws {
    let harness = try await BackgroundDictationHarness(
        transcriber: OpenMicTranscriber(holdingStart: false, failingToStart: nil),
        reading: .heard("", segments: [])
    )
    let session = try #require(harness.app.workout.currentSession)
    let set = try #require(harness.focus.activeSet(in: session))
    let history = harness.app.lastPerformed.snapshot
    let context = { SpokenSetContext(for: set.set, history: history) }
    let listening = Task { await harness.dictation.listenUntilQuiet(for: set.setID, on: .headless, in: context) }
    await waitUntil({ harness.dictation.state.pressSetID != nil }, orRecord: "The mic never opened")
    // A press that logged past the open mic holds its readback, and the mic it overtook never stops,
    // so the press runs on a clock that moves and the outcome must hold before the mic is closed.
    let chips = LockScreenPress(
        app: harness.app,
        dictation: harness.dictation,
        focus: harness.focus,
        restTimer: harness.restTimer,
        liveActivity: harness.liveActivity,
        rows: LockScreenRows(),
        signIn: harness.signIn,
        clock: ContinuousListeningClock()
    )

    let outcome = await chips.logSet(setIdentity: harness.identity(), reps: 5, rpe: "7")

    try #require(outcome == .micBusy)
    #expect(await chips.chooseReps(setIdentity: harness.identity(), reps: 6) == .micBusy)
    #expect(harness.liveActivity.readbacks.isEmpty)
    #expect(harness.liveActivity.refreshes.isEmpty)
    #expect(try harness.app.sync.fetchPendingWriteRecords().isEmpty)
    await harness.dictation.cancel()
    _ = await listening.value
}

/// With no rest to start the activity ends on the readback, which stays to be read, so nothing
/// holds the intent and no card replaces it.
@MainActor
@Test func theSessionsLastSetEndsOnTheReadback() async throws {
    let harness = try await BackgroundDictationHarness(hearing: [])
    let session = try #require(harness.app.workout.currentSession)
    let last = try #require(SessionSetOrder.orderedSets(in: session).last)
    for position in SessionSetOrder.orderedSets(in: session).dropLast() {
        try harness.app.workout.log(position.set, as: logged235)
    }
    harness.focus.reset(to: session)

    let outcome = await harness.chips.logSet(setIdentity: harness.identity(of: last.setID), reps: 5, rpe: "7")

    #expect(outcome == .logged(logged235, at: last.setID))
    #expect(harness.liveActivity.replacements.isEmpty)
    guard case .set = harness.liveActivity.subjects.last else {
        Issue.record("The Session's last Set showed \(String(describing: harness.liveActivity.subjects.last))")
        return
    }
}
