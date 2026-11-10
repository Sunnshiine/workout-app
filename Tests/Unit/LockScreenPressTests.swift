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
    #expect(harness.liveActivity.islandReadbacks.map(\.readback) == [.logged("235×5 @7", to: try harness.squat(set: 1))])
    #expect(harness.liveActivity.readbacks.isEmpty, "the card reads nothing back")
    #expect(try harness.app.session(nil).exercises[0].sets[0].setLog == "235x5@7")
    #expect(try await harness.app.sheet(tab: nil).cells["K15"] == "235x5@7")
    #expect(try harness.app.sync.fetchPendingWriteRecords().isEmpty)
    #expect(harness.restTimer.interval != nil)
    #expect(harness.signIn.restores == 1)
    let session = try #require(harness.app.workout.currentSession)
    #expect(harness.focus.activeSet(in: session)?.setID == secondSet)
    let rest = try #require(harness.liveActivity.islandReadbacks.last?.card)
    #expect(rest.target?.setID == secondSet)
    #expect(rest.face == .rest)
    #expect(rest.restStartDate == harness.restTimer.interval?.start)
}

/// Once its hold is over the island's readback goes, and the next Set's card stays as it was.
@MainActor
@Test func theIslandReadsTheSetLogBackOverTheNextSetsCard() async throws {
    let harness = try await BackgroundDictationHarness(hearing: [])
    let chips = harness.chips
    let identity = harness.identity()

    let run = Task { await chips.logSet(setIdentity: identity, reps: 5, rpe: "7") }
    await harness.clock.waitUntilSleeping(
        until: harness.clock.now + LockScreenPress.readbackHold,
        orRecord: "The readback never held"
    )
    #expect(harness.liveActivity.islandReadbacks.first?.card.target?.setID == secondSet)
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
    #expect(replacement.card.face == .rest)
    #expect(replacement.card.restEndDate == harness.restTimer.interval?.end)
    #expect(replacement.card.pendingWrites == 0, "the flush landed during the hold")
    #expect(harness.liveActivity.refreshes.isEmpty)
}

/// A slow flush keeps neither the next Set's card off the Lock Screen nor the readback on the
/// island past its hold.
@MainActor
@Test func theNextSetsCardShowsWhileTheFlushIsStillGoing() async throws {
    let sheet = HeldWriteSheetsClient()
    let harness = try await BackgroundDictationHarness(hearing: [], sheet: sheet)
    let chips = harness.chips
    let identity = harness.identity()

    let run = Task { await chips.logSet(setIdentity: identity, reps: 5, rpe: "7") }
    await sheet.waitUntilHeld(orRecord: "The flush never reached the Sheet")
    #expect(harness.liveActivity.islandReadbacks.first?.card.target?.setID == secondSet)
    await harness.clock.waitUntilSleeping(
        until: harness.clock.now + LockScreenPress.readbackHold,
        orRecord: "The readback never held"
    )
    harness.clock.advance(by: LockScreenPress.readbackHold)
    await waitUntil({ !harness.liveActivity.replacements.isEmpty }, orRecord: "The readback waited for the flush")

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
    #expect(harness.liveActivity.islandReadbacks.first?.card.pendingWrites == 1)
    await harness.clock.waitUntilSleeping(
        until: harness.clock.now + LockScreenPress.readbackHold,
        orRecord: "The readback never held"
    )
    harness.clock.advance(by: LockScreenPress.readbackHold)
    await waitUntil({ !harness.liveActivity.replacements.isEmpty }, orRecord: "The readback waited for the flush")
    #expect(harness.liveActivity.replacements.first?.card.pendingWrites == 1)

    sheet.release()
    #expect(await run.value == .logged(logged235, at: firstSet))
    #expect(harness.liveActivity.refreshes.map(\.pendingWrites) == [0])
}

@MainActor
@Test func theSameChipTwiceWritesOnceAndLeavesTheNextSetsCard() async throws {
    let harness = try await BackgroundDictationHarness(hearing: [])
    let identity = harness.identity()
    _ = await harness.press(identity)
    let card = harness.liveActivity.restContent

    let outcome = await harness.chips.logSet(setIdentity: identity, reps: 5, rpe: "7")

    #expect(outcome == .sameSetLog(at: firstSet))
    #expect(harness.liveActivity.restContent == card)
    #expect(harness.liveActivity.islandReadbacks.count == 1)
    #expect(harness.liveActivity.readbacks.isEmpty)
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

/// With no rest running, the recording has the Live Activity to itself, and a readback would end
/// the activity the system records under. No chip shows over it, so only a stale tap gets here.
@MainActor
@Test func aChipWhileTheMicListensOverNoRestLeavesTheMicItsActivity() async throws {
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
        settle: RPEFaceSettle(),
        signIn: harness.signIn,
        clock: ContinuousListeningClock()
    )

    let outcome = await chips.logSet(setIdentity: harness.identity(), reps: 5, rpe: "7")

    try #require(outcome == .notLogged(.micBusy(.headless)))
    #expect(await chips.turn(to: .rpe(reps: 6), pressing: harness.identity()) == .notLogged(.micBusy(.headless)))
    #expect(await chips.turn(to: .coachNote, pressing: nil) == .turned(to: .rest))
    #expect(harness.liveActivity.readbacks.isEmpty)
    #expect(harness.liveActivity.refreshes.isEmpty)
    #expect(try harness.app.sync.fetchPendingWriteRecords().isEmpty)
    await harness.dictation.cancel()
    _ = await listening.value
}

/// A tap as the Lock Screen's mic opens over the rest, before "Listening…" drew, says why it logged
/// nothing. The mic still listens, so "Listening…" comes back once the readback has been read.
@MainActor
@Test func aChipWhileTheLockScreensMicListensSaysSoAndListeningComesBack() async throws {
    let harness = try await BackgroundDictationHarness(
        transcriber: OpenMicTranscriber(holdingStart: false, failingToStart: nil),
        reading: .heard("", segments: [])
    )
    try harness.restRunning()
    let run = Task { await harness.background.run() }
    await waitUntil({ harness.dictation.state.pressSetID != nil }, orRecord: "The mic never opened")
    // The mic waits on the harness's clock, so the press holds its readback on a clock of its own.
    let clock = ManualListeningClock()
    let chips = LockScreenPress(
        app: harness.app,
        dictation: harness.dictation,
        focus: harness.focus,
        restTimer: harness.restTimer,
        liveActivity: harness.liveActivity,
        settle: RPEFaceSettle(),
        signIn: harness.signIn,
        clock: clock
    )
    let refusal = LiveActivityDictationContent.Readback.notLogged("The mic is listening. Say the Set")

    let press = Task { await chips.logSet(setIdentity: harness.identity(), reps: 5, rpe: "7") }
    await clock.waitUntilSleeping(until: clock.now + LockScreenPress.readbackHold, orRecord: "The readback never held")
    #expect(harness.liveActivity.readbacks == [.listening, refusal])
    clock.advance(by: LockScreenPress.readbackHold)

    #expect(await press.value == .notLogged(.micBusy(.headless)))
    #expect(harness.liveActivity.readbacks == [.listening, refusal, .listening])
    #expect(harness.liveActivity.replacements.isEmpty)
    try harness.expectNothingWritten()
    await harness.dictation.cancel()
    harness.clock.advance(by: SetDictation.silenceWindow)
    #expect(await run.value == .noSetToLog(.micBusy))
}

/// The card's mic in the app can still hold its press once the phone locks. The chip says why it
/// logged nothing, and the card comes back, since the Lock Screen never showed "Listening…".
@MainActor
@Test func aChipWhileTheAppsMicListensSaysSoAndTheCardComesBack() async throws {
    let harness = try await BackgroundDictationHarness(
        transcriber: OpenMicTranscriber(holdingStart: false, failingToStart: nil),
        reading: .heard("", segments: [])
    )
    try harness.restRunning()
    let session = try #require(harness.app.workout.currentSession)
    try #require(harness.dictation.start(for: try #require(harness.focus.activeSet(in: session)).setID))

    let outcome = await harness.press(harness.identity())

    #expect(outcome == .notLogged(.micBusy(.card)))
    #expect(harness.liveActivity.readbacks == [.notLogged("The app’s mic is listening. Open to log")])
    #expect(harness.liveActivity.replacements.count == 1)
    try harness.expectNothingWritten()
    await harness.dictation.cancel()
}

/// Two chips pressed at once on the Session's last Set: the first logs it, and the second finds no
/// Set left. It reads back what the Set holds, over that Set, as on any other Set.
@MainActor
@Test(arguments: [true, false])
func aStalePressOnTheSessionsLastSetSaysWhatTheSetHolds(onAnRPEChip: Bool) async throws {
    let harness = try await BackgroundDictationHarness(hearing: [])
    let session = try #require(harness.app.workout.currentSession)
    let sets = SessionSetOrder.orderedSets(in: session)
    let last = try #require(sets.last)
    for position in sets {
        try harness.app.workout.log(position.set, as: logged235)
    }
    harness.focus.reset(to: session)
    let identity = harness.identity(of: last.setID)

    let outcome =
        onAnRPEChip ? await harness.press(identity, rpe: "8") : await harness.turn(to: .rpe(reps: 6), pressing: identity)

    let written = LiveActivityDictationContent.WrittenSet(last, in: session)
    #expect(outcome == .notLogged(.setSettled(setLog: "235×5 @7", set: written)))
    #expect(harness.liveActivity.noSets.isEmpty)
    #expect(harness.liveActivity.readbacks == [.settled(setLog: "235×5 @7", written)])
    guard case .set(let shown) = harness.liveActivity.subjects.last else {
        Issue.record("The readback showed \(String(describing: harness.liveActivity.subjects.last))")
        return
    }
    #expect(shown.exerciseName == last.exercise.exerciseName.base)
}

/// A press that names no Set of the Session, once every Set is logged, has only that to say.
@MainActor
@Test func aPressNamingNoSetOfAFinishedSessionSaysNoSetIsLeft() async throws {
    let harness = try await BackgroundDictationHarness(hearing: [])
    let session = try #require(harness.app.workout.currentSession)
    for position in SessionSetOrder.orderedSets(in: session) {
        try harness.app.workout.log(position.set, as: logged235)
    }
    harness.focus.reset(to: session)

    let outcome = await harness.press(harness.identity(of: ActiveSetID(exerciseOrder: 99, setIndex: 0)))

    #expect(outcome == .notLogged(.cardMovedOn))
    #expect(harness.liveActivity.noSets == [.noSetLeft])
    #expect(harness.liveActivity.readbacks.isEmpty)
}

/// No rest follows the Session's last Set, so its card goes and nothing reads back in its place.
@MainActor
@Test func theSessionsLastSetTakesTheCardDown() async throws {
    let harness = try await BackgroundDictationHarness(hearing: [])
    let session = try #require(harness.app.workout.currentSession)
    let last = try #require(SessionSetOrder.orderedSets(in: session).last)
    for position in SessionSetOrder.orderedSets(in: session).dropLast() {
        try harness.app.workout.log(position.set, as: logged235)
    }
    harness.focus.reset(to: session)
    try harness.restRunning()

    let outcome = await harness.chips.logSet(setIdentity: harness.identity(of: last.setID), reps: 5, rpe: "7")

    #expect(outcome == .logged(logged235, at: last.setID))
    #expect(harness.liveActivity.endedRests == 1)
    #expect(harness.liveActivity.restContent == nil)
    #expect(harness.liveActivity.readbacks.isEmpty)
}
