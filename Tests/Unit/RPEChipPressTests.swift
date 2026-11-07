import Foundation
import Testing

@testable import WorkoutTracker

private let firstSet = ActiveSetID(exerciseOrder: 0, setIndex: 0)
private let secondSet = ActiveSetID(exerciseOrder: 0, setIndex: 1)
private let logged235 = SetLog(weight: .pounds(235), reps: 5, rpe: .seven)

extension BackgroundDictationHarness {
    fileprivate var chips: RPEChipPress {
        RPEChipPress(
            app: app,
            dictation: dictation,
            focus: focus,
            restTimer: restTimer,
            liveActivity: liveActivity,
            signIn: signIn,
            clock: clock
        )
    }

    /// What a chip the Lock Screen drew for `setID` hands back.
    fileprivate func identity(
        of setID: ActiveSetID = firstSet,
        weight: Weight = .pounds(235),
        reps: Int = 5,
        blockTab: String = "Block 27"
    ) -> String {
        LoggableSetIdentity(
            session: SessionCoordinate(blockTab: blockTab, address: SessionAddress(week: 1, day: 1)),
            setID: setID,
            weight: weight,
            reps: reps
        ).storageValue
    }

    /// Presses a chip and lets the readback's hold run out.
    fileprivate func press(_ identity: String, rpe: String = "7") async -> RPEChipPress.Outcome {
        let chips = self.chips
        let run = Task { await chips.run(setIdentity: identity, rpe: rpe) }
        let shown = liveActivity.shown.count + liveActivity.noSets.count
        await waitUntil({ liveActivity.shown.count + liveActivity.noSets.count > shown }, orRecord: "It never read back")
        if liveActivity.restContent != nil {
            let hold = RPEChipPress.readbackHold
            await clock.waitUntilSleeping(until: clock.now + hold, orRecord: "The readback never held")
            clock.advance(by: hold)
        }
        return await run.value
    }

}

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

    let run = Task { await chips.run(setIdentity: identity, rpe: "7") }
    await harness.clock.waitUntilSleeping(
        until: harness.clock.now + RPEChipPress.readbackHold,
        orRecord: "The readback never held"
    )
    #expect(harness.liveActivity.replacements.isEmpty)
    await waitUntil(
        { (try? harness.app.sync.fetchPendingWriteRecords().isEmpty) == true },
        orRecord: "The flush never landed"
    )

    harness.clock.advance(by: RPEChipPress.readbackHold)
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

    let run = Task { await chips.run(setIdentity: identity, rpe: "7") }
    await sheet.waitUntilHeld(orRecord: "The flush never reached the Sheet")
    await harness.clock.waitUntilSleeping(
        until: harness.clock.now + RPEChipPress.readbackHold,
        orRecord: "The readback never held"
    )
    harness.clock.advance(by: RPEChipPress.readbackHold)
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

    let run = Task { await chips.run(setIdentity: identity, rpe: "7") }
    await sheet.waitUntilHeld(orRecord: "The flush never reached the Sheet")
    await harness.clock.waitUntilSleeping(
        until: harness.clock.now + RPEChipPress.readbackHold,
        orRecord: "The readback never held"
    )
    harness.clock.advance(by: RPEChipPress.readbackHold)
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

    let outcome = await harness.chips.run(setIdentity: identity, rpe: "7")

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
    #expect(harness.liveActivity.readbacks == [.notLogged("The Session changed. Unlock to log")])
    try harness.expectNothingWritten()
}

@MainActor
@Test(arguments: [("not an identity", "7"), ("identity", "7.25"), ("identity", "")])
func aPressThisBuildCannotReadWritesNothing(identity: String, rpe: String) async throws {
    let harness = try await BackgroundDictationHarness(hearing: [])
    let pressed = identity == "identity" ? harness.identity() : identity

    let outcome = await harness.press(pressed, rpe: rpe)

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

/// The stage's card and the Lock Screen disagree, which only the athlete can settle.
@MainActor
@Test func aChipOverACardThatChangedWritesNothingAndSaysSo() async throws {
    let harness = try await BackgroundDictationHarness(hearing: [])
    harness.focus.cardShows(SetLogDraft(weight: .pounds(240), reps: 5, rpe: nil), for: firstSet)

    let outcome = await harness.press(harness.identity())

    #expect(outcome == .notLogged(.cardChanged))
    #expect(harness.liveActivity.readbacks == [.notLogged("The card changed. Unlock to log")])
    try harness.expectNothingWritten()
}

/// The card reports no RPE until the athlete picks one, and the tapped chip is the report.
@MainActor
@Test func aChipOverACardShowingTheSameValuesLogsTheTappedRPE() async throws {
    let harness = try await BackgroundDictationHarness(hearing: [])
    harness.focus.cardShows(SetLogDraft(weight: .pounds(235), reps: 5, rpe: .nine), for: firstSet)

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

    let outcome = await harness.chips.run(setIdentity: harness.identity(), rpe: "7")

    #expect(outcome == .micBusy)
    #expect(harness.liveActivity.readbacks.isEmpty)
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

    let outcome = await harness.chips.run(setIdentity: harness.identity(of: last.setID), rpe: "7")

    #expect(outcome == .logged(logged235, at: last.setID))
    #expect(harness.liveActivity.replacements.isEmpty)
    guard case .set = harness.liveActivity.subjects.last else {
        Issue.record("The Session's last Set showed \(String(describing: harness.liveActivity.subjects.last))")
        return
    }
}
