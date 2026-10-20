import Testing

@testable import WorkoutTracker

private let squat = SpokenSetContext(draft: SetLogDraft(weight: .pounds(185), reps: 5, rpe: .eight), previous: nil)
private let firstSet = ActiveSetID(exerciseOrder: 0, setIndex: 0)
private let said = "185 for 5 at 8"
private let liveLogs = SetDictation.Outcome.logged(SetLog(weight: .pounds(185), reps: 5, rpe: .eight), heard: said)
private let recordingSkips = RecordingDecode(result: .heard("skip", segments: []), timings: nil)
private let silence = [Float](repeating: 0, count: DictationRecorder.sampleRate)
private let deadline = Duration.milliseconds(1500)

/// A press that went live hearing `said` and ended: its live engine's finalize is parked until the
/// test releases it, and its recording, when there is one, is being read until the test answers.
@MainActor
private struct EndedPress {
    let dictation: SetDictation
    let live: HeldSetTranscriber
    let reader: HeldRecordingTranscriber
    let clock: ManualListeningClock
    let finishing: Task<SetDictation.Outcome?, Never>

    /// Lets the live engine hand over its transcripts.
    func finalizeLive() async {
        await live.finishing.waitUntilHeld(orRecord: "The live engine never finalized")
        live.finishing.release()
    }
}

@MainActor
private func endPress(recording: [Float] = silence) async -> EndedPress {
    let live = HeldSetTranscriber(candidates: [said], recording: recording)
    let reader = HeldRecordingTranscriber()
    let clock = ManualListeningClock()
    let dictation = SetDictation(transcriber: live, reader: reader, clock: clock)
    dictation.start(for: firstSet)
    #expect(reader.expectations == 1, "the recording engine hears of the press as it starts")
    await live.starting.waitUntilHeld(orRecord: "The live engine never started")
    live.starting.release()
    let finishing = Task { await dictation.finish(for: firstSet, in: squat) }
    if !recording.isEmpty { await reader.waitUntilCalled() }
    return EndedPress(dictation: dictation, live: live, reader: reader, clock: clock, finishing: finishing)
}

@MainActor
@Test func aRecordingTranscriptInByTheDeadlineDecidesThePress() async {
    let press = await endPress()
    #expect(press.dictation.state == .deciding(firstSet, heard: said))
    #expect(press.reader.ranOnMainThread == false, "the read never blocks the main thread")

    press.reader.answer(recordingSkips)
    await press.finalizeLive()

    #expect(await press.finishing.value == .skipped(heard: "skip"))
    #expect(press.dictation.state == .finished(firstSet, .skipped(heard: "skip")))
}

@MainActor
@Test func aReadStillRunningAtTheDeadlineIsCancelledAndTheLiveTranscriptDecides() async {
    let press = await endPress()
    await press.finalizeLive()
    await press.clock.waitUntilSleeping(until: deadline, orRecord: "The press never waited for the read")

    press.clock.advance(by: deadline)

    #expect(await press.finishing.value == liveLogs)
    #expect(press.reader.wasCancelled)
    #expect(press.reader.transcribes == 1)
}

@MainActor
@Test func theDeadlineCountsFromThePressEndNotFromTheLiveEnginesAnswer() async {
    let press = await endPress()
    press.clock.advance(by: .milliseconds(400))
    await press.finalizeLive()

    await press.clock.waitUntilSleeping(until: deadline, orRecord: "The deadline moved with the live engine")
    press.clock.advance(by: deadline - .milliseconds(400))

    #expect(await press.finishing.value == liveLogs)
    #expect(press.reader.wasCancelled)
}

@MainActor
@Test func aLiveTranscriptInPastTheDeadlineDecidesAtOnceAndDropsTheRead() async {
    let press = await endPress()
    press.clock.advance(by: .seconds(2))

    await press.finalizeLive()

    #expect(await press.finishing.value == liveLogs)
    #expect(press.reader.wasCancelled)
}

@MainActor
@Test func aDecodeAlreadyInDecidesEvenPastTheDeadline() async {
    let reader = HeldRecordingTranscriber()
    let clock = ManualListeningClock()
    let reading = SetDictation.Reading(of: DictationRecording(samples: silence, isTruncated: false), by: reader)
    await reader.waitUntilCalled()
    reader.answer(recordingSkips)
    #expect(await reading.decode(by: .seconds(1), on: clock) == recordingSkips)

    clock.advance(by: .seconds(2))

    #expect(await reading.decode(by: .seconds(1), on: clock) == recordingSkips)
    #expect(!reader.wasCancelled)
}

@MainActor
@Test func cancellingADecidingPressDoesNothing() async {
    let press = await endPress()

    await press.dictation.cancel()

    #expect(press.dictation.state == .deciding(firstSet, heard: said))
    #expect(!press.live.wasCancelled)
    press.reader.answer(recordingSkips)
    await press.finalizeLive()
    #expect(await press.finishing.value == .skipped(heard: "skip"))
}

@MainActor
@Test func aCaptionTheLiveEngineDeliversAsItFinalizesKeepsThePressDeciding() async {
    let press = await endPress()

    press.live.hear("185 for 5 at 8, nine")

    #expect(press.dictation.state == .deciding(firstSet, heard: "185 for 5 at 8, nine"))
    press.reader.answer(recordingSkips)
    await press.finalizeLive()
    _ = await press.finishing.value
}

@MainActor
@Test func aPressThatRecordedNothingIsDecidedByTheLiveTranscriptWithNoRead() async {
    let press = await endPress(recording: [])

    await press.finalizeLive()

    #expect(await press.finishing.value == liveLogs)
    #expect(press.reader.transcribes == 0)
}
