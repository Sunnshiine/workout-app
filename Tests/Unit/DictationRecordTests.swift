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
@Test(arguments: DictationRecordFixtures.lines.prefix(2))
func aDecidedPressIsDecidedTheSameAgainFromItsRecord(line: String) throws {
    let press = try decided(try decoded(line))
    let hearing = Hearing(
        live: .transcripts(press.live.candidates),
        recording: RecordingDecode(result: press.recording.result, timings: nil).transcript
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
        recordingRead: nil,
        recordingDropped: dropped,
        decided: decided
    )
}

@Test(arguments: [
    (timeline(live: 100, liveFinished: 1100, decided: 1500), nil),
    (timeline(live: 100, liveFinished: 1400, decided: 1600), DictationRecord.WaitCause.liveFinalize),
    (timeline(live: 100, liveFinished: 1050, decided: 1700), .recordingTranscript),
    (timeline(live: 100, liveFinished: 1050, dropped: 2500, decided: 2500), .decisionDeadline),
    (timeline(live: 1600, liveFinished: 1650, decided: 1700), .liveStart),
    (timeline(live: nil, liveFinished: nil, decided: 1900), .liveStart)
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
