import Testing

@testable import WorkoutTracker

private let squat = SpokenSetContext(draft: SetLogDraft(weight: .pounds(185), reps: 5, rpe: .eight), previous: nil)
private let firstSet = ActiveSetID(exerciseOrder: 0, setIndex: 0)
private let window = SetDictation.silenceWindow
private let cap = SetDictation.listeningCap

private let frame = VoiceActivity.frameDuration
private let unheard = VoiceActivity()

@Test(
    "With the mic level hearing no one, listening stops the silence window after the caption last changed, or at the cap",
    arguments: [
        (Duration.seconds(1), nil, Duration.seconds(1), SetDictation.AutoStop.wake(at: .seconds(1) + frame)),
        (.seconds(1), nil, .seconds(1) + cap - .milliseconds(50), .wake(at: .seconds(1) + cap)),
        (.seconds(1), nil, .seconds(1) + cap, .stop(.nothingHeard)),
        (.seconds(1), .seconds(2), .milliseconds(2500), .wake(at: .milliseconds(2500) + frame)),
        (.seconds(1), .seconds(2), .seconds(2) + window - .milliseconds(50), .wake(at: .seconds(2) + window)),
        (.seconds(1), .seconds(2), .seconds(2) + window, .stop(.silence)),
        (.seconds(1), .seconds(1) + cap - window, .seconds(1) + cap, .stop(.silence)),
        (.seconds(1), .seconds(8), .milliseconds(8500), .wake(at: .milliseconds(8500) + frame)),
        (.seconds(1), .seconds(8), .seconds(1) + cap, .stop(.cap))
    ] as [(Duration, Duration?, Duration, SetDictation.AutoStop)]
)
func listeningStopsOnTheCaption(liveAt: Duration, lastHeardAt: Duration?, now: Duration, step: SetDictation.AutoStop) {
    #expect(SetDictation.autoStop(at: now, liveAt: liveAt, lastHeardAt: lastHeardAt, voice: unheard, earlyRead: nil) == step)
}

/// The athlete spoke for 5 frames after 3 quiet ones, so their Pause began 8 frames in.
private func spoke(thenPausedFor frames: Int) -> VoiceActivity {
    VoiceActivity(levels: Array(repeating: -60, count: 3) + Array(repeating: -20, count: 5) + Array(repeating: -60, count: frames))
}

private let pauseBegan = 8 * VoiceActivity.frameSamples
private let now = Duration.seconds(2)

private func read(_ heard: HandsFreeEarlyRead.Heard?, ofAllTheAthleteSaid all: Bool = true) -> HandsFreeEarlyRead {
    HandsFreeEarlyRead(samples: all ? pauseBegan + 4 * VoiceActivity.frameSamples : pauseBegan - 1, heard: heard)
}

@Test(
    "A Pause asks for a read of the recording so far, and stops listening once that read heard a whole Set",
    arguments: [
        (3, nil, SetDictation.AutoStop.wake(at: now + frame)),
        (4, nil, .read),
        (4, read(nil), .wake(at: now + frame)),
        (4, read(nil, ofAllTheAthleteSaid: false), .read),
        (4, read(.wholeSet), .stop(.wholeSet)),
        (4, read(.wholeSet, ofAllTheAthleteSaid: false), .read),
        (4, read(.wholeSetWithAWholeRPE), .wake(at: now + frame)),
        (11, read(.wholeSetWithAWholeRPE), .wake(at: now + frame)),
        (12, read(.wholeSetWithAWholeRPE), .stop(.wholeSet)),
        (13, read(.partOfASet), .wake(at: now + frame)),
        (14, read(.partOfASet), .stop(.silence)),
        (14, nil, .stop(.silence))
    ] as [(Int, HandsFreeEarlyRead?, SetDictation.AutoStop)]
)
func listeningStopsOnAPause(pause: Int, earlyRead: HandsFreeEarlyRead?, step: SetDictation.AutoStop) {
    #expect(
        SetDictation.autoStop(at: now, liveAt: .zero, lastHeardAt: nil, voice: spoke(thenPausedFor: pause), earlyRead: earlyRead) == step
    )
}

@Test func theMicLevelHearingTheAthleteMeansTheCapStopsWhatItHeardRatherThanNothing() {
    let speaking = spoke(thenPausedFor: 0)

    #expect(SetDictation.autoStop(at: cap, liveAt: .zero, lastHeardAt: nil, voice: speaking, earlyRead: nil) == .stop(.cap))
    #expect(SetDictation.autoStop(at: cap, liveAt: .zero, lastHeardAt: nil, voice: unheard, earlyRead: nil) == .stop(.nothingHeard))
}

@Test(
    "A read stops listening early only when its transcript says the whole Set itself",
    arguments: [
        ("225 for 3 at 9.5", nil, HandsFreeEarlyRead.Heard.wholeSet),
        ("185 for 5 at 10", nil, .wholeSet),
        ("185 for 5 at 8", nil, .wholeSetWithAWholeRPE),
        ("skip", nil, .wholeSet),
        ("same again", SetLog(weight: .pounds(185), reps: 5, rpe: .eight), .wholeSet),
        ("same again", nil, .partOfASet),
        ("185 for 5", nil, .partOfASet),
        ("for 5 at 8", nil, .partOfASet),
        ("185 for 5 at", nil, .partOfASet),
        ("185 kilos for 5 at 8", nil, .partOfASet)
    ] as [(String, SetLog?, HandsFreeEarlyRead.Heard)]
)
func whatAnEarlyReadHeard(transcript: String, previous: SetLog?, heard: HandsFreeEarlyRead.Heard) {
    let context = SpokenSetContext(draft: SetLogDraft(weight: .pounds(185), reps: 5, rpe: .eight), previous: previous)
    let decode = RecordingDecode(result: .heard(transcript, segments: []), timings: nil)

    #expect(SetDictation.heard(decode, in: context) == heard)
}

@Test func anEarlyReadThatHeardNothingSaysNoSet() {
    #expect(SetDictation.heard(.missing(.modelNotReady(.absent)), in: squat) == .partOfASet)
}

/// The outcome once listening has ended, or nil, cancelling the press, when it never does.
@MainActor
private func outcome(of listening: Task<SetDictation.Outcome?, Never>, from dictation: SetDictation) async -> SetDictation.Outcome? {
    let ended = await waitUntil({ if case .finished = dictation.state { true } else { false } }, orRecord: "Listening never ended")
    if !ended { await dictation.cancel() }
    return await listening.value
}

@MainActor
@Test func handsFreeListeningEndsTheSilenceWindowAfterTheLastWordAndWritesWhatWasHeard() async {
    let (dictation, transcriber, clock) = makeHandsFreeDictation()
    let listening = Task { await dictation.listenUntilQuiet(for: firstSet, on: .card) { squat } }
    await clock.waitUntilSleeping(until: frame, orRecord: "It never listened")

    await clock.advanceUntilSleeping(by: .milliseconds(500), orRecord: "It stopped listening before a word")
    transcriber.say("135 for")
    await clock.advanceUntilSleeping(by: .milliseconds(1100), orRecord: "It never waited out the silence after 135 for")
    transcriber.say("135 for 4 at 9")
    await clock.advanceUntilSleeping(by: .milliseconds(1150), orRecord: "It never waited out the silence after the last word")
    #expect(dictation.state == .listening(firstSet, heard: "135 for 4 at 9"), "still listening inside the window")

    clock.advance(by: .milliseconds(50))

    let logged = SetDictation.Outcome.logged(SetLog(weight: .pounds(135), reps: 4, rpe: .nine), heard: "135 for 4 at 9")
    #expect(await outcome(of: listening, from: dictation) == logged)
    #expect(dictation.state == .finished(firstSet, logged))
}

@MainActor
@Test func aTranscriptHeardAgainUnchangedDoesNotRestartTheSilenceWindow() async {
    let (dictation, transcriber, clock) = makeHandsFreeDictation()
    let listening = Task { await dictation.listenUntilQuiet(for: firstSet, on: .card) { squat } }
    await clock.waitUntilSleeping(until: frame, orRecord: "It never listened")

    await clock.advanceUntilSleeping(by: .milliseconds(500), orRecord: "It stopped listening before a word")
    transcriber.say("skip")
    await clock.advanceUntilSleeping(by: .milliseconds(300), orRecord: "It stopped listening inside the window")
    transcriber.say("skip")
    clock.advance(by: .milliseconds(900))

    #expect(await outcome(of: listening, from: dictation) == .skipped(heard: "skip"), "the window ran from the first skip")
}

@MainActor
@Test func handsFreeListeningThatHearsNothingByTheCapWritesNothing() async {
    let (dictation, transcriber, clock) = makeHandsFreeDictation()
    let listening = Task { await dictation.listenUntilQuiet(for: firstSet, on: .card) { squat } }
    await clock.waitUntilSleeping(until: frame, orRecord: "It never listened")

    await clock.advanceUntilSleeping(by: cap - .milliseconds(50), orRecord: "It never waited for the cap")
    clock.advance(by: .milliseconds(50))

    let nothingHeard = SetDictation.Outcome.rejected(.transcriber(.nothingHeard), heard: "")
    #expect(await outcome(of: listening, from: dictation) == nothingHeard)
    #expect(dictation.state == .finished(firstSet, nothingHeard))
    #expect(transcriber.wasCancelled)
    #expect(transcriber.finishes == 0)
}

@MainActor
@Test func theCapEndsHandsFreeListeningThatNeverFallsQuiet() async {
    let (dictation, transcriber, clock) = makeHandsFreeDictation()
    let listening = Task { await dictation.listenUntilQuiet(for: firstSet, on: .card) { squat } }
    await clock.waitUntilSleeping(until: frame, orRecord: "It never listened")

    clock.advance(by: cap - .milliseconds(500))
    transcriber.say("skip")
    await clock.advanceUntilSleeping(by: .milliseconds(450), orRecord: "It never waited for the cap")
    clock.advance(by: .milliseconds(50))

    #expect(await outcome(of: listening, from: dictation) == .skipped(heard: "skip"))
    #expect(transcriber.finishes == 1)
}

@MainActor
@Test func theCapCountsFromWhenTheMicWentLiveNotFromThePress() async {
    let (dictation, transcriber, clock) = makeHandsFreeDictation(holdingStart: true)
    let listening = Task { await dictation.listenUntilQuiet(for: firstSet, on: .card) { squat } }
    await transcriber.starting.waitUntilHeld(orRecord: "The transcriber never started")

    clock.advance(by: cap + .seconds(2))
    transcriber.starting.release()

    await clock.waitUntilSleeping(until: cap + .seconds(2) + frame, orRecord: "Preparing counted against the cap")
    #expect(dictation.state == .listening(firstSet, heard: ""))
    await dictation.cancel()
    clock.advance(by: frame)
    #expect(await listening.value == nil)
}

@MainActor
@Test func aTapOnTheMicFinishesHandsFreeListeningAndTheAutoStopWritesNothingMore() async {
    let (dictation, transcriber, clock) = makeHandsFreeDictation()
    let listening = Task { await dictation.listenUntilQuiet(for: firstSet, on: .card) { squat } }
    await clock.waitUntilSleeping(until: frame, orRecord: "It never listened")
    transcriber.say("skip")

    let tapped = await dictation.finish(for: firstSet, in: squat)
    clock.advance(by: window)

    #expect(tapped == .skipped(heard: "skip"))
    #expect(await listening.value == nil)
    #expect(transcriber.finishes == 1)
}

@MainActor
@Test func aMicThatWillNotStartRejectsHandsFreeListeningAtOnce() async {
    let (dictation, _, _) = makeHandsFreeDictation(failingToStart: .microphoneDenied)

    let rejected = await dictation.listenUntilQuiet(for: firstSet, on: .card) { squat }

    #expect(rejected == .rejected(.transcriber(.microphoneDenied), heard: ""))
}

@MainActor
@Test func handsFreeListeningLeavesAPressAlreadyInFlightAlone() async {
    let (dictation, _, _) = makeHandsFreeDictation()
    let secondSet = ActiveSetID(exerciseOrder: 0, setIndex: 1)
    #expect(dictation.start(for: secondSet))

    #expect(await dictation.listenUntilQuiet(for: firstSet, on: .card) { squat } == nil)
    #expect(dictation.state.pressSetID == secondSet)
    #expect(!dictation.start(for: firstSet))
}

@MainActor
@Test func aHandsFreePressRecordsWhenItWentLiveWasHeardAndStopped() async throws {
    let journal = DictationJournal(storage: .inMemory)
    let (dictation, transcriber, clock) = makeHandsFreeDictation(holdingStart: true, keepingRecordsIn: journal)
    let listening = Task { await dictation.listenUntilQuiet(for: firstSet, on: .headless) { squat } }
    await transcriber.starting.waitUntilHeld(orRecord: "The transcriber never started")
    clock.advance(by: .milliseconds(150))
    transcriber.starting.release()
    await clock.waitUntilSleeping(until: .milliseconds(150) + frame, orRecord: "It never waited for a first word")

    await clock.advanceUntilSleeping(by: .milliseconds(250), orRecord: "It stopped listening before a word")
    transcriber.say("135 for")
    await clock.advanceUntilSleeping(by: .milliseconds(600), orRecord: "It stopped listening inside the window")
    transcriber.say("135 for 4 at 9")
    await clock.advanceUntilSleeping(by: .milliseconds(1150), orRecord: "It never waited out the silence")
    clock.advance(by: .milliseconds(50))
    _ = await outcome(of: listening, from: dictation)

    let record = try #require(try await journal.records().first)
    #expect(record.surface == .headless)
    #expect(
        record.timeline
            == DictationRecord.Timeline(
                live: 150,
                firstHeard: 400,
                lastHeard: 1000,
                ended: 2200,
                liveFinished: 2200,
                earlyReadAsked: nil,
                recordingAsked: nil,
                recordingRead: nil,
                recordingDropped: nil,
                decided: 2200
            )
    )
    #expect(record.decided?.end == .silence)
    #expect(record.decided?.live.captionChanges == 2)
}

@MainActor
@Test func aHandsFreePressThatHeardNothingOrNeverStartedNeverAsksTheRecordingEngine() async throws {
    let journal = DictationJournal(storage: .inMemory)
    let (unheard, _, clock) = makeHandsFreeDictation(keepingRecordsIn: journal)
    let listening = Task { await unheard.listenUntilQuiet(for: firstSet, on: .card) { squat } }
    await clock.waitUntilSleeping(until: frame, orRecord: "It never listened")
    clock.advance(by: cap)
    _ = await listening.value
    let (unstarted, _, _) = makeHandsFreeDictation(failingToStart: .microphoneDenied, keepingRecordsIn: journal)
    _ = await unstarted.listenUntilQuiet(for: firstSet, on: .card) { squat }

    let records = try await journal.records().compactMap(\.decided)
    #expect(records.map(\.end) == [.nothingHeard, .unstarted])
    #expect(records.map(\.live.failure) == [.nothingHeard, .microphoneDenied])
    #expect(records.map(\.recording.result) == [.missing(.notAsked), .missing(.notAsked)])
    #expect(records.map(\.decision.outcome.kind) == [.rejected, .rejected])
}

@MainActor
private func makeHandsFreeDictation(
    holdingStart: Bool = false,
    failingToStart failure: SetTranscriberError? = nil,
    keepingRecordsIn journal: DictationJournal = DictationJournal(storage: .inMemory)
) -> (SetDictation, OpenMicTranscriber, ManualListeningClock) {
    let transcriber = OpenMicTranscriber(holdingStart: holdingStart, failingToStart: failure)
    let clock = ManualListeningClock()
    let reader = CannedRecordingTranscriber(answering: .missing(.modelNotReady(.absent)))
    return (SetDictation(transcriber: transcriber, reader: reader, journal: journal, clock: clock), transcriber, clock)
}
