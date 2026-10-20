import Foundation
import Testing

@testable import WorkoutTracker

private let frozenNow = Date(timeIntervalSince1970: 1_780_000_000)
private let firstSet = ActiveSetID(exerciseOrder: 0, setIndex: 0)
private let window = SetDictation.silenceWindow
/// The bound a hung flush holds a press to, spelled out: the result shows before it, and a
/// longer wait keeps the recording session open past what the athlete expects of a press.
private let flushWait = Duration.seconds(10)
private let logged235 = SetLog(weight: .pounds(235), reps: 5, rpe: .seven)

@MainActor
@Test func theCardsMicListeningLeavesTheSetToTheCard() async throws {
    let harness = try await BackgroundDictationHarness(hearing: ["235 for 5 at 7"])
    #expect(harness.dictation.start(for: firstSet))

    let outcome = await harness.background.run()

    #expect(outcome == .noSetToLog(.micBusy))
    #expect(harness.liveActivity.readbacks.isEmpty, "the card shows its own listening")
    #expect(harness.liveActivity.noSets.isEmpty)
    await harness.dictation.cancel()
    try harness.expectNothingWritten()
}

@MainActor
@Test func inASupersetItLogsTheSetTheCardShowsAndAlternatesAsTheCardDoes() async throws {
    let harness = try await BackgroundDictationHarness(hearing: ["235 for 5 at 7"])
    let session = try #require(harness.app.workout.currentSession)
    let stage = harness.stage(on: session)
    let squat = try #require(session.exercises.first { $0.order == 0 })
    let rdl = try #require(session.exercises.first { $0.order == 1 })
    #expect(stage.createSuperset(from: squat, to: rdl, in: session))
    stage.log(try #require(squat.sets.first { $0.index == 0 }), as: SetLog(weight: .pounds(225), reps: 5, rpe: .seven))
    let cardShows = try #require(stage.activeSetID)
    #expect(cardShows == ActiveSetID(exerciseOrder: rdl.order, setIndex: 0), "the Superset alternates to its other side")

    let first = await harness.runUntilQuiet()

    #expect(first == .logged(SetLog(weight: .pounds(235), reps: 5, rpe: .seven), at: cardShows))
    #expect(rdl.sets.first { $0.index == 0 }?.state == .logged)
    #expect(squat.sets.first { $0.index == 1 }?.state == .pending)
    #expect(stage.activeSetID == ActiveSetID(exerciseOrder: squat.order, setIndex: 1), "the card moved on as a tap would")
    guard case .rest(let rest) = harness.liveActivity.subjects.last else {
        Issue.record("Logged showed \(String(describing: harness.liveActivity.subjects.last)), not the rest")
        return
    }
    #expect(rest.target?.setID == ActiveSetID(exerciseOrder: squat.order, setIndex: 1), "the rest leads where the card goes")
    #expect(rest.restEndDate == frozenNow.addingTimeInterval(harness.app.settings.supersetRestDuration.timeInterval))
    #expect(harness.restTimer.interval?.kind == .superset, "the stage's rest is the Superset's")
    #expect(harness.restTimer.interval?.end == rest.restEndDate)

    let second = await harness.runUntilQuiet()

    #expect(second == .logged(SetLog(weight: .pounds(235), reps: 5, rpe: .seven), at: ActiveSetID(exerciseOrder: squat.order, setIndex: 1)))
    #expect(stage.activeSetID == ActiveSetID(exerciseOrder: rdl.order, setIndex: 1))
}

@MainActor
@Test func itLogsTheSetTheAthleteFocusedOnTheCard() async throws {
    let harness = try await BackgroundDictationHarness(hearing: ["235 for 5 at 7"])
    let session = try #require(harness.app.workout.currentSession)
    let stage = harness.stage(on: session)
    let squat = try #require(session.exercises.first { $0.order == 0 })
    let rdl = try #require(session.exercises.first { $0.order == 1 })
    let rdlFirst = try #require(rdl.sets.first { $0.index == 0 })
    stage.focus(on: rdlFirst)

    let outcome = await harness.runUntilQuiet()

    #expect(outcome == .logged(SetLog(weight: .pounds(235), reps: 5, rpe: .seven), at: ActiveSetID(exerciseOrder: rdl.order, setIndex: 0)))
    #expect(rdlFirst.state == .logged)
    #expect(squat.sets.allSatisfy { $0.isPending }, "the first Pending Set was not the card's")
}

@MainActor
@Test func withTheStageOnAnotherSessionItLogsTheCurrentSessionsFirstPendingSet() async throws {
    let harness = try await BackgroundDictationHarness(hearing: ["235 for 5 at 7"])
    let current = try #require(harness.app.workout.currentSession)
    harness.app.workout.show(SessionAddress(week: 1, day: 2))
    let browsed = try #require(harness.app.workout.viewedSession)
    #expect(browsed !== current)
    let stage = harness.stage(on: browsed)
    let browsedExercise = try #require(browsed.exercises.first { $0.order == 0 })
    stage.focus(on: try #require(browsedExercise.sets.first { $0.index == 1 }))

    let outcome = await harness.runUntilQuiet()

    #expect(outcome == .logged(SetLog(weight: .pounds(235), reps: 5, rpe: .seven), at: firstSet))
    #expect(current.exercises.first { $0.order == 0 }?.sets.first { $0.index == 0 }?.state == .logged)
    #expect(browsed.exercises.allSatisfy { $0.sets.allSatisfy { $0.isPending } }, "the browsed Session took nothing")
    #expect(stage.activeSetID == ActiveSetID(exerciseOrder: 0, setIndex: 1), "the browsed card stays where it was")
}

/// A second press can arrive while the first's readback is still being drawn, so the card moves
/// on with the write itself, never after it shows.
@MainActor
@Test func theCardMovesPastTheSetWithTheWriteBeforeTheReadbackShows() async throws {
    let harness = try await BackgroundDictationHarness(hearing: ["235 for 5 at 7"])
    let session = try #require(harness.app.workout.currentSession)
    let stage = harness.stage(on: session)
    let next = ActiveSetID(exerciseOrder: 0, setIndex: 1)
    var cardWhileShowing: ActiveSetVisualFocusOwner?
    harness.liveActivity.whileShowing = { readback in
        guard case .logged = readback else { return }
        cardWhileShowing = harness.focus.visualFocusOwner
    }

    _ = await harness.runUntilQuiet()

    #expect(cardWhileShowing == .activeSet(next), "the card is on the next Set as the readback shows")
    #expect(stage.activeSetID == next)
    #expect(!harness.focus.isHoldingSpokenWrite, "no card held a Set written with the phone locked")
    #expect(harness.dictation.state == .idle)
}

@MainActor
@Test func aStageWhoseActiveSetWasLoggedElsewhereListensForTheNextPendingSet() async throws {
    let harness = try await BackgroundDictationHarness(hearing: ["235 for 5 at 7"])
    let session = try #require(harness.app.workout.currentSession)
    _ = harness.stage(on: session)
    let set = try #require(session.exercises.first { $0.order == 0 }?.sets.first { $0.index == 0 })
    try harness.app.workout.log(set, as: SetLog(weight: .pounds(225), reps: 5, rpe: .six))

    let outcome = await harness.runUntilQuiet()

    #expect(outcome == .logged(logged235, at: ActiveSetID(exerciseOrder: 0, setIndex: 1)))
    #expect(harness.liveActivity.noSets.isEmpty, "Pending Sets remain, so the press listened")
}

/// The card keeps a Set its mic wrote for the athlete to glance at and undo. A press with the
/// phone locked says they have moved on, so the hold ends as a touch of the card would, and the
/// next Set takes the write; no card stays held while another Set is written.
@MainActor
@Test func aPressWhileTheCardHoldsASpokenWriteEndsTheHoldAndLogsTheNextSet() async throws {
    let harness = try await BackgroundDictationHarness(hearing: ["235 for 5 at 7"])
    let session = try #require(harness.app.workout.currentSession)
    let stage = harness.stage(on: session)
    let first = try #require(session.exercises.first { $0.order == 0 }?.sets.first { $0.index == 0 })
    #expect(harness.focus.advanceAfterSpokenWrite(first, in: session, holding: true))
    try harness.app.workout.log(first, as: SetLog(weight: .pounds(225), reps: 5, rpe: .six))
    #expect(harness.focus.isHoldingSpokenWrite)

    let outcome = await harness.runUntilQuiet()

    let second = ActiveSetID(exerciseOrder: 0, setIndex: 1)
    #expect(outcome == .logged(logged235, at: second))
    #expect(!harness.focus.isHoldingSpokenWrite)
    #expect(harness.focus.visualFocusOwner == .activeSet(ActiveSetID(exerciseOrder: 0, setIndex: 2)), "the card moved past both Sets")
    #expect(stage.activeSetID == ActiveSetID(exerciseOrder: 0, setIndex: 2))
}

/// What the athlete dialled on the card before locking the phone fills what they leave unsaid, as
/// it would had they let go of the card's own mic.
@MainActor
@Test func aPressFillsWhatIsUnsaidFromWhatTheCardShowsForTheSet() async throws {
    let harness = try await BackgroundDictationHarness(hearing: ["for 5 at 8"])
    let session = try #require(harness.app.workout.currentSession)
    let stage = harness.stage(on: session)
    let first = try #require(session.exercises.first { $0.order == 0 }?.sets.first { $0.index == 0 })
    stage.cardShows(SetLogDraft(weight: .pounds(245), reps: 5, rpe: .six), for: first)

    let outcome = await harness.runUntilQuiet()

    #expect(outcome == .logged(SetLog(weight: .pounds(245), reps: 5, rpe: .eight), at: firstSet))
    #expect(first.setLog == SetLog(weight: .pounds(245), reps: 5, rpe: .eight))
}

@MainActor
@Test func whatTheCardShowedForAnotherSetFillsNothing() async throws {
    let harness = try await BackgroundDictationHarness(hearing: ["for 5 at 8"])
    let session = try #require(harness.app.workout.currentSession)
    let stage = harness.stage(on: session)
    let second = try #require(session.exercises.first { $0.order == 0 }?.sets.first { $0.index == 1 })
    stage.cardShows(SetLogDraft(weight: .pounds(245), reps: 5, rpe: .six), for: second)

    let outcome = await harness.runUntilQuiet()

    #expect(outcome == .notLogged(.missingValues(SetLogDraft(weight: nil, reps: 5, rpe: .eight), heard: "for 5 at 8"), at: firstSet))
    try harness.expectNothingWritten()
}

@MainActor
@Test func theCardTakingTheMicWhileListeningShowsTakesTheReadbackOff() async throws {
    let harness = try await BackgroundDictationHarness(hearing: ["235 for 5 at 7"])
    harness.liveActivity.whileShowing = { readback in
        if readback == .listening { harness.dictation.start(for: firstSet) }
    }

    let outcome = await harness.background.run()

    #expect(outcome == .noSetToLog(.micBusy))
    #expect(harness.liveActivity.readbacks == [.listening])
    #expect(harness.liveActivity.withdrawals == 1, "Listening… does not outlive the press")
    #expect(harness.liveActivity.finalReadback == nil)
    await harness.dictation.cancel()
    try harness.expectNothingWritten()
}

@MainActor
@Test func aPressCancelledWhileListeningTakesTheReadbackOff() async throws {
    let transcriber = HeldSetTranscriber(candidates: ["235 for 5 at 7"])
    let harness = try await BackgroundDictationHarness(transcriber: transcriber)

    let run = Task { await harness.background.run() }
    await transcriber.starting.waitUntilHeld(orRecord: "The transcriber never started")
    transcriber.starting.release()
    await harness.clock.waitUntilSleeping(until: window, orRecord: "It never started listening")
    await harness.dictation.cancel()
    harness.clock.advance(by: window)

    #expect(await run.value == .noSetToLog(.micBusy))
    #expect(harness.liveActivity.withdrawals == 1, "Listening… does not outlive the press")
    #expect(harness.liveActivity.finalReadback == nil)
    try harness.expectNothingWritten()
}

@MainActor
@Test func aSetLoggedElsewhereWhileListeningTakesNothingAndSaysSo() async throws {
    let harness = try await BackgroundDictationHarness(hearing: ["235 for 5 at 7"])
    let session = try #require(harness.app.workout.currentSession)
    let set = try #require(session.exercises.first { $0.order == 0 }?.sets.first { $0.index == 0 })
    let onTheCard = SetLog(weight: .pounds(225), reps: 5, rpe: .six)

    let run = Task { await harness.background.run() }
    await harness.clock.waitUntilSleeping(until: window, orRecord: "It never started listening")
    try harness.app.workout.log(set, as: onTheCard)
    harness.clock.advance(by: window)

    #expect(await run.value == .notLogged(.setChanged, at: firstSet))
    #expect(harness.liveActivity.finalReadback == .notLogged("The Set changed while listening"))
    #expect(set.setLog == onTheCard, "what was heard does not overwrite the Set")
    #expect(try harness.app.sync.fetchPendingWriteRecords().count == 1, "only the card's write is queued")
    #expect(harness.signIn.restores == 0, "nothing of this press to flush")
}

@MainActor
@Test func theSignInIsRestoredBeforeTheFlushOnlyWhenNoSceneDid() async throws {
    let cold = try await BackgroundDictationHarness(hearing: ["235 for 5 at 7"])
    _ = await cold.runUntilQuiet()
    #expect(cold.signIn.restores == 1)
    #expect(cold.app.settings.isSignedIn)

    let warm = try await BackgroundDictationHarness(hearing: ["235 for 5 at 7"])
    warm.app.settings.isSignedIn = true
    _ = await warm.runUntilQuiet()
    #expect(warm.signIn.restores == 0)
}

@MainActor
@Test func aFlushThatHangsReturnsAtTheDeadlineWithTheWriteQueuedAndRunsOn() async throws {
    let sheet = HeldWriteSheetsClient()
    let harness = try await BackgroundDictationHarness(hearing: ["235 for 5 at 7"], sheet: sheet)

    let run = Task { await harness.background.run() }
    await harness.clock.waitUntilSleeping(until: window, orRecord: "It never started listening")
    harness.clock.advance(by: window)
    await harness.clock.waitUntilSleeping(until: window + flushWait, orRecord: "The flush was never bounded")
    await sheet.waitUntilHeld(orRecord: "The flush never reached the Sheet")
    #expect(
        harness.liveActivity.readbacks == [.listening, .logged("235×5 @7", to: try harness.squat(set: 1))],
        "the result shows before the flush"
    )
    harness.clock.advance(by: flushWait)

    #expect(await run.value == .logged(SetLog(weight: .pounds(235), reps: 5, rpe: .seven), at: firstSet))
    #expect(try harness.app.sync.fetchPendingWriteRecords().count == 1, "the write stays queued")

    sheet.release()
    _ = await harness.background.flushing?.value
    #expect(try await harness.app.sheet(tab: nil).cells["K15"] == "235x5@7", "the flush ran on past the deadline")
}
