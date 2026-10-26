import Testing

@testable import WorkoutTracker

private let squat = SpokenSetContext(draft: SetLogDraft(weight: .pounds(185), reps: 5, rpe: .eight), previous: nil)
private let firstSet = ActiveSetID(exerciseOrder: 0, setIndex: 0)
private let frame = VoiceActivity.frameDuration
/// -20 dBFS, 40 dB over the room.
private let loud = [Float](repeating: 0.1, count: VoiceActivity.frameSamples)
/// -60 dBFS.
private let quiet = [Float](repeating: 0.001, count: VoiceActivity.frameSamples)

/// When the `frames`th frame of the press's audio ended, in whole milliseconds since it went live.
private func ms(frames: Int) -> Int {
    (frame * frames).wholeMilliseconds
}

/// A hands-free press listening from the clock's zero, whose recording engine holds each read until
/// the test answers it.
@MainActor
private struct HandsFreePress {
    let dictation: SetDictation
    let mic: OpenMicTranscriber
    let reader = HeldRecordingTranscriber()
    let clock = ManualListeningClock()
    let journal = DictationJournal(storage: .inMemory)
    let listening: Task<SetDictation.Outcome?, Never>

    init() async {
        let mic = OpenMicTranscriber(holdingStart: false, failingToStart: nil)
        let dictation = SetDictation(transcriber: mic, reader: reader, journal: journal, clock: clock)
        self.dictation = dictation
        self.mic = mic
        listening = Task { await dictation.listenUntilQuiet(for: firstSet, on: .card) { squat } }
        await clock.waitUntilSleeping(until: frame, orRecord: "It never listened")
        await hear(3, of: quiet)
    }

    /// `count` frames of `audio`, each recorded as the mic's tap hands it over and a frame of time
    /// on, for listening to look at before the next.
    func hear(_ count: Int, of audio: [Float]) async {
        for _ in 0..<count {
            mic.play(audio)
            await clock.advanceUntilSleeping(by: frame, orRecord: "Listening stopped on a frame it should have listened on")
        }
    }

    /// One more frame of `audio`, which ends listening.
    func hearTheLastFrame(of audio: [Float]) {
        mic.play(audio)
        clock.advance(by: frame)
    }

    /// Answers the read in flight with `transcript`, and waits for listening to look at it.
    func answerTheRead(hearing transcript: String) async {
        let sleeps = clock.sleeps
        reader.answer(hearing: transcript)
        if await waitUntil({ clock.sleeps > sleeps }, orRecord: "Listening never looked at the read") { return }
        await dictation.cancel()
    }

    /// The outcome once listening has ended, or nil, cancelling the press, when it never does.
    func outcome() async -> SetDictation.Outcome? {
        let ended = await waitUntil({ if case .finished = dictation.state { true } else { false } }, orRecord: "Listening never ended")
        if !ended { await dictation.cancel() }
        return await listening.value
    }

    func record() async throws -> DictationRecord {
        try #require(try await journal.records().first)
    }
}

@MainActor
@Test func aWholeSetAndA341MillisecondPauseStopListeningAndTheEarlyReadDecides() async throws {
    let press = await HandsFreePress()
    await press.hear(10, of: loud)
    press.mic.say("225 for 3 at 9")
    await press.hear(3, of: quiet)
    #expect(press.reader.transcribes == 0, "no read before 341 ms of Pause")

    press.mic.play(quiet)
    press.clock.advance(by: frame)
    await press.reader.waitUntilCalled()
    press.clock.advance(by: .milliseconds(50))
    press.reader.answer(hearing: "225 for 3 at 9.5")

    #expect(await press.outcome() == .logged(SetLog(weight: .pounds(225), reps: 3, rpe: .ninePointFive), heard: "225 for 3 at 9.5"))
    #expect(press.reader.transcribes == 1, "the press ends on the early read, with no second read")
    let record = try await press.record()
    #expect(record.decided?.end == .wholeSet)
    #expect(record.timeline.earlyReadAsked == ms(frames: 17))
    #expect(record.timeline.recordingAsked == ms(frames: 17), "the press was decided with the read asked at the Pause")
    #expect(record.timeline.ended == ms(frames: 17) + 50)
}

@MainActor
@Test func aWholeSetWhoseRPEIsAWholeNumberWaitsA1024MillisecondPauseForAHalf() async throws {
    let press = await HandsFreePress()
    await press.hear(10, of: loud)
    press.mic.say("185 for 5 at 8")
    await press.hear(4, of: quiet)
    await press.reader.waitUntilCalled()
    await press.answerTheRead(hearing: "185 for 5 at 8")

    await press.hear(7, of: quiet)
    #expect(press.dictation.state == .listening(firstSet, heard: "185 for 5 at 8"), "still listening at 939 ms of Pause")
    press.hearTheLastFrame(of: quiet)

    #expect(await press.outcome() == .logged(SetLog(weight: .pounds(185), reps: 5, rpe: .eight), heard: "185 for 5 at 8"))
    #expect(press.reader.transcribes == 1)
    let record = try await press.record()
    #expect(record.decided?.end == .wholeSet)
    #expect(record.timeline.ended == ms(frames: 25))
}

@MainActor
@Test func speechAfterTheEarlyReadSendsTheNextPauseToANewRead() async throws {
    let press = await HandsFreePress()
    await press.hear(10, of: loud)
    await press.hear(4, of: quiet)
    await press.reader.waitUntilCalled()
    await press.answerTheRead(hearing: "185 for 5 at 8")
    await press.hear(2, of: quiet)

    await press.hear(3, of: loud)
    press.mic.say("185 for 5 at 8 and a half")
    await press.hear(4, of: quiet)
    await press.reader.waitUntilCalled(times: 2)
    press.reader.answer(hearing: "185 for 5 at 8 and a half")

    #expect(
        await press.outcome() == .logged(SetLog(weight: .pounds(185), reps: 5, rpe: .eightPointFive), heard: "185 for 5 at 8 and a half")
    )
    #expect(press.reader.samplesRead == [17, 26].map { $0 * VoiceActivity.frameSamples }, "the second read heard the half")
    #expect(try await press.record().decided?.end == .wholeSet)
}

@MainActor
@Test func aReadThatHeardPartOfASetKeepsListeningUntil1200MillisecondsOfPause() async throws {
    let press = await HandsFreePress()
    await press.hear(10, of: loud)
    press.mic.say("185 for 5")
    await press.hear(4, of: quiet)
    await press.reader.waitUntilCalled()
    await press.answerTheRead(hearing: "185 for 5")

    await press.hear(9, of: quiet)
    #expect(press.dictation.state == .listening(firstSet, heard: "185 for 5"), "still listening at 1109 ms of Pause")
    press.hearTheLastFrame(of: quiet)

    #expect(await press.outcome() == .logged(SetLog(weight: .pounds(185), reps: 5, rpe: .eight), heard: "185 for 5"))
    #expect(press.reader.transcribes == 1, "the early read heard all the athlete said, so the stop reads nothing new")
    let record = try await press.record()
    #expect(record.decided?.end == .silence)
    #expect(record.timeline.ended == ms(frames: 27))
}

/// The caption last changed after "185 for", so its silence window ends listening while the
/// athlete is still saying the rest.
@MainActor
@Test func aStopWhileTheAthleteSpeaksReadsTheWholeRecordingRatherThanTheEarlyRead() async throws {
    let press = await HandsFreePress()
    await press.hear(5, of: loud)
    press.mic.say("185 for")
    await press.hear(4, of: quiet)
    await press.reader.waitUntilCalled()
    await press.answerTheRead(hearing: "185 for")

    await press.hear(10, of: loud)
    press.hearTheLastFrame(of: loud)
    await press.reader.waitUntilCalled(times: 2)
    press.reader.answer(hearing: "185 for 5 at 8")

    #expect(await press.outcome() == .logged(SetLog(weight: .pounds(185), reps: 5, rpe: .eight), heard: "185 for 5 at 8"))
    #expect(press.reader.samplesRead == [12, 23].map { $0 * VoiceActivity.frameSamples })
    #expect(try await press.record().decided?.end == .silence)
}

@MainActor
@Test func aStopWithTheEarlyReadStillInFlightWaitsForThatRead() async throws {
    let press = await HandsFreePress()
    await press.hear(10, of: loud)
    press.mic.say("skip")
    await press.hear(4, of: quiet)
    await press.reader.waitUntilCalled()
    await press.hear(9, of: quiet)
    press.hearTheLastFrame(of: quiet)

    await waitUntil({ press.dictation.state == .deciding(firstSet, heard: "skip") }, orRecord: "The press never stopped to decide")
    press.reader.answer(hearing: "skip")

    #expect(await press.outcome() == .skipped(heard: "skip"))
    #expect(press.reader.transcribes == 1)
    #expect(!press.reader.wasCancelled)
    #expect(try await press.record().decided?.recording.result == .heard("skip", segments: []))
}

@MainActor
@Test func aHeldPressReadsItsWholeRecordingOnceAtRelease() async {
    let mic = OpenMicTranscriber(holdingStart: false, failingToStart: nil)
    let reader = HeldRecordingTranscriber()
    let dictation = SetDictation(
        transcriber: mic,
        reader: reader,
        journal: DictationJournal(storage: .inMemory),
        clock: ManualListeningClock()
    )
    dictation.start(for: firstSet)
    await waitUntil({ dictation.state == .listening(firstSet, heard: "") }, orRecord: "The mic never went live")

    for audio in Array(repeating: quiet, count: 3) + Array(repeating: loud, count: 10) + Array(repeating: quiet, count: 14) {
        mic.play(audio)
    }
    mic.say("skip")
    let finishing = Task { await dictation.finish(for: firstSet, in: squat) }
    await reader.waitUntilCalled()
    reader.answer(hearing: "skip")

    #expect(await finishing.value == .skipped(heard: "skip"))
    #expect(reader.samplesRead == [27 * VoiceActivity.frameSamples])
}
