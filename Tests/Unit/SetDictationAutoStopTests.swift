import Testing

@testable import WorkoutTracker

private let squat = SpokenSetContext(draft: SetLogDraft(weight: .pounds(185), reps: 5, rpe: .eight), previous: nil)
private let firstSet = ActiveSetID(exerciseOrder: 0, setIndex: 0)
private let window = SetDictation.silenceWindow
private let cap = SetDictation.listeningCap

@Test(
    "Listening stops the silence window after the last word, or at the cap after the mic went live",
    arguments: [
        (Duration.seconds(1), nil, Duration.seconds(1), SetDictation.AutoStop.wake(at: .seconds(1) + window)),
        (.seconds(1), nil, .seconds(1) + cap - .milliseconds(500), .wake(at: .seconds(1) + cap)),
        (.seconds(1), nil, .seconds(1) + cap, .stop(.nothingHeard)),
        (.seconds(1), .seconds(2), .milliseconds(2500), .wake(at: .seconds(2) + window)),
        (.seconds(1), .seconds(2), .seconds(2) + window, .stop(.silence)),
        (.seconds(1), .seconds(1) + cap - window, .seconds(1) + cap, .stop(.silence)),
        (.seconds(1), .seconds(8), .milliseconds(8500), .wake(at: .seconds(1) + cap)),
        (.seconds(1), .seconds(8), .seconds(1) + cap, .stop(.cap))
    ] as [(Duration, Duration?, Duration, SetDictation.AutoStop)]
)
func listeningStopsOnItsOwn(liveAt: Duration, lastHeardAt: Duration?, now: Duration, step: SetDictation.AutoStop) {
    #expect(SetDictation.autoStop(at: now, liveAt: liveAt, lastHeardAt: lastHeardAt) == step)
}

@MainActor
@Test func handsFreeListeningEndsTheSilenceWindowAfterTheLastWordAndWritesWhatWasHeard() async {
    let (dictation, transcriber, clock) = makeHandsFreeDictation()
    let listening = Task { await dictation.listenUntilQuiet(for: firstSet, on: .card) { squat } }
    await clock.waitUntilSleeping(until: window, orRecord: "Nothing heard, it never looked again a silence window on")

    clock.advance(by: .milliseconds(500))
    transcriber.say("135 for")
    clock.advance(by: .milliseconds(1000))
    await clock.waitUntilSleeping(until: .milliseconds(1700), orRecord: "It never waited out the silence after 135 for")
    transcriber.say("135 for 4 at 9")
    clock.advance(by: .milliseconds(1100))
    await clock.waitUntilSleeping(until: .milliseconds(2700), orRecord: "It never waited out the silence after the last word")
    #expect(dictation.state == .listening(firstSet, heard: "135 for 4 at 9"), "still listening inside the window")

    clock.advance(by: .milliseconds(100))

    let logged = SetDictation.Outcome.logged(SetLog(weight: .pounds(135), reps: 4, rpe: .nine), heard: "135 for 4 at 9")
    #expect(await listening.value == logged)
    #expect(dictation.state == .finished(firstSet, logged))
}

@MainActor
@Test func aTranscriptHeardAgainUnchangedDoesNotRestartTheSilenceWindow() async {
    let (dictation, transcriber, clock) = makeHandsFreeDictation()
    let listening = Task { await dictation.listenUntilQuiet(for: firstSet, on: .card) { squat } }
    await clock.waitUntilSleeping(until: window, orRecord: "It never started waiting")

    clock.advance(by: .milliseconds(500))
    transcriber.say("skip")
    clock.advance(by: .milliseconds(300))
    transcriber.say("skip")
    clock.advance(by: .milliseconds(400))

    await clock.waitUntilSleeping(until: .milliseconds(1700), orRecord: "The unchanged skip restarted the silence window")
    clock.advance(by: window)
    #expect(await listening.value == .skipped(heard: "skip"))
}

@MainActor
@Test func handsFreeListeningThatHearsNothingByTheCapWritesNothing() async {
    let (dictation, transcriber, clock) = makeHandsFreeDictation()
    let listening = Task { await dictation.listenUntilQuiet(for: firstSet, on: .card) { squat } }
    await clock.waitUntilSleeping(until: window, orRecord: "It never started waiting")

    clock.advance(by: cap - .milliseconds(100))
    await clock.waitUntilSleeping(until: cap, orRecord: "It never waited for the cap")
    clock.advance(by: .milliseconds(100))

    let nothingHeard = SetDictation.Outcome.rejected(.transcriber(.nothingHeard), heard: "")
    #expect(await listening.value == nothingHeard)
    #expect(dictation.state == .finished(firstSet, nothingHeard))
    #expect(transcriber.wasCancelled)
    #expect(transcriber.finishes == 0)
}

@MainActor
@Test func theCapEndsHandsFreeListeningThatNeverFallsQuiet() async {
    let (dictation, transcriber, clock) = makeHandsFreeDictation()
    let listening = Task { await dictation.listenUntilQuiet(for: firstSet, on: .card) { squat } }
    await clock.waitUntilSleeping(until: window, orRecord: "It never started waiting")

    clock.advance(by: cap - .milliseconds(500))
    transcriber.say("skip")
    await clock.waitUntilSleeping(until: cap, orRecord: "It never waited for the cap")
    clock.advance(by: .milliseconds(500))

    #expect(await listening.value == .skipped(heard: "skip"))
    #expect(transcriber.finishes == 1)
}

@MainActor
@Test func theCapCountsFromWhenTheMicWentLiveNotFromThePress() async {
    let (dictation, transcriber, clock) = makeHandsFreeDictation(holdingStart: true)
    let listening = Task { await dictation.listenUntilQuiet(for: firstSet, on: .card) { squat } }
    await transcriber.starting.waitUntilHeld(orRecord: "The transcriber never started")

    clock.advance(by: cap + .seconds(2))
    transcriber.starting.release()

    await clock.waitUntilSleeping(until: cap + .seconds(2) + window, orRecord: "Preparing counted against the cap")
    #expect(dictation.state == .listening(firstSet, heard: ""))
    await dictation.cancel()
    clock.advance(by: window)
    #expect(await listening.value == nil)
}

@MainActor
@Test func aTapOnTheMicFinishesHandsFreeListeningAndTheAutoStopWritesNothingMore() async {
    let (dictation, transcriber, clock) = makeHandsFreeDictation()
    let listening = Task { await dictation.listenUntilQuiet(for: firstSet, on: .card) { squat } }
    await clock.waitUntilSleeping(until: window, orRecord: "It never started waiting")
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
    await clock.waitUntilSleeping(until: .milliseconds(150) + window, orRecord: "It never waited for a first word")

    clock.advance(by: .milliseconds(250))
    transcriber.say("135 for")
    clock.advance(by: .milliseconds(600))
    transcriber.say("135 for 4 at 9")
    clock.advance(by: .milliseconds(350))
    await clock.waitUntilSleeping(until: .milliseconds(1000) + window, orRecord: "It never waited out the silence")
    clock.advance(by: .milliseconds(850))
    _ = await listening.value

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
    await clock.waitUntilSleeping(until: window, orRecord: "It never started waiting")
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

/// A transcriber that hears whatever the test says, when the test says it.
@MainActor
private final class OpenMicTranscriber: SetTranscriber {
    let starting: HeldCall
    private(set) var finishes = 0
    private(set) var wasCancelled = false
    private let startFailure: SetTranscriberError?
    private var hearing: (@MainActor (String) -> Void)?
    private var heard = ""

    init(holdingStart: Bool, failingToStart failure: SetTranscriberError?) {
        starting = HeldCall(parks: holdingStart ? 1 : 0)
        startFailure = failure
    }

    func start(hearing: @escaping @MainActor (String) -> Void, recording _: DictationRecorder) async throws(SetTranscriberStartError) {
        await starting.hold()
        if let startFailure { throw SetTranscriberStartError(startFailure) }
        self.hearing = hearing
    }

    func say(_ words: String) {
        heard = words
        hearing?(words)
    }

    func finish() async throws(SetTranscriberError) -> [String] {
        finishes += 1
        hearing = nil
        return heard.isEmpty ? [] : [heard]
    }

    func cancel() async {
        wasCancelled = true
        hearing = nil
    }
}
