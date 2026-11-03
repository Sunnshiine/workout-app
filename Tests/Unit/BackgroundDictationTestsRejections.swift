import Testing

@testable import WorkoutTracker

private let firstSet = ActiveSetID(exerciseOrder: 0, setIndex: 0)
private let cap = SetDictation.listeningCap

@MainActor
@Test func aValueStillMissingWritesNothingAndSaysWhich() async throws {
    let harness = try await BackgroundDictationHarness(hearing: ["RPE 9"])

    let outcome = await harness.runUntilQuiet()

    #expect(outcome == .notLogged(.missingValues(SetLogDraft(weight: nil, reps: 5, rpe: .nine), heard: "RPE 9"), at: firstSet))
    #expect(harness.liveActivity.readbacks == [.listening, .notLogged("“RPE 9”, no weight")])
    try harness.expectNothingWritten()
}

@MainActor
@Test func aSetOnlyTheLiveTranscriptsAlternativesReadWritesNothing() async throws {
    let harness = try await BackgroundDictationHarness(hearing: ["um", "185 for 5 at 8"])

    let outcome = await harness.runUntilQuiet()

    #expect(outcome == .notLogged(.rejected(.spokenSet(.nothingHeard), heard: "um"), at: firstSet))
    #expect(harness.liveActivity.readbacks == [.listening, .notLogged("Nothing heard")])
    try harness.expectNothingWritten()
}

/// A fill no locked card can take, which only a rule that lets the Live Transcript fill decides.
@Test func aCompleteFillReadsBackWhatWasHeardAndAMissingValueSaysWhich() {
    let complete = BackgroundDictation.NotLogged(filled: SetLogDraft(weight: .pounds(185), reps: 5, rpe: .eight), heard: "185 for 5 at 8")
    let missing = BackgroundDictation.NotLogged(filled: SetLogDraft(weight: .pounds(185), reps: 5, rpe: nil), heard: "185 for 5")

    #expect(complete.caption == "“185 for 5 at 8”")
    #expect(missing.caption == "“185 for 5”, no RPE")
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
@Test func aPressWithNoRecordingTranscriptWritesNothingAndSaysWhyThoughTheLiveTranscriptReadsASet() async throws {
    let harness = try await BackgroundDictationHarness(
        transcriber: CannedSetTranscriber(candidates: ["235 for 5 at 7"]),
        reading: .missing(.modelNotReady(.loading))
    )

    let outcome = await harness.runUntilQuiet()

    #expect(outcome == .notLogged(.rejected(.recording(.modelNotReady(.loading)), heard: ""), at: firstSet))
    #expect(harness.liveActivity.readbacks == [.listening, .notLogged("Speech model was loading, say it again")])
    try harness.expectNothingWritten()
    let press = try #require(try await harness.app.dictationJournal.records().first?.decided)
    #expect(press.decision.outcome.rejection?.reason == .speechModelNotReady)
}

@MainActor
@Test func nothingHeardByTheCapWritesNothing() async throws {
    let harness = try await BackgroundDictationHarness(hearing: [])

    let run = Task { await harness.background.run() }
    await harness.clock.waitUntilSleeping(until: VoiceActivity.frameDuration, orRecord: "It never started listening")
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
    let harness = try await BackgroundDictationHarness(transcriber: FailingSetTranscriber(error), reading: .missing(.notAsked))

    let outcome = await harness.background.run()

    #expect(outcome == .notLogged(.rejected(.transcriber(error), heard: ""), at: firstSet))
    #expect(harness.liveActivity.readbacks == [.listening, .notLogged("Open WorkoutTracker once to allow the mic")])
    try harness.expectNothingWritten()
}

@MainActor
@Test func listeningThatFailsAsksForAnUnlockAndRecordsWhatRefusedTheMic() async throws {
    let harness = try await BackgroundDictationHarness(
        transcriber: FailingSetTranscriber(.failed, refusal: DictationRecordFixtures.refusal),
        reading: .missing(.notAsked)
    )

    _ = await harness.background.run()

    #expect(harness.liveActivity.readbacks == [.listening, .notLogged("Couldn’t listen. Unlock to log")])
    try harness.expectNothingWritten()
    let record = try #require(try await harness.app.dictationJournal.records().first)
    #expect(record.surface == .headless)
    let press = try #require(record.decided)
    #expect(press.end == .unstarted)
    #expect(press.live.startRefusal == DictationRecordFixtures.refusal)
}

@MainActor
private final class FailingSetTranscriber: SetTranscriber {
    private let error: SetTranscriberError
    private let refusal: MicStartRefusal?

    init(_ error: SetTranscriberError, refusal: MicStartRefusal? = nil) {
        (self.error, self.refusal) = (error, refusal)
    }

    func start(hearing: @escaping @MainActor (String) -> Void, recording _: DictationRecorder) async throws(SetTranscriberStartError) {
        throw SetTranscriberStartError(error, refusal: refusal)
    }

    func finish() async throws(SetTranscriberError) -> [String] {
        throw error
    }

    func cancel() async {}
}
