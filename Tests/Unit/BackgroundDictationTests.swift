import Foundation
import Testing

@testable import WorkoutTracker

private let frozenNow = Date(timeIntervalSince1970: 1_780_000_000)
private let firstSet = ActiveSetID(exerciseOrder: 0, setIndex: 0)
private let window = SetDictation.silenceWindow
private let cap = SetDictation.listeningCap
/// The bound a hung flush holds a press to, spelled out: the result shows before it, and a
/// longer wait keeps the recording session open past what the athlete expects of a press.
private let flushWait = Duration.seconds(10)
private let logged235 = SetLog(weight: .pounds(235), reps: 5, rpe: .seven)

@MainActor
@Test func aSpokenSetLogsTheActiveSetReadsItBackOverTheRestAndFlushes() async throws {
    let harness = try await Harness(hearing: ["235 for 5 at 7"])
    let exercise = try harness.app.session(nil).exercises[0]

    let outcome = await harness.runUntilQuiet()

    #expect(outcome == .logged(SetLog(weight: .pounds(235), reps: 5, rpe: .seven), at: firstSet))
    #expect(harness.liveActivity.readbacks == [.listening, .logged("235×5 @7", to: try harness.squat(set: 1))])
    #expect(harness.liveActivity.sessionLabels == ["Week 1 - Day 1", "Week 1 - Day 1"])
    guard case .set(let listenedFor) = harness.liveActivity.subjects.first else {
        Issue.record("Listening showed \(String(describing: harness.liveActivity.subjects.first)), not the Set")
        return
    }
    #expect(listenedFor.exerciseName == exercise.name)
    #expect(listenedFor.setsDone == 0)
    #expect(listenedFor.setsTotal == exercise.sets.count)
    guard case .rest(let rest) = harness.liveActivity.subjects.last else {
        Issue.record("Logged showed \(String(describing: harness.liveActivity.subjects.last)), not the rest")
        return
    }
    #expect(rest.target?.setID == ActiveSetID(exerciseOrder: 0, setIndex: 1))
    #expect(rest.setsDone == 1)
    #expect(rest.restStartDate == frozenNow)
    #expect(rest.restEndDate == frozenNow.addingTimeInterval(harness.app.settings.standardRestDuration.timeInterval))
    #expect(try harness.app.session(nil).exercises[0].sets[0].state == "logged")
    #expect(harness.dictation.state == .idle)
    #expect(try await harness.app.sheet(tab: nil).cells["K15"] == "235x5@7")
    #expect(try harness.app.sync.fetchPendingWriteRecords().isEmpty)
}

@MainActor
@Test func afterAnExercisesLastSetTheReadbackNamesThatExerciseOverTheRestTowardTheNext() async throws {
    let harness = try await Harness(hearing: ["235 for 5 at 7"])
    let session = try #require(harness.app.workout.currentSession)
    let squatSets = try #require(session.exercises.first { $0.order == 0 }).sets.sorted { $0.index < $1.index }
    for set in squatSets.dropLast() {
        try harness.app.workout.log(set, as: SetLog(weight: .pounds(225), reps: 5, rpe: .seven))
    }

    let outcome = await harness.runUntilQuiet()

    #expect(outcome == .logged(logged235, at: ActiveSetID(exerciseOrder: 0, setIndex: 2)))
    #expect(harness.liveActivity.readbacks.last == .logged("235×5 @7", to: try harness.squat(set: 3)))
    guard case .rest(let rest) = harness.liveActivity.subjects.last else {
        Issue.record("Logged showed \(String(describing: harness.liveActivity.subjects.last)), not the rest")
        return
    }
    #expect(rest.exerciseName == "2-3:1:0 BB RDL", "the countdown still leads to the next Exercise")
    #expect(rest.target?.setID == ActiveSetID(exerciseOrder: 1, setIndex: 0))
}

@MainActor
@Test func afterTheSessionsLastSetTheReadbackNamesTheSetLogged() async throws {
    let harness = try await Harness(hearing: ["235 for 5 at 7"])
    let session = try #require(harness.app.workout.currentSession)
    let positions = SessionSetOrder.orderedSets(in: session)
    for position in positions.dropLast() {
        try harness.app.workout.log(position.set, as: SetLog(weight: .pounds(225), reps: 5, rpe: .seven))
    }
    let last = try #require(positions.last)

    _ = await harness.runUntilQuiet()

    let rdl = try harness.written("2-3:1:0 BB RDL", order: 1, set: 2, of: 2)
    #expect(harness.liveActivity.readbacks.last == .logged("235×5 @7", to: rdl))
    #expect(last.set.state == .logged)
    let result = try #require(harness.liveActivity.shown.last?.content)
    let restTowardIt = restContent(toward: rdl.target)
    #expect(!result.rides(restTowardIt), "the stage's rest led to the Set just logged, so it is over")
    #expect(result.rides(restContent(toward: LiveActivityRestTarget(session: rdl.target.session, setID: firstSet))))
}

@MainActor
@Test func listeningAndAResultThatWroteNothingSitOverARunningRestAndALoggedRestReplacesIt() async throws {
    let harness = try await Harness(hearing: ["RPE 9"])

    _ = await harness.runUntilQuiet()

    let target = try harness.squat(set: 1).target
    let running = restContent(toward: target)
    let listening = try #require(harness.liveActivity.shown.first?.content)
    let notLogged = try #require(harness.liveActivity.shown.last?.content)
    #expect(listening.rides(running))
    #expect(notLogged.rides(running), "nothing was written, so the rest toward the Set still stands")
    let logged = LiveActivityDictationContent(readback: .logged("235×5 @7", to: try harness.squat(set: 1)), subject: .rest(running))
    #expect(!logged.rides(running), "the rest this write began takes the running one's place")
}

@MainActor
@Test func theLiveActivityShowsListeningBeforeTheMicOpens() async throws {
    let transcriber = HeldSetTranscriber(candidates: ["skip it"])
    let harness = try await Harness(transcriber: transcriber)

    let run = Task { await harness.background.run() }
    await transcriber.starting.waitUntilHeld(orRecord: "The transcriber never started")
    #expect(harness.liveActivity.readbacks == [.listening])

    transcriber.starting.release()
    await harness.clock.waitUntilSleeping(until: window, orRecord: "It never waited for the athlete to fall quiet")
    harness.clock.advance(by: window)
    await transcriber.finishing.waitUntilHeld(orRecord: "The transcriber never finished")
    transcriber.finishing.release()

    #expect(await run.value == .skipped(at: firstSet))
    #expect(harness.liveActivity.readbacks == [.listening, .skipped(try harness.squat(set: 1))])
    #expect(try harness.app.session(nil).exercises[0].sets[0].state == "skipped")
    #expect(try await harness.app.sheet(tab: nil).cells["K15"] == "skip")
}

@MainActor
@Test func aValueStillMissingWritesNothingAndSaysWhich() async throws {
    let harness = try await Harness(hearing: ["RPE 9"])

    let outcome = await harness.runUntilQuiet()

    #expect(outcome == .notLogged(.missingValues(SetLogDraft(weight: nil, reps: 5, rpe: .nine), heard: "RPE 9"), at: firstSet))
    #expect(harness.liveActivity.readbacks == [.listening, .notLogged("“RPE 9”, no weight")])
    try harness.expectNothingWritten()
}

@MainActor
@Test func aSetOnlyTheLessLikelyTranscriptsReadWritesNothing() async throws {
    let harness = try await Harness(hearing: ["um", "185 for 5 at 8"])

    let outcome = await harness.runUntilQuiet()

    #expect(outcome == .notLogged(.ambiguous(heard: "um"), at: firstSet))
    #expect(harness.liveActivity.readbacks == [.listening, .notLogged("“um”")])
    try harness.expectNothingWritten()
}

@MainActor
@Test func aRejectedSpokenSetWritesNothingAndLeavesWhyForTheCard() async throws {
    let harness = try await Harness(hearing: ["100 kilos for 5"])

    let outcome = await harness.runUntilQuiet()

    let rejected = SetDictation.Outcome.rejected(.spokenSet(.kilograms), heard: "100 kilos for 5")
    #expect(outcome == .notLogged(.rejected(.spokenSet(.kilograms), heard: "100 kilos for 5"), at: firstSet))
    #expect(harness.liveActivity.readbacks == [.listening, .notLogged("“100 kilos for 5”")])
    #expect(harness.dictation.state == .finished(firstSet, rejected))
    try harness.expectNothingWritten()
}

@MainActor
@Test func nothingHeardByTheCapWritesNothing() async throws {
    let harness = try await Harness(hearing: [])

    let run = Task { await harness.background.run() }
    await harness.clock.waitUntilSleeping(until: window, orRecord: "It never started listening")
    harness.clock.advance(by: cap)

    #expect(await run.value == .notLogged(.rejected(.transcriber(.nothingHeard), heard: ""), at: firstSet))
    #expect(harness.liveActivity.readbacks == [.listening, .notLogged("Nothing heard")])
    try harness.expectNothingWritten()
}

@MainActor
@Test(
    "A mic that will not open tells the athlete to open the app once",
    arguments: [SetTranscriberError.microphoneDenied, .unavailable]
)
func aMicThatWillNotOpenTellsTheAthleteToOpenTheAppOnce(error: SetTranscriberError) async throws {
    let harness = try await Harness(transcriber: FailingSetTranscriber(error))

    let outcome = await harness.background.run()

    #expect(outcome == .notLogged(.rejected(.transcriber(error), heard: ""), at: firstSet))
    #expect(harness.liveActivity.readbacks == [.listening, .notLogged("Open WorkoutTracker once to allow the mic")])
    try harness.expectNothingWritten()
}

@MainActor
@Test func listeningThatFailsAsksForAnUnlock() async throws {
    let harness = try await Harness(transcriber: FailingSetTranscriber(.failed))

    _ = await harness.background.run()

    #expect(harness.liveActivity.readbacks == [.listening, .notLogged("Couldn’t listen. Unlock to log")])
    try harness.expectNothingWritten()
}

@MainActor
@Test func withNoCurrentSessionTheLiveActivitySaysToChooseASheetAndNothingListens() async throws {
    let harness = try await Harness(hearing: ["235 for 5 at 7"], selectingSpreadsheet: false)

    let outcome = await harness.background.run()

    #expect(outcome == .noSetToLog(.noCurrentSession))
    #expect(harness.liveActivity.noSets == [.noCurrentSession])
    #expect(harness.liveActivity.readbacks.isEmpty, "nothing listened")
    #expect(harness.dictation.state == .idle)
    #expect(try harness.app.sync.fetchPendingWriteRecords().isEmpty)
    #expect(harness.signIn.restores == 0, "nothing to flush")
}

@MainActor
@Test func aCurrentSessionWithNoPendingSetSaysSoOnTheLiveActivity() async throws {
    let harness = try await Harness(hearing: ["235 for 5 at 7"])
    let session = try #require(harness.app.workout.currentSession)
    for position in SessionSetOrder.orderedSets(in: session) {
        try harness.app.workout.skip(position.set)
    }
    harness.app.workout.show(SessionAddress(week: 1, day: 1))
    harness.app.workout.makeViewedSessionCurrent()
    let queued = try harness.app.sync.fetchPendingWriteRecords().count

    let outcome = await harness.background.run()

    #expect(outcome == .noSetToLog(.everythingLogged))
    #expect(harness.liveActivity.noSets == [.noSetLeft(session: "Week 1 - Day 1")])
    #expect(harness.liveActivity.readbacks.isEmpty, "nothing listened")
    #expect(harness.dictation.state == .idle)
    #expect(try harness.app.sync.fetchPendingWriteRecords().count == queued, "nothing written")
    #expect(harness.signIn.restores == 0, "nothing to flush")
}

@MainActor
@Test func theCardsMicListeningLeavesTheSetToTheCard() async throws {
    let harness = try await Harness(hearing: ["235 for 5 at 7"])
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
    let harness = try await Harness(hearing: ["235 for 5 at 7"])
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

    let second = await harness.runUntilQuiet()

    #expect(second == .logged(SetLog(weight: .pounds(235), reps: 5, rpe: .seven), at: ActiveSetID(exerciseOrder: squat.order, setIndex: 1)))
    #expect(stage.activeSetID == ActiveSetID(exerciseOrder: rdl.order, setIndex: 1))
}

@MainActor
@Test func itLogsTheSetTheAthleteFocusedOnTheCard() async throws {
    let harness = try await Harness(hearing: ["235 for 5 at 7"])
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
    let harness = try await Harness(hearing: ["235 for 5 at 7"])
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
    let harness = try await Harness(hearing: ["235 for 5 at 7"])
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
    let harness = try await Harness(hearing: ["235 for 5 at 7"])
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
    let harness = try await Harness(hearing: ["235 for 5 at 7"])
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

@MainActor
@Test func theCardTakingTheMicWhileListeningShowsTakesTheReadbackOff() async throws {
    let harness = try await Harness(hearing: ["235 for 5 at 7"])
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
    let harness = try await Harness(transcriber: transcriber)

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
    let harness = try await Harness(hearing: ["235 for 5 at 7"])
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
    let cold = try await Harness(hearing: ["235 for 5 at 7"])
    _ = await cold.runUntilQuiet()
    #expect(cold.signIn.restores == 1)
    #expect(cold.app.settings.isSignedIn)

    let warm = try await Harness(hearing: ["235 for 5 at 7"])
    warm.app.settings.isSignedIn = true
    _ = await warm.runUntilQuiet()
    #expect(warm.signIn.restores == 0)
}

@MainActor
@Test func aFlushThatHangsReturnsAtTheDeadlineWithTheWriteQueuedAndRunsOn() async throws {
    let sheet = HeldWriteSheetsClient()
    let harness = try await Harness(hearing: ["235 for 5 at 7"], sheet: sheet)

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

private func restContent(toward target: LiveActivityRestTarget) -> LiveActivityRestContent {
    LiveActivityRestContent(
        exerciseName: "Back Squat",
        prescribedReps: "5",
        prescribedLoad: "RPE7",
        weightValue: "",
        weightUnit: "lbs",
        setsDone: 1,
        setsTotal: 3,
        variant: .restTimerSetsLeft,
        restStartDate: frozenNow,
        restEndDate: frozenNow.addingTimeInterval(120),
        target: target
    )
}

@MainActor
private struct Harness {
    let app: WorkoutApplication
    let dictation: SetDictation
    let clock = ManualListeningClock()
    let liveActivity = SpyDictationLiveActivity()
    let signIn = FakeSignIn()
    /// The process's focus, which a stage binds when a test puts one up.
    let focus = ActiveSetFocusManager(session: nil)
    let background: BackgroundDictation

    init(hearing candidates: [String], selectingSpreadsheet: Bool = true, sheet: HeldWriteSheetsClient? = nil) async throws {
        try await self.init(
            transcriber: CannedSetTranscriber(candidates: candidates),
            selectingSpreadsheet: selectingSpreadsheet,
            sheet: sheet
        )
    }

    init(transcriber: any SetTranscriber, selectingSpreadsheet: Bool = true, sheet: HeldWriteSheetsClient? = nil) async throws {
        app = try WorkoutApplication(
            environment: AppEnvironment(
                storage: .inMemory,
                sheetsClient: sheet ?? HeldWriteSheetsClient(holding: false),
                defaults: .inMemory(),
                now: { frozenNow },
                seed: nil
            )
        )
        if selectingSpreadsheet {
            _ = try await app.selectSpreadsheet(id: "FIXTURE", title: "Fixture Training Log")
        }
        dictation = SetDictation(transcriber: transcriber, clock: clock)
        background = BackgroundDictation(
            app: app,
            dictation: dictation,
            focus: focus,
            liveActivity: liveActivity,
            signIn: signIn,
            clock: clock,
            now: { frozenNow }
        )
    }

    /// Runs with a transcriber that hears everything at once, so listening ends a silence window on.
    func runUntilQuiet() async -> BackgroundDictation.Outcome {
        let run = Task { await background.run() }
        await clock.waitUntilSleeping(until: clock.now + window, orRecord: "It never started listening")
        clock.advance(by: window)
        return await run.value
    }

    func written(_ exerciseName: String, order: Int, set ordinal: Int, of total: Int) throws -> LiveActivityDictationContent.WrittenSet {
        let session = try #require(app.workout.currentSession)
        let setID = ActiveSetID(exerciseOrder: order, setIndex: ordinal - 1)
        return LiveActivityDictationContent.WrittenSet(
            exerciseName: exerciseName,
            setOrdinal: ordinal,
            setsTotal: total,
            target: LiveActivityRestTarget(session: session.reparseIdentity, setID: setID)
        )
    }

    func squat(set ordinal: Int) throws -> LiveActivityDictationContent.WrittenSet {
        try written("Back Squat", order: 0, set: ordinal, of: 3)
    }

    /// A Session screen up behind the intent, its stage on `session`, as with the app backgrounded.
    func stage(on session: Session) -> SessionCoordinator {
        let stage = SessionCoordinator(logging: app.workout, dictation: dictation, focus: focus)
        stage.bind(to: session)
        return stage
    }

    func expectNothingWritten(sourceLocation: SourceLocation = #_sourceLocation) throws {
        #expect(try app.session(nil).exercises[0].sets[0].state == "pending", sourceLocation: sourceLocation)
        #expect(try app.sync.fetchPendingWriteRecords().isEmpty, sourceLocation: sourceLocation)
        #expect(signIn.restores == 0, "nothing to flush", sourceLocation: sourceLocation)
    }
}

@MainActor
private final class SpyDictationLiveActivity: DictationLiveActivityAdapter {
    private(set) var shown: [(content: LiveActivityDictationContent, sessionLabel: String)] = []

    var readbacks: [LiveActivityDictationContent.Readback] { shown.map(\.content.readback) }
    var subjects: [LiveActivityDictationContent.Subject] { shown.map(\.content.subject) }
    var sessionLabels: [String] { shown.map(\.sessionLabel) }
    private(set) var noSets: [LiveActivityNoSetReadback] = []
    private(set) var withdrawals = 0
    /// Runs as a readback shows, as the app can come forward while the system draws it.
    var whileShowing: (LiveActivityDictationContent.Readback) -> Void = { _ in }

    /// What the Live Activity reads once the run is over; nil when nothing is left on it.
    var finalReadback: LiveActivityDictationContent.Readback? {
        withdrawals > 0 ? nil : readbacks.last
    }

    func show(_ content: LiveActivityDictationContent, sessionLabel: String) async {
        shown.append((content, sessionLabel))
        whileShowing(content.readback)
    }

    func show(_ noSet: LiveActivityNoSetReadback) async {
        noSets.append(noSet)
    }

    func withdrawReadback() async {
        withdrawals += 1
    }
}

@MainActor
private final class FakeSignIn: SignInRestoring {
    private(set) var restores = 0

    func restorePreviousSignIn() async -> Bool {
        restores += 1
        return true
    }
}

@MainActor
private final class FailingSetTranscriber: SetTranscriber {
    private let error: SetTranscriberError

    init(_ error: SetTranscriberError) {
        self.error = error
    }

    func start(hearing: @escaping @MainActor (String) -> Void) async throws(SetTranscriberError) {
        throw error
    }

    func finish() async throws(SetTranscriberError) -> [String] {
        throw error
    }

    func cancel() async {}
}

/// The fixture workbook behind a Sheet whose writes park until the test releases them.
@MainActor
private final class HeldWriteSheetsClient: SheetsClient {
    private let workbook = LocalWorkbookSheetsClient(workbook: WorkbookScenario.freshBlock.workbook())
    private let held: HeldCall

    init(holding: Bool = true) {
        held = HeldCall(parks: holding ? 1 : 0)
    }

    func listTabTitles(spreadsheetId: String) async throws -> [String] {
        try await workbook.listTabTitles(spreadsheetId: spreadsheetId)
    }

    func listSpreadsheets(pageToken: String?) async throws -> SpreadsheetListPage {
        try await workbook.listSpreadsheets(pageToken: pageToken)
    }

    func fetchTabSnapshot(spreadsheetId: String, tabName: String) async throws -> SheetSnapshot {
        try await workbook.fetchTabSnapshot(spreadsheetId: spreadsheetId, tabName: tabName)
    }

    func updateCells(spreadsheetId: String, range: String, values: [[String]]) async throws {
        await held.hold()
        try await workbook.updateCells(spreadsheetId: spreadsheetId, range: range, values: values)
    }

    func updateCells(spreadsheetId: String, updates: [SheetValueRangeUpdate]) async throws {
        await held.hold()
        try await workbook.updateCells(spreadsheetId: spreadsheetId, updates: updates)
    }

    func waitUntilHeld(orRecord failure: Comment, sourceLocation: SourceLocation = #_sourceLocation) async {
        await held.waitUntilHeld(orRecord: failure, sourceLocation: sourceLocation)
    }

    /// Releases only a write already parked, so a test waits for one first.
    func release() {
        held.release()
    }
}
