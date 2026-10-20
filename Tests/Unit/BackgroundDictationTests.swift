import Foundation
import Testing

@testable import WorkoutTracker

private let frozenNow = Date(timeIntervalSince1970: 1_780_000_000)
private let firstSet = ActiveSetID(exerciseOrder: 0, setIndex: 0)
private let window = SetDictation.silenceWindow
private let cap = SetDictation.listeningCap
private let logged235 = SetLog(weight: .pounds(235), reps: 5, rpe: .seven)

@MainActor
@Test func aSpokenSetLogsTheActiveSetReadsItBackOverTheRestAndFlushes() async throws {
    let harness = try await BackgroundDictationHarness(hearing: ["235 for 5 at 7"])
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
    let restDuration = rest.restEndDate.timeIntervalSince(rest.restStartDate)
    #expect(harness.restTimer.interval == RestInterval(start: rest.restStartDate, duration: restDuration, kind: .standard))
    #expect(try harness.app.session(nil).exercises[0].sets[0].state == "logged")
    #expect(harness.dictation.state == .idle)
    #expect(try await harness.app.sheet(tab: nil).cells["K15"] == "235x5@7")
    #expect(try harness.app.sync.fetchPendingWriteRecords().isEmpty)
    #expect(outcome.refusal == nil)
}

/// A recording with the app behind must have a Live Activity up, so with Live Activities off for
/// the app nothing listens, and the press says what to turn on instead of recording unseen.
@MainActor
@Test func withLiveActivitiesOffNothingListensAndThePressSaysWhatToTurnOn() async throws {
    let harness = try await BackgroundDictationHarness(hearing: ["235 for 5 at 7"])
    harness.liveActivity.isUp = false

    let outcome = await harness.background.run()

    #expect(outcome == .liveActivitiesOff)
    #expect(outcome.refusal?.errorDescription == "Turn on Live Activities for WorkoutTracker to log while locked")
    #expect(harness.liveActivity.readbacks == [.listening], "it asked for the activity and stopped when none showed")
    #expect(harness.dictation.state == .idle)
    try harness.expectNothingWritten()
}

/// A press with no Set to log says why on the Live Activity; with none to say it on, the surface
/// that pressed says what to turn on rather than nothing at all.
@MainActor
@Test func withLiveActivitiesOffAPressWithNoSetToLogSaysWhatToTurnOn() async throws {
    let harness = try await BackgroundDictationHarness(hearing: ["235 for 5 at 7"], selectingSpreadsheet: false)
    harness.liveActivity.isUp = false

    let outcome = await harness.background.run()

    #expect(outcome == .liveActivitiesOff)
    #expect(outcome.refusal?.errorDescription == "Turn on Live Activities for WorkoutTracker to log while locked")
    #expect(harness.liveActivity.noSets == [.noCurrentSession], "it asked the Live Activity first")
    #expect(harness.liveActivity.readbacks.isEmpty, "nothing listened")
    #expect(try harness.app.sync.fetchPendingWriteRecords().isEmpty)
}

@MainActor
@Test func afterAnExercisesLastSetTheReadbackNamesThatExerciseOverTheRestTowardTheNext() async throws {
    let harness = try await BackgroundDictationHarness(hearing: ["235 for 5 at 7"])
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
    #expect(rest.exerciseName == "BB RDL", "the countdown still leads to the next Exercise")
    #expect(rest.target?.setID == ActiveSetID(exerciseOrder: 1, setIndex: 0))
}

@MainActor
@Test func afterTheSessionsLastSetTheReadbackNamesTheSetLogged() async throws {
    let harness = try await BackgroundDictationHarness(hearing: ["235 for 5 at 7"])
    let session = try #require(harness.app.workout.currentSession)
    let positions = SessionSetOrder.orderedSets(in: session)
    for position in positions.dropLast() {
        try harness.app.workout.log(position.set, as: SetLog(weight: .pounds(225), reps: 5, rpe: .seven))
    }
    let last = try #require(positions.last)

    _ = await harness.runUntilQuiet()

    let rdl = try harness.written("BB RDL", order: 1, set: 2, of: 2)
    #expect(harness.liveActivity.readbacks.last == .logged("235×5 @7", to: rdl))
    #expect(last.set.state == .logged)
    let result = try #require(harness.liveActivity.shown.last?.content)
    let restTowardIt = restContent(toward: try #require(rdl.target))
    #expect(!result.rides(restTowardIt), "the stage's rest led to the Set just logged, so it is over")
    #expect(result.rides(restContent(toward: LiveActivityRestTarget(session: try #require(rdl.target).session, setID: firstSet))))
    #expect(harness.restTimer.isRunning, "the week has Sets left, so the stage would rest toward the next Session")
}

/// The stage rests only toward a Set left in the week; a locked log of the week's last one, with no
/// rest running, starts none and schedules no notification.
@MainActor
@Test func aLockedLogOfTheWeeksLastSetStartsNoRest() async throws {
    let harness = try await BackgroundDictationHarness(hearing: ["235 for 5 at 7"])
    let session = try #require(harness.app.workout.currentSession)
    let last = try #require(SessionSetOrder.orderedSets(in: session).last)
    for weekSession in SessionProgressTracker().sessionsInCurrentWeek(for: session) {
        for position in SessionSetOrder.orderedSets(in: weekSession) where position.set !== last.set {
            try harness.app.workout.log(position.set, as: SetLog(weight: .pounds(225), reps: 5, rpe: .seven))
        }
    }
    // The Sheet moves the Current Session past a Session logged elsewhere; the athlete keeps it here.
    harness.app.workout.show(try #require(session.address))
    harness.app.workout.makeViewedSessionCurrent()
    #expect(harness.app.workout.currentSession === session)

    let outcome = await harness.runUntilQuiet()

    #expect(outcome == .logged(logged235, at: last.setID))
    #expect(harness.restTimer.interval == nil)
    #expect(harness.restNotifications.scheduledDeadlines.isEmpty)
    #expect(harness.liveActivity.subjects.last == .set(LiveActivitySetContent(last)))
}

/// The rest a locked log starts is the stage's own: the pill shows it when the app comes forward,
/// and the rest-end notification fires with no scene to schedule it.
@MainActor
@Test func aLockedLogStartsTheRestTheStageShowsAndSchedulesItsEndNotification() async throws {
    let harness = try await BackgroundDictationHarness(hearing: ["235 for 5 at 7"])
    let session = try #require(harness.app.workout.currentSession)
    let stage = harness.stage(on: session)

    _ = await harness.runUntilQuiet()

    let duration = harness.app.settings.standardRestDuration.timeInterval
    let end = frozenNow.addingTimeInterval(duration)
    #expect(harness.restTimer.interval == RestInterval(start: frozenNow, duration: duration, kind: .standard))
    #expect(harness.restTimer.origin == firstSet)
    #expect(harness.restNotifications.scheduledDeadlines == [end])
    #expect(harness.restExpiry.scheduledDeadlines == [end])
    guard case .rest(let rest) = harness.liveActivity.subjects.last else {
        Issue.record("Logged showed \(String(describing: harness.liveActivity.subjects.last)), not the rest")
        return
    }
    #expect(rest.restStartDate == harness.restTimer.interval?.start)
    #expect(rest.restEndDate == harness.restTimer.interval?.end, "the Live Activity counts the same rest down")
    #expect(stage.activeSetID == ActiveSetID(exerciseOrder: 0, setIndex: 1))
}

/// Deleting the Set Log on the card afterwards ends the rest, as it does for a tapped Log, since
/// the rest was started for that Set.
@MainActor
@Test func theStageCancelsTheRestALockedLogStartedWhenItsSetLogIsDeleted() async throws {
    let harness = try await BackgroundDictationHarness(hearing: ["235 for 5 at 7"])
    let session = try #require(harness.app.workout.currentSession)
    let stage = harness.stage(on: session)
    let first = try #require(session.exercises.first { $0.order == 0 }?.sets.first { $0.index == 0 })
    _ = await harness.runUntilQuiet()
    #expect(harness.restTimer.isRunning)

    stage.deleteLog(for: first)

    #expect(!harness.restTimer.isRunning)
    #expect(harness.restNotifications.cancelCount == 1)
}

@MainActor
@Test func listeningAndAResultThatWroteNothingSitOverARunningRestAndALoggedRestReplacesIt() async throws {
    let harness = try await BackgroundDictationHarness(hearing: ["RPE 9"])

    _ = await harness.runUntilQuiet()

    let target = try #require(try harness.squat(set: 1).target)
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
    let harness = try await BackgroundDictationHarness(transcriber: transcriber)

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
    let harness = try await BackgroundDictationHarness(hearing: ["RPE 9"])

    let outcome = await harness.runUntilQuiet()

    #expect(outcome == .notLogged(.missingValues(SetLogDraft(weight: nil, reps: 5, rpe: .nine), heard: "RPE 9"), at: firstSet))
    #expect(harness.liveActivity.readbacks == [.listening, .notLogged("“RPE 9”, no weight")])
    try harness.expectNothingWritten()
}

@MainActor
@Test func aSetOnlyTheLessLikelyTranscriptsReadWritesNothing() async throws {
    let harness = try await BackgroundDictationHarness(hearing: ["um", "185 for 5 at 8"])

    let outcome = await harness.runUntilQuiet()

    #expect(outcome == .notLogged(.ambiguous(heard: "um"), at: firstSet))
    #expect(harness.liveActivity.readbacks == [.listening, .notLogged("“um”")])
    try harness.expectNothingWritten()
}

@MainActor
@Test func aRejectedSpokenSetWritesNothingAndLeavesWhyForTheCard() async throws {
    let harness = try await BackgroundDictationHarness(hearing: ["100 kilos for 5"])

    let outcome = await harness.runUntilQuiet()

    let rejected = SetDictation.Outcome.rejected(.spokenSet(.kilograms), heard: "100 kilos for 5")
    #expect(outcome == .notLogged(.rejected(.spokenSet(.kilograms), heard: "100 kilos for 5"), at: firstSet))
    #expect(harness.liveActivity.readbacks == [.listening, .notLogged("“100 kilos for 5”")])
    #expect(harness.dictation.state == .finished(firstSet, rejected))
    try harness.expectNothingWritten()
}

@MainActor
@Test func aSetNoLifterLogsWritesNothingAndAsksForItAgain() async throws {
    let harness = try await BackgroundDictationHarness(hearing: ["180 for 546"])

    let outcome = await harness.runUntilQuiet()

    #expect(outcome == .notLogged(.rejected(.spokenSet(.implausible(.reps)), heard: "180 for 546"), at: firstSet))
    #expect(harness.liveActivity.readbacks == [.listening, .notLogged("“180 for 546”, say it again")])
    try harness.expectNothingWritten()
}

@MainActor
@Test func nothingHeardByTheCapWritesNothing() async throws {
    let harness = try await BackgroundDictationHarness(hearing: [])

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
    let harness = try await BackgroundDictationHarness(transcriber: FailingSetTranscriber(error))

    let outcome = await harness.background.run()

    #expect(outcome == .notLogged(.rejected(.transcriber(error), heard: ""), at: firstSet))
    #expect(harness.liveActivity.readbacks == [.listening, .notLogged("Open WorkoutTracker once to allow the mic")])
    try harness.expectNothingWritten()
}

@MainActor
@Test func listeningThatFailsAsksForAnUnlock() async throws {
    let harness = try await BackgroundDictationHarness(transcriber: FailingSetTranscriber(.failed))

    _ = await harness.background.run()

    #expect(harness.liveActivity.readbacks == [.listening, .notLogged("Couldn’t listen. Unlock to log")])
    try harness.expectNothingWritten()
}

@MainActor
@Test func withNoCurrentSessionTheLiveActivitySaysToChooseASheetAndNothingListens() async throws {
    let harness = try await BackgroundDictationHarness(hearing: ["235 for 5 at 7"], selectingSpreadsheet: false)

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
    let harness = try await BackgroundDictationHarness(hearing: ["235 for 5 at 7"])
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
