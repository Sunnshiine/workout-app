import Foundation
import Testing

@testable import WorkoutTracker

/// Three presses as a journal holds them: one both engines agreed on, one decided by the Live
/// Transcript after the Recording Transcript missed the deadline, and one cancelled. Each is one
/// line once the source's line breaks are gone.
private let journal = [
    #"""
    {"app":{"build":"431","commit":"6aba617","version":"1.9"},"decision":{"agreement":"agreed",
    "byRule":{"gate":{"heard":"185 for 5 at 8.","kind":"logged","setLog":"185x5@8"},
    "lead":{"heard":"185 for 5 at 8.","kind":"logged","setLog":"185x5@8"},"liveOnly":{"heard":"185 for 5 at 8.",
    "kind":"logged","setLog":"185x5@8"},"recordingOnly":{"heard":"185 for 5 at 8.","kind":"logged",
    "setLog":"185x5@8"}},"live":{"heard":"185 for 5 at 8.","kind":"logged","setLog":"185x5@8"},
    "outcome":{"heard":"185 for 5 at 8.","kind":"logged","setLog":"185x5@8"},
    "recording":{"heard":"185 for 5 at 8.","kind":"logged","setLog":"185x5@8"},"rule":"lead"},
    "device":{"footprintMB":420,"lowPower":false,"model":"iPhone17,1","os":"26.1.0","thermal":"nominal"},
    "end":"released","id":"6F1C2D0E-0000-4000-8000-000000000001","live":{"candidates":["185 for 5 at 8.",
    "185 for five at 8."],"captionChanges":7},"longestMainThreadStallMs":11,"pressedAt":"2026-10-19T17:02:11Z",
    "recording":{"audioSeconds":2.31,"decodeMs":{"decodeLoop":188,"encode":61,"fallbacks":0,"mel":4,"queued":0,
    "tokens":9,"total":262},"modelAtEnd":"ready","modelAtPress":"ready","segments":[{"avgLogprob":-0.11,
    "compressionRatio":1.07,"noSpeechProb":0.01,"temperature":0}],"transcript":"185 for 5 at 8.",
    "truncated":false},"schema":1,"set":{"address":"w1d1.e0.s0","block":"Block 27","draft":{"reps":5,"rpe":8,
    "weight":"185"},"exercise":"Back Squat","previous":"185x5@7"},"surface":"card","timelineMs":{"decided":3368,
    "ended":3104,"firstHeard":640,"lastHeard":1902,"live":182,"liveFinished":3131,"recordingRead":3366}}
    """#,
    #"""
    {"app":{"build":"431","version":"1.9"},"decision":{"agreement":"liveOnly",
    "byRule":{"gate":{"heard":"same again","kind":"logged","setLog":"BWx12@7.5"},"lead":{"heard":"same again",
    "kind":"logged","setLog":"BWx12@7.5"},"liveOnly":{"heard":"same again","kind":"logged","setLog":"BWx12@7.5"},
    "recordingOnly":{"heard":"","kind":"rejected","rejection":{"reason":"nothingHeard"}}},
    "live":{"heard":"same again","kind":"logged","setLog":"BWx12@7.5"},"outcome":{"heard":"same again",
    "kind":"logged","setLog":"BWx12@7.5"},"rule":"lead"},"device":{"footprintMB":388,"lowPower":true,
    "model":"iPhone16,2","os":"26.0.1","thermal":"fair"},"end":"silence",
    "id":"6F1C2D0E-0000-4000-8000-000000000002","live":{"candidates":["same again"],"captionChanges":2},
    "longestMainThreadStallMs":4,"pressedAt":"2026-10-19T17:05:40Z","recording":{"audioSeconds":3.1,"miss":"late",
    "modelAtEnd":"ready","modelAtPress":"ready","truncated":false},"schema":1,"set":{"address":"w1d1.e2.s1",
    "block":"Block 27","draft":{"reps":12,"rpe":7.5,"weight":"BW"},"exercise":"Pull Up","previous":"BWx12@7.5"},
    "surface":"headless","timelineMs":{"decided":4200,"ended":2700,"firstHeard":900,"lastHeard":1500,"live":150,
    "liveFinished":2760,"recordingDropped":4200}}
    """#,
    #"""
    {"app":{"build":"431","version":"1.9"},"device":{"footprintMB":401,"lowPower":false,"model":"iPhone17,1",
    "os":"26.1.0","thermal":"nominal"},"end":"cancelled","id":"6F1C2D0E-0000-4000-8000-000000000003",
    "longestMainThreadStallMs":3,"pressedAt":"2026-10-19T17:09:02Z","schema":1,"surface":"card",
    "timelineMs":{"ended":800,"live":120}}
    """#
].map { $0.replacingOccurrences(of: "\n", with: "") }

private func decoded(_ line: String) throws -> DictationRecord {
    try DictationRecord.lineDecoder().decode(DictationRecord.self, from: Data(line.utf8))
}

private func decided(_ record: DictationRecord) throws -> DictationRecord.Decided {
    guard case .decided(let decided) = record.ending else {
        Issue.record("The press was cancelled")
        throw CancellationError()
    }
    return decided
}

@Test(arguments: journal)
func aRecordReadsBackAsItWasWritten(line: String) throws {
    let encoded = try DictationRecord.lineEncoder().encode(try decoded(line))

    #expect(String(bytes: encoded, encoding: .utf8) == line)
}

@Test func aCancelledPressDecidedNothing() throws {
    #expect(try decoded(journal[2]).ending == .cancelled)
}

/// Replay decides a recorded press again from what the engines heard and what the card showed, so
/// both must come back from the record exactly.
@Test(arguments: journal.prefix(2))
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
    let future = journal[2].replacingOccurrences(of: #""schema":1"#, with: #""schema":2"#)

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
    let record = try decoded(journal[0])
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
