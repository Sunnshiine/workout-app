import Foundation
import Testing

@testable import WorkoutTracker

private let squat = SpokenSetContext(draft: SetLogDraft(weight: .pounds(185), reps: 5, rpe: .eight), previous: nil)
private let firstSet = ActiveSetID(exerciseOrder: 0, setIndex: 0)
private let noModel = CannedRecordingTranscriber(answering: .missing(.modelNotReady(.absent)))

@MainActor
@Test func aPressDecidesAndTheNextOneStartsWhileTheDiskHoldsItsRecord() async throws {
    let store = HeldDictationRecordStore()
    let journal = DictationJournal(store: store)
    let dictation = SetDictation(transcriber: CannedSetTranscriber(candidates: ["skip"]), reader: noModel, journal: journal)

    dictation.start(for: firstSet)
    #expect(await dictation.finish(for: firstSet, in: squat) == .skipped(heard: "skip"))
    await store.waitUntilAppending()
    dictation.dismiss()
    #expect(dictation.start(for: firstSet), "a stalled disk never holds the mic")
    #expect(await dictation.finish(for: firstSet, in: squat) == .skipped(heard: "skip"))

    #expect(store.ranOnMainThread == false)
    store.release()
    let records = try await journal.records()
    #expect(records.count == 2)
    #expect(Set(records.map(\.id)).count == 2, "each press has its own record")
}

/// The baseline every phone ships with: no recording engine model, and a mic that records nothing
/// for it, so the Live Transcript decides alone.
@MainActor
@Test func aCardPressWithNoRecordingEngineRecordsTheLiveTranscriptDecidingAlone() async throws {
    let journal = DictationJournal(storage: .inMemory)
    let clock = ManualListeningClock()
    let transcriber = HeldSetTranscriber(candidates: ["185 for 5 at 8"])
    let dictation = SetDictation(transcriber: transcriber, reader: noModel, journal: journal, clock: clock)

    dictation.start(for: firstSet)
    await transcriber.starting.waitUntilHeld(orRecord: "The transcriber never started")
    clock.advance(by: .milliseconds(120))
    transcriber.starting.release()
    await waitUntilListening(dictation)
    clock.advance(by: .milliseconds(80))
    let finishing = Task { await dictation.finish(for: firstSet, in: squat) }
    await transcriber.finishing.waitUntilHeld(orRecord: "The transcriber never finished")
    clock.advance(by: .milliseconds(45))
    transcriber.finishing.release()
    _ = await finishing.value

    let record = try #require(try await journal.records().first)
    #expect(record.surface == .card)
    #expect(record.pressedAt == Date(timeIntervalSince1970: 1_792_400_000))
    #expect(record.timeline.live == 120)
    #expect(record.timeline.firstHeard == 120)
    #expect(record.timeline.ended == 200)
    #expect(record.timeline.liveFinished == 245)
    #expect(record.timeline.decided == 245)
    #expect(record.isWithinTarget == true)
    let decided = try #require(record.decided)
    #expect(decided.end == .released)
    #expect(decided.set == squat)
    #expect(decided.live == DictationRecord.Live(candidates: ["185 for 5 at 8"], failure: nil, captionChanges: 1, startRefusal: nil))
    #expect(
        decided.recording
            == DictationRecord.Recording(
                version: .shipped,
                modelAtPress: .absent,
                modelAtEnd: .absent,
                result: .missing(.nothingRecorded),
                audioSeconds: 0,
                truncated: false,
                decodeMs: nil
            )
    )
    let logged = DictationRecord.Outcome(.logged(SetLog(weight: .pounds(185), reps: 5, rpe: .eight), heard: "185 for 5 at 8"))
    #expect(decided.decision.rule == .lead)
    #expect(decided.decision.agreement == .liveOnly)
    #expect(decided.decision.outcome == logged)
    #expect(decided.decision.recording == nil)
    #expect(decided.decision.byRule[.recordingOnly]?.kind == .rejected)
    #expect(decided.decision.byRule[.gate] == logged)
}

@MainActor
@Test func aCancelledPressIsRecordedDecidingNothing() async throws {
    let journal = DictationJournal(storage: .inMemory)
    let clock = ManualListeningClock()
    let dictation = SetDictation(transcriber: CannedSetTranscriber(candidates: ["skip"]), reader: noModel, journal: journal, clock: clock)

    dictation.start(for: firstSet)
    clock.advance(by: .milliseconds(300))
    await dictation.cancel()

    let record = try #require(try await journal.records().first)
    #expect(record.ending == .cancelled)
    #expect(record.timeline.ended == 300)
    #expect(record.timeline.decided == nil)
    #expect(record.waitCause == nil)
}

/// The Lock Screen's mic never goes live in a simulator, so the record must name what refused it.
@MainActor
@Test func aPressWhoseMicNeverWentLiveRecordsWhatRefusedIt() async throws {
    let journal = DictationJournal(storage: .inMemory)
    let dictation = SetDictation(transcriber: RefusingSetTranscriber(), reader: noModel, journal: journal)

    dictation.start(for: firstSet)
    #expect(await dictation.finish(for: firstSet, in: squat) == .rejected(.transcriber(.failed), heard: ""))

    let live = try #require(try await journal.records().first?.decided).live
    #expect(live.failure == .failed)
    #expect(live.startRefusal == DictationRecordFixtures.refusal)
}

@MainActor
private final class RefusingSetTranscriber: SetTranscriber {
    func start(hearing _: @escaping @MainActor (String) -> Void, recording _: DictationRecorder) async throws(SetTranscriberStartError) {
        throw SetTranscriberStartError(.failed, refusal: DictationRecordFixtures.refusal)
    }

    func finish() async throws(SetTranscriberError) -> [String] { [] }

    func cancel() async {}
}

@MainActor
private func waitUntilListening(_ dictation: SetDictation) async {
    for _ in 0..<10_000 {
        if case .listening = dictation.state { return }
        await Task.yield()
    }
    Issue.record("The press never went live")
}
