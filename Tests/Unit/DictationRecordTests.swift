import Foundation
import Testing

@testable import WorkoutTracker

private func decoded(_ line: String) throws -> DictationRecord {
    try DictationRecordFixtures.record(line)
}

private func decided(_ record: DictationRecord) throws -> DictationRecord.Decided {
    guard case .decided(let decided) = record.ending else {
        Issue.record("The press was cancelled")
        throw CancellationError()
    }
    return decided
}

@Test(arguments: DictationRecordFixtures.lines)
func aRecordReadsBackAsItWasWritten(line: String) throws {
    let encoded = try DictationRecord.lineEncoder().encode(try decoded(line))

    #expect(String(bytes: encoded, encoding: .utf8) == line)
}

@Test func aCancelledPressDecidedNothing() throws {
    #expect(try decoded(DictationRecordFixtures.lines[2]).ending == .cancelled)
}

/// Replay decides a recorded press again from what the engines heard and what the card showed, so
/// both must come back from the record exactly.
@Test(arguments: DictationRecordFixtures.decided)
func aDecidedPressIsDecidedTheSameAgainFromItsRecord(line: String) throws {
    let press = try decided(try decoded(line))
    let hearing = Hearing(
        live: .transcripts(press.live.candidates),
        recording: press.recording.result
    )

    for rule in MergeRule.allCases {
        let decision = rule.decide(hearing, in: press.set)
        #expect(DictationRecord.Outcome(decision.outcome) == press.decision.byRule[rule], "\(rule)")
        #expect(decision.agreement == press.decision.agreement)
    }
    #expect(press.decision.outcome == press.decision.byRule[press.decision.rule])
}

@Test func aRecordOfAnotherSchemaIsUnreadable() {
    let future = DictationRecordFixtures.lines[2].replacingOccurrences(of: #""schema":1"#, with: #""schema":2"#)

    #expect(throws: DecodingError.self) { try decoded(future) }
}

@Test(arguments: [
    (RecordingMiss.modelNotReady(.absent), #""modelNotReady.absent""#),
    (.modelNotReady(.downloading), #""modelNotReady.downloading""#),
    (.modelNotReady(.unloaded(.memoryWarning)), #""modelNotReady.unloaded.memoryWarning""#),
    (.late, #""late""#),
    (.failed("model crashed"), #""failed: model crashed""#),
    (.tooHot, #""tooHot""#),
    (.nothingRecorded, #""nothingRecorded""#),
    (.notAsked, #""notAsked""#)
])
func everyRecordingMissReadsBackAsWritten(miss: RecordingMiss, json: String) throws {
    #expect(String(bytes: try JSONEncoder().encode(miss), encoding: .utf8) == json)
    #expect(try JSONDecoder().decode(RecordingMiss.self, from: Data(json.utf8)) == miss)
}

private func timeline(live: Int?, liveFinished: Int?, dropped: Int? = nil, decided: Int) -> DictationRecord.Timeline {
    DictationRecord.Timeline(
        live: live,
        firstHeard: nil,
        lastHeard: nil,
        ended: 1000,
        liveFinished: liveFinished,
        earlyReadAsked: nil,
        recordingAsked: 1000,
        recordingRead: nil,
        recordingDropped: dropped,
        decided: decided
    )
}

@Test(arguments: [
    (timeline(live: 100, liveFinished: 1100, decided: 3000), nil),
    (timeline(live: 100, liveFinished: 2800, decided: 3100), DictationRecord.WaitCause.liveFinalize),
    (timeline(live: 100, liveFinished: 1050, decided: 3200), .recordingTranscript),
    (timeline(live: 100, liveFinished: 2050, decided: 3100), .liveFinalize),
    (timeline(live: 100, liveFinished: 1050, dropped: 6000, decided: 6000), .decisionDeadline),
    (timeline(live: 3100, liveFinished: 3150, decided: 3200), .liveStart),
    (timeline(live: nil, liveFinished: nil, decided: 3400), .liveStart)
])
func aWaitPastTheTargetNamesItsLargestShare(timeline: DictationRecord.Timeline, cause: DictationRecord.WaitCause?) throws {
    let record = try decoded(DictationRecordFixtures.lines[0])
    let waited = DictationRecord(
        id: record.id,
        pressedAt: record.pressedAt,
        app: record.app,
        surface: record.surface,
        ending: record.ending,
        timeline: timeline,
        device: record.device,
        longestMainThreadStallMs: 0
    )

    #expect(waited.waitCause == cause)
    #expect(waited.isWithinTarget == (cause == nil))
}

@Test func aPressRecordedBeforeBuildsKeptStartRefusalsStillReads() throws {
    let press = try decided(try decoded(DictationRecordFixtures.unstartedBeforeRefusals))

    #expect(press.live.failure == .failed)
    #expect(press.live.startRefusal == nil)
}

@Test func whatRefusedTheMicReadsBackAsItWasWritten() throws {
    let line = DictationRecordFixtures.unstartedWithRefusal
    let record = try decoded(line)

    #expect(try decided(record).live.startRefusal == DictationRecordFixtures.refusal)
    #expect(String(bytes: try DictationRecord.lineEncoder().encode(record), encoding: .utf8) == line)
}
