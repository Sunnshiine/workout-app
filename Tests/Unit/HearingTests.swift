import Foundation
import Testing

@testable import WorkoutTracker

private let squat = SpokenSetContext(draft: SetLogDraft(weight: .pounds(185), reps: 5, rpe: .eight), previous: nil)
private let firstSet = ActiveSetID(exerciseOrder: 0, setIndex: 0)

private func logged(_ pounds: Double, _ reps: Int, _ rpe: RPE, heard: String) -> SetDictation.Outcome {
    .logged(SetLog(weight: .pounds(pounds), reps: reps, rpe: rpe), heard: heard)
}

private func read(_ transcript: String) -> RecordingDecode.Result {
    .heard(transcript, segments: [])
}

private func filled(_ pounds: Double, _ reps: Int, _ rpe: RPE?, heard: String) -> SetDictation.Outcome {
    .filled(SetLogDraft(weight: .pounds(pounds), reps: reps, rpe: rpe), heard: heard)
}

/// One press heard by both engines, each engine's outcome on its own, and `gate`'s outcome for it.
private struct Press: Sendable, CustomTestStringConvertible {
    let testDescription: String
    let recordingRead: RecordingDecode.Result
    let liveTranscript: LiveHearing
    let recording: SetDictation.Outcome?
    let live: SetDictation.Outcome
    let agreement: EngineAgreement
    let gate: SetDictation.Outcome

    var hearing: Hearing { Hearing(live: liveTranscript, recording: recordingRead) }
}

private let table: [Press] = [
    Press(
        testDescription: "no Recording Transcript by the Decision Deadline",
        recordingRead: .missing(.late),
        liveTranscript: .transcripts(["135 for 4 at 9"]),
        recording: nil,
        live: logged(135, 4, .nine, heard: "135 for 4 at 9"),
        agreement: .liveOnly,
        gate: logged(135, 4, .nine, heard: "135 for 4 at 9")
    ),
    Press(
        testDescription: "both write one Set Log",
        recordingRead: read("185 for 5 at 8."),
        liveTranscript: .transcripts(["185 for five at eight"]),
        recording: logged(185, 5, .eight, heard: "185 for 5 at 8."),
        live: logged(185, 5, .eight, heard: "185 for five at eight"),
        agreement: .agreed,
        gate: logged(185, 5, .eight, heard: "185 for 5 at 8.")
    ),
    Press(
        testDescription: "both skip",
        recordingRead: read("Skip."),
        liveTranscript: .transcripts(["skip"]),
        recording: .skipped(heard: "Skip."),
        live: .skipped(heard: "skip"),
        agreement: .agreed,
        gate: .skipped(heard: "Skip.")
    ),
    Press(
        testDescription: "each writes a different RPE",
        recordingRead: read("1258 for 13 at 8.5."),
        liveTranscript: .transcripts(["1258 for 13 at 6.5."]),
        recording: logged(1258, 13, .eightPointFive, heard: "1258 for 13 at 8.5."),
        live: logged(1258, 13, .sixPointFive, heard: "1258 for 13 at 6.5."),
        agreement: .disagreed,
        gate: filled(1258, 13, .eightPointFive, heard: "1258 for 13 at 8.5.")
    ),
    Press(
        testDescription: "a skip against a Set Log",
        recordingRead: read("skip"),
        liveTranscript: .transcripts(["185 for 5 at 8"]),
        recording: .skipped(heard: "skip"),
        live: logged(185, 5, .eight, heard: "185 for 5 at 8"),
        agreement: .disagreed,
        gate: .rejected(.spokenSet(.ambiguous), heard: "skip")
    ),
    Press(
        testDescription: "the live engine failed",
        recordingRead: read("Skip."),
        liveTranscript: .failed(.nothingHeard, caption: ""),
        recording: .skipped(heard: "Skip."),
        live: .rejected(.transcriber(.nothingHeard), heard: ""),
        agreement: .recordingAlone,
        gate: .skipped(heard: "Skip.")
    ),
    Press(
        testDescription: "the Live Transcript cut off its RPE",
        recordingRead: read("135 for 8 at 9."),
        liveTranscript: .transcripts(["135 for 8 at"]),
        recording: logged(135, 8, .nine, heard: "135 for 8 at 9."),
        live: filled(135, 8, nil, heard: "135 for 8 at"),
        agreement: .recordingAlone,
        gate: logged(135, 8, .nine, heard: "135 for 8 at 9.")
    ),
    Press(
        testDescription: "the Recording Transcript cut off its RPE, which the Live Transcript never settles",
        recordingRead: read("185 for 5 at"),
        liveTranscript: .transcripts(["185 for 5 at 8"]),
        recording: filled(185, 5, nil, heard: "185 for 5 at"),
        live: logged(185, 5, .eight, heard: "185 for 5 at 8"),
        agreement: .liveFills,
        gate: filled(185, 5, .eight, heard: "185 for 5 at 8")
    ),
    Press(
        testDescription: "the Recording Transcript is a Set no lifter logs",
        recordingRead: read("15.68 for 10 at 8.5."),
        liveTranscript: .transcripts(["1568 for 10 at 8.5."]),
        recording: .rejected(.spokenSet(.implausible(.weight)), heard: "15.68 for 10 at 8.5."),
        live: logged(1568, 10, .eightPointFive, heard: "1568 for 10 at 8.5."),
        agreement: .liveFills,
        gate: filled(1568, 10, .eightPointFive, heard: "1568 for 10 at 8.5.")
    ),
    Press(
        testDescription: "a rejected Recording Transcript against a fill",
        recordingRead: read("100 kilos for 5."),
        liveTranscript: .transcripts(["185 for 5 at"]),
        recording: .rejected(.spokenSet(.kilograms), heard: "100 kilos for 5."),
        live: filled(185, 5, nil, heard: "185 for 5 at"),
        agreement: .liveFills,
        gate: filled(185, 5, nil, heard: "185 for 5 at")
    ),
    Press(
        testDescription: "both fill",
        recordingRead: read("185 for 5 at"),
        liveTranscript: .transcripts(["135 for 8 at"]),
        recording: filled(185, 5, nil, heard: "185 for 5 at"),
        live: filled(135, 8, nil, heard: "135 for 8 at"),
        agreement: .neither,
        gate: filled(185, 5, nil, heard: "185 for 5 at")
    ),
    Press(
        testDescription: "a fill against a rejection",
        recordingRead: read("185 for 5 at"),
        liveTranscript: .transcripts(["100 kilos for 5"]),
        recording: filled(185, 5, nil, heard: "185 for 5 at"),
        live: .rejected(.spokenSet(.kilograms), heard: "100 kilos for 5"),
        agreement: .neither,
        gate: filled(185, 5, nil, heard: "185 for 5 at")
    ),
    Press(
        testDescription: "both rejected",
        recordingRead: read("100 kilos for 5."),
        liveTranscript: .failed(.failed, caption: "135 for"),
        recording: .rejected(.spokenSet(.kilograms), heard: "100 kilos for 5."),
        live: .rejected(.transcriber(.failed), heard: "135 for"),
        agreement: .neither,
        gate: .rejected(.spokenSet(.kilograms), heard: "100 kilos for 5.")
    )
]

@Test("Under every rule each engine's outcome is its own, and the pair falls in one row of the table", arguments: table)
private func eachEnginesOutcomeIsItsOwn(press: Press) {
    for rule in MergeRule.allCases {
        let decision = rule.decide(press.hearing, in: squat)

        #expect(decision.live == press.live, "\(rule)")
        #expect(decision.recording == press.recording, "\(rule)")
        #expect(decision.agreement == press.agreement, "\(rule)")
    }
}

@Test("gate: a write needs the Recording Transcript, and the Live Transcript reading another Set turns it into a fill", arguments: table)
private func gateChecksTheRecordingTranscriptWithTheLiveTranscript(press: Press) {
    #expect(MergeRule.gate.decide(press.hearing, in: squat).outcome == press.gate)
}

@Test("lead: the Recording Transcript decides a press it read, and the Live Transcript a press with none", arguments: table)
private func leadTakesTheRecordingTranscriptWhenThereIsOne(press: Press) {
    #expect(MergeRule.lead.decide(press.hearing, in: squat).outcome == press.recording ?? press.live)
}

@Test("liveOnly: the Live Transcript decides every press", arguments: table)
private func liveOnlyTakesTheLiveTranscript(press: Press) {
    #expect(MergeRule.liveOnly.decide(press.hearing, in: squat).outcome == press.live)
}

@Test("recordingOnly: the Recording Transcript decides every press, and a press with none writes nothing", arguments: table)
private func recordingOnlyTakesTheRecordingTranscript(press: Press) {
    let late = SetDictation.Outcome.rejected(.recording(.late), heard: "")

    #expect(MergeRule.recordingOnly.decide(press.hearing, in: squat).outcome == press.recording ?? late)
}

/// A press the Live Transcript reads as a whole Set, which the recording engine did not read, and
/// what the card and the Live Activity say of it.
private struct Unread: Sendable, CustomTestStringConvertible {
    let testDescription: String
    let read: RecordingDecode.Result
    let live: LiveHearing
    let card: String
    let lockScreen: String
}

private let unread: [Unread] = [
    Unread(
        testDescription: "the Speech Model still loading",
        read: .missing(.modelNotReady(.loading)),
        live: .transcripts(["185 for 5 at 8"]),
        card: "Speech model isn’t ready yet",
        lockScreen: "Speech model isn’t ready. Unlock to log"
    ),
    Unread(
        testDescription: "the Speech Model not downloaded",
        read: .missing(.modelNotReady(.absent)),
        live: .transcripts(["185 for 5 at 8"]),
        card: "Speech model isn’t ready yet",
        lockScreen: "Speech model isn’t ready. Unlock to log"
    ),
    Unread(
        testDescription: "a read still running at the Decision Deadline",
        read: .missing(.late),
        live: .transcripts(["185 for 5 at 8"]),
        card: "Took too long to hear you, say it again",
        lockScreen: "Took too long to hear you, say it again"
    ),
    Unread(
        testDescription: "a phone too hot to read",
        read: .missing(.tooHot),
        live: .transcripts(["185 for 5 at 8"]),
        card: "Phone is too hot to hear you",
        lockScreen: "Phone is too hot. Unlock to log"
    ),
    Unread(
        testDescription: "a read that failed",
        read: .missing(.failed("decoder")),
        live: .transcripts(["185 for 5 at 8"]),
        card: "Couldn’t hear that, say it again",
        lockScreen: "Couldn’t hear that, say it again"
    ),
    Unread(
        testDescription: "a read with no words in it",
        read: read(" "),
        live: .transcripts(["185 for 5 at 8"]),
        card: "Nothing heard",
        lockScreen: "Nothing heard"
    ),
    Unread(
        testDescription: "a recording too short to read",
        read: .missing(.nothingRecorded),
        live: .transcripts(["185 for 5 at 8"]),
        card: "Nothing heard",
        lockScreen: "Nothing heard"
    ),
    Unread(
        testDescription: "a mic the athlete turned off, never asked to read",
        read: .missing(.notAsked),
        live: .failed(.microphoneDenied, caption: ""),
        card: "Microphone is off in Settings",
        lockScreen: "Open WorkoutTracker once to allow the mic"
    )
]

@Test("recordingOnly: a press with no Recording Transcript writes nothing and says why", arguments: unread)
private func recordingOnlyNamesWhyAPressHasNoRecordingTranscript(press: Unread) {
    let outcome = MergeRule.recordingOnly.decide(Hearing(live: press.live, recording: press.read), in: squat).outcome

    guard case .rejected(let rejection, let heard) = outcome else {
        Issue.record("\(outcome) is not a rejection")
        return
    }
    #expect(SetCardDictation(.finished(firstSet, outcome), for: firstSet) == .rejected(caption: press.card))
    #expect(BackgroundDictation.NotLogged.rejected(rejection, heard: heard).caption == press.lockScreen)
}

@Test func aPressTheTwoEnginesHeardDifferentlyWritesWhatTheRecordingTranscriptRead() {
    let hearing = Hearing(live: .transcripts(["1258 for 13 at 6.5."]), recording: read("1258 for 13 at 8.5."))

    let decision = SetDictation.decision(of: hearing, in: squat)

    #expect(decision.outcome == logged(1258, 13, .eightPointFive, heard: "1258 for 13 at 8.5."))
    #expect(decision.agreement == .disagreed)
}

@Test func aRecordingTranscriptNoLifterLogsAsksForTheSetAgainThoughTheLiveTranscriptReadOne() {
    let hearing = Hearing(live: .transcripts(["1568 for 10 at 8.5."]), recording: read("15.68 for 10 at 8.5."))

    let outcome = SetDictation.decision(of: hearing, in: squat).outcome

    #expect(outcome == .rejected(.spokenSet(.implausible(.weight)), heard: "15.68 for 10 at 8.5."))
    #expect(SetCardDictation(.finished(firstSet, outcome), for: firstSet) == .rejected(caption: "“15.68 for 10 at 8.5.”, say it again"))
}
