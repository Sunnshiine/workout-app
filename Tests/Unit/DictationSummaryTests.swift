import Foundation
import Testing

@testable import WorkoutTracker

private let bench = DictationScoring.Write.setLog("225x5@8")

/// The classes `scripts/measure-dictation.sh` scores with, row for row.
@Test(
    arguments: [
        (nil, DictationScoring.Truth.reject, DictationScoring.Class.correct),
        (nil, .write(bench), .nowrite),
        (nil, .write(.skip), .nowrite),
        (bench, .write(bench), .correct),
        (.skip, .write(.skip), .correct),
        (bench, .write(.setLog("225x5@9")), .wrong),
        (bench, .write(.skip), .wrong),
        (.skip, .write(bench), .wrong),
        (bench, .reject, .wrong),
        (.skip, .reject, .wrong)
    ] as [(DictationScoring.Write?, DictationScoring.Truth, DictationScoring.Class)]
)
func aPressIsScoredAgainstWhatTheAthleteMeant(
    written: DictationScoring.Write?,
    truth: DictationScoring.Truth,
    scored: DictationScoring.Class
) {
    #expect(DictationScoring.classify(written: written, truth: truth) == scored)
}

@Test func onlyALoggedOrSkippedOutcomeWrote() {
    let logged = DictationRecord.Outcome(.logged(SetLog(weight: .pounds(225), reps: 5, rpe: .eight), heard: "225 for 5 at 8"))
    let filled = DictationRecord.Outcome(.filled(SetLogDraft(weight: .pounds(225), reps: 5, rpe: nil), heard: "225 for 5"))
    let rejected = DictationRecord.Outcome(.rejected(.spokenSet(.nothingHeard), heard: ""))

    #expect(logged.written == bench)
    #expect(DictationRecord.Outcome(.skipped(heard: "skip")).written == .skip)
    #expect(filled.written == nil)
    #expect(rejected.written == nil)
}

@Test(arguments: [
    ([3, 1, 2], DictationSummary.Percentiles(p50: 2, p90: 3, p99: 3, max: 3)),
    ([7], DictationSummary.Percentiles(p50: 7, p90: 7, p99: 7, max: 7)),
    (Array(1...100), DictationSummary.Percentiles(p50: 50, p90: 90, p99: 99, max: 100))
])
func percentilesAreTheNearestRank(values: [Int], percentiles: DictationSummary.Percentiles) {
    #expect(DictationSummary.Percentiles(values) == percentiles)
}

@Test func noValuesHaveNoPercentiles() {
    #expect(DictationSummary.Percentiles([]) == nil)
}

private func press(live: [String], recording: String) throws -> DictationRecord.Decided {
    let echoed = try #require(try DictationRecordFixtures.record(DictationRecordFixtures.lines[4]).decided)
    return DictationRecord.Decided(
        end: echoed.end,
        set: echoed.set,
        live: DictationRecord.Live(candidates: live, failure: nil, captionChanges: 1),
        recording: DictationRecord.Recording(
            modelAtPress: .ready,
            modelAtEnd: .ready,
            result: .heard(recording, segments: []),
            audioSeconds: 2,
            truncated: false,
            decodeMs: nil
        ),
        decision: echoed.decision
    )
}

@Test(arguments: [
    (["135 for 5 at 8"], "62 pounds for 11 at 9.", true),
    (["1290 for 3"], "1,290 for 3.", false),
    (["135 for 3"], "1,290 for 3.", true),
    (["135 for 3 at 9"], "135 for 3 at 9.", false),
    (["135 for 5", "135 for 3 at 9"], "135 for 3 at 9.", false),
    ([], "62 pounds for 11 at 9.", false)
])
func aRecordingTranscriptEchoesThePromptWithANumeralTheLiveTranscriptLacks(live: [String], recording: String, echoes: Bool) throws {
    #expect(try press(live: live, recording: recording).echoes(.p1) == echoes)
}

@Test func aPressPastTheTargetCountsAsAMissAndOneWithinItDoesNot() throws {
    let within = try DictationRecordFixtures.record(DictationRecordFixtures.lines[0])
    let late = try DictationRecordFixtures.record(DictationRecordFixtures.lines[1])

    let summary = DictationSummary([within, within, late], unreadableLines: 0)

    #expect(summary.latency.withinTarget == 2)
    #expect(summary.latency.missedTarget == 1)
    #expect(summary.latency.waitCause == ["decisionDeadline": 1])
}

@Test func anEmptyJournalSummarizesAsNoPresses() throws {
    let summary = DictationSummary([], unreadableLines: 0)

    #expect(summary.presses == 0)
    #expect(summary.latency.waitMs == nil)
    #expect(summary.caveats == DictationSummary.caveats)
}
