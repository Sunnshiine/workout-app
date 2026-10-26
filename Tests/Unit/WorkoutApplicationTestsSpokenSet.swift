import Foundation
import Testing

@testable import WorkoutTracker

private func address(_ raw: String) throws -> SetAddress {
    try #require(SetAddress(raw))
}

@MainActor
@Test func sayingAWholeSetLogsItThroughTheSameWriteAsLog() async throws {
    let app = try await makeSelectedApp()

    let report = try app.say("185 for 5 at 8", at: address("w1d1.e0.s0"))

    #expect(report.heard == "185 for 5 at 8")
    #expect(report.outcome == .logged)
    #expect(report.setLog == "185x5@8")
    #expect(report.set.state == "logged")
    #expect(report.set.setLog == "185x5@8")
    #expect(report.pendingWriteCount == 1)
    _ = try await app.flush()
    #expect(try await app.sheet(tab: nil).cells["K15"] == "185x5@8")
}

@MainActor
@Test func sayingOnlyTheRPEOfAFreshBlocksFirstSetIsMissingTheWeightAndQueuesNothing() async throws {
    let app = try await makeSelectedApp()

    let report = try app.say("RPE 9", at: address("w1d1.e0.s0"))

    #expect(report.outcome == .missingValues)
    #expect(report.missing == ["weight"])
    #expect(report.setLog == nil)
    #expect(report.set.state == "pending")
    #expect(report.pendingWriteCount == 0)
    #expect(try app.sync.fetchPendingWriteRecords().isEmpty)
}

@MainActor
@Test func sayingTheRPEAfterSetOneLogsTheWeightTheCardEstimates() async throws {
    let app = try await makeSelectedApp()
    _ = try app.log(address("w1d1.e0.s0"), setLog: "185x5@8")
    let estimate = try #require(try app.session(nil).exercises[0].sets[1].loadSuggestion.weight)

    let report = try app.say("at 9", at: address("w1d1.e0.s1"))

    #expect(report.outcome == .logged)
    #expect(report.setLog == SetLog(weight: .pounds(estimate), reps: 5, rpe: .nine).formatted)
}

@MainActor
@Test func sayingSameAgainRepeatsTheNearestEarlierSetLogOfTheExercise() async throws {
    let app = try await makeSelectedApp()
    _ = try app.log(address("w1d1.e0.s0"), setLog: "185x5@8")

    let report = try app.say("same again", at: address("w1d1.e0.s1"))

    #expect(report.outcome == .logged)
    #expect(report.setLog == "185x5@8")
    #expect(report.pendingWriteCount == 2)
}

/// A typed Set Log takes any weight, so a spoken one does too, wherever the words show it hides no value.
@MainActor
@Test(
    "Saying a weight of 1,000 or more writes it to the Sheet as said",
    arguments: [
        ("1000 for 5 at 8", "1000x5@8"), ("1005 for 5 at 8", "1005x5@8"), ("1500 for 5 at 8", "1500x5@8"),
        ("1000 pounds for 1 at 10", "1000x1@10"), ("1,000 for 5 at 8", "1000x5@8"), ("1,005 pounds for 5 at 8", "1005x5@8"),
        ("one thousand for 5 at 8", "1000x5@8"), ("a thousand for 2 at 9", "1000x2@9")
    ]
)
func sayingAWeightOfAThousandOrMoreWritesItAsSaid(transcript: String, setLog: String) async throws {
    let app = try await makeSelectedApp()

    let report = try app.say(transcript, at: address("w1d1.e0.s0"))

    #expect(report.outcome == .logged)
    #expect(report.setLog == setLog)
    _ = try await app.flush()
    #expect(try await app.sheet(tab: nil).cells["K15"] == setLog)
}

@MainActor
@Test func sayingSkipSkipsTheSetAndWritesSkip() async throws {
    let app = try await makeSelectedApp()

    let report = try app.say("skip it", at: address("w1d1.e0.s0"))

    #expect(report.outcome == .skipped)
    #expect(report.set.state == "skipped")
    #expect(try app.sync.fetchPendingWriteRecords().map(\.valueToWrite) == ["skip"])
    _ = try await app.flush()
    #expect(try await app.sheet(tab: nil).cells["K15"] == "skip")
}

@MainActor
@Test func aRejectedSpokenSetReportsWhyAndQueuesNothing() async throws {
    let app = try await makeSelectedApp()

    let offLadder = try app.say("185 for 5 RPE 4", at: address("w1d1.e0.s0"))
    let nothingToRepeat = try app.say("same again", at: address("w1d1.e0.s0"))
    let conflicting = try app.say("135 for 4, 8 reps", at: address("w1d1.e0.s0"))
    let fused = try app.say("40542 at nine.", at: address("w1d1.e0.s0"))
    let ambiguous = try app.say("135 for 49", at: address("w1d1.e0.s0"))
    let implausible = try app.say("12.47 for 3", at: address("w1d1.e0.s0"))

    #expect(offLadder.outcome == .rejected)
    #expect(offLadder.rejection == SpokenSetRejectionSnapshot(reason: .offLadderRPE, field: nil, value: 4))
    #expect(nothingToRepeat.rejection?.reason == .nothingToRepeat)
    #expect(conflicting.rejection == SpokenSetRejectionSnapshot(reason: .conflicting, field: "reps", value: nil))
    #expect(fused.rejection == SpokenSetRejectionSnapshot(reason: .fusedNumber, field: nil, value: nil))
    #expect(ambiguous.rejection == SpokenSetRejectionSnapshot(reason: .ambiguous, field: nil, value: nil))
    #expect(implausible.rejection == SpokenSetRejectionSnapshot(reason: .implausible, field: "weight", value: nil))
    #expect(conflicting.set.state == "pending")
    #expect(try app.sync.fetchPendingWriteRecords().isEmpty)
}

/// The second Set once the first is logged, so its card pre-fills a weight, reps, and an RPE, and any
/// value the grammar wrongly hears completes a Set Log that would be queued for the Sheet.
@MainActor
private func appWhoseSecondSetCardHoldsEveryValue() async throws -> WorkoutApplication {
    let app = try await makeSelectedApp()
    _ = try app.log(address("w1d1.e0.s0"), setLog: "185x5@8")
    return app
}

@MainActor
@Test func oneValueSaidOnACardThatHoldsEveryValueQueuesItsWrite() async throws {
    let app = try await appWhoseSecondSetCardHoldsEveryValue()

    let report = try app.say("for 5", at: address("w1d1.e0.s1"))

    #expect(report.outcome == .logged)
    #expect(try app.sync.fetchPendingWriteRecords().count == 2)
}

/// "185 for 5 and 5" once logged RPE 5 over the card's RPE, so a number after "and" or a misheard
/// "to" leaves the RPE to the athlete.
@MainActor
@Test(
    "A weight for reps and a number on a card that holds every value is missing the RPE and queues nothing",
    arguments: ["185 for 5 and 5", "Body weight for 12 to 7"]
)
func aWeightForRepsAndANumberOnACardThatHoldsEveryValueIsMissingTheRPEAndQueuesNothing(transcript: String) async throws {
    let app = try await appWhoseSecondSetCardHoldsEveryValue()

    let report = try app.say(transcript, at: address("w1d1.e0.s1"))

    #expect(report.outcome == .missingValues)
    #expect(report.missing == ["rpe"])
    #expect(report.set.state == "pending")
    #expect(try app.sync.fetchPendingWriteRecords().count == 1)
}

/// Each of these once wrote a Set Log nobody said, or is a transcriber's misreading of one.
@MainActor
@Test(
    "A transcript the grammar rejects queues no write, even on a card that holds every value",
    arguments: [
        "5 at 8", "for 5, 8", "5 reps, 8", "eight reps nine", "four at eight", "1 85", "1,85", "one 85", "1 8 5",
        "185, 45, at 8", "405 42", "eight", "8", "ten", "nine point five", "185, 5, 8", "185 and 5", "for 5 and 8",
        "8 reps of 135", "nine five for five", "at nine five for five", "five or six reps at eight",
        "twenty five or thirty reps at eight", "1854.5 for 5",
        "135 for 16", "Two.", "245 for three 8 1/2", "185+58", "315 for 19.5", "185 for 5 at 80%",
        "185 for 5 and 8 reps", "185 for 5 at 8 reps", "185 for 5, 185 for 5", "same weight", "8½", "95 pounds to 67"
    ]
)
func aRejectedTranscriptQueuesNoWrite(transcript: String) async throws {
    let app = try await appWhoseSecondSetCardHoldsEveryValue()

    let report = try app.say(transcript, at: address("w1d1.e0.s1"))

    #expect(report.outcome == .rejected)
    #expect(report.set.state == "pending")
    #expect(try app.sync.fetchPendingWriteRecords().count == 1)
}

/// Each of these once wrote a Set Log the lifter did not say: a value no Set Log holds, "or" between two
/// numbers, a command naming which Set, a value said twice, a dropped minus sign.
@MainActor
@Test(
    "A transcript no Set Log holds or that says a value twice queues no write on a card that holds every value",
    arguments: [
        "135 for 0", "135 for 8.5", "0 for 5", "30 or 25 reps", "25 or 20 reps", "50 or 40 reps", "twenty five or twenty reps",
        "thirty or twenty five reps at 8",
        "60 or 50 reps", "40 or 30", "25 per 30", "20 per 25", "forty four five", "ninety four five", "skip set one",
        "skip one set", "same as set one", "same as last time", "repeat set one", "one again", "same one", "135 for -5",
        "135 for 5 at -8", "185 for 5 and 3 at 8", "185 for 5 and 5 at 8", "185 for 5 and 8 at 9", "185 for 5 and 5 RPE 8",
        "185 for 5 for 5 for 5", "185 for 5 reps, 5 reps, 5 reps", "135 for 3 and 135 at 9", "135 for 5 at 8 at",
        "135 for 5 at 8 for", "135 for 5 at 8 x", "135 for 5 at 8 of", "135 for 5 at 8 add", "135 for 5 for"
    ]
)
func aTranscriptNoSetLogHoldsQueuesNoWrite(transcript: String) async throws {
    let app = try await appWhoseSecondSetCardHoldsEveryValue()

    let report = try app.say(transcript, at: address("w1d1.e0.s1"))

    #expect(report.outcome == .rejected)
    #expect(report.set.state == "pending")
    #expect(try app.sync.fetchPendingWriteRecords().count == 1)
}

/// Speaking logs what typing on the card logs, however light the weight, fine its fraction, or many its reps.
@MainActor
@Test(
    "A Spoken Set of any weight and rep count a lifter logs queues its write",
    arguments: [
        ("5 by 5", "5x5@7"), ("4 for 5", "4x5@7"), ("10 for 12 at 9", "10x12@9"), ("135 for 45", "135x45@7"),
        ("187.25 for 5", "187.25x5@7"), ("8 reps at 12", "12x8@7"), ("5 reps with 12", "12x5@7"), ("19 per 5", "19x5@7")
    ]
)
func aSpokenSetOfAnyValueALifterLogsQueuesItsWrite(transcript: String, setLog: String) async throws {
    let app = try await appWhoseSecondSetCardHoldsEveryValue()

    let report = try app.say(transcript, at: address("w1d1.e0.s1"))

    #expect(report.outcome == .logged)
    #expect(report.setLog == setLog)
    #expect(try app.sync.fetchPendingWriteRecords().count == 2)
}

/// Each of these once logged the card's or the cut-off RPE as if the lifter had finished saying it.
@MainActor
@Test(
    "A transcript cut off after its RPE is missing the RPE and queues no write on a card that holds every value",
    arguments: [
        "135 for 5 at eight and a", "135 for 5 at 8 and", "135 for 5 at 8 and a", "135 for 5 at 8 and uh",
        "135 for 5 rpe 8 and", "135 for 5 reps at 8 and a", "rpe 8 and a", "rpe 8 and", "at 8 and", "135 for 5 at nine and",
        "135 for 5 at nine and a", "135 for 5 at 9 and a", "135 for 5 at 6 and a", "135 for 5 at 7 and a",
        "135 for 3 at 9 and", "8 reps at 9 and", "8 reps rpe 9 and", "135 for 5 at 8 and then", "135 for 5 at 8 and then uh",
        "135 for 5 at 8 so and"
    ]
)
func aTranscriptCutOffAfterItsRPEQueuesNoWrite(transcript: String) async throws {
    let app = try await appWhoseSecondSetCardHoldsEveryValue()

    let report = try app.say(transcript, at: address("w1d1.e0.s1"))

    #expect(report.outcome == .missingValues)
    #expect(report.missing == ["rpe"])
    #expect(report.set.state == "pending")
    #expect(try app.sync.fetchPendingWriteRecords().count == 1)
}

@MainActor
@Test func sayingToAnUnknownSetThrowsTheSameLookupErrorAsLog() async throws {
    let app = try await makeSelectedApp()

    #expect(throws: ApplicationError.notFound(.set, name: "w1d1.e0.s9", candidates: ["w1d1.e0.s0", "w1d1.e0.s1", "w1d1.e0.s2"])) {
        try app.say("185 for 5 at 8", at: address("w1d1.e0.s9"))
    }
}

@MainActor
@Test func dictatingWritesOnlyWhatTheMostLikelyTranscriptReads() async throws {
    let app = try await makeSelectedApp()

    let report = try app.dictate(["RPE 9", "185 for 5 at 8"], at: address("w1d1.e0.s0"))

    #expect(report.heard == "RPE 9")
    #expect(report.outcome == .missingValues)
    #expect(report.missing == ["weight"])
    #expect(report.set.state == "pending")
    #expect(try app.sync.fetchPendingWriteRecords().isEmpty)
}

@MainActor
@Test func dictatingASetOnlyTheLessLikelyTranscriptsReadIsAmbiguousAndWritesNothing() async throws {
    let app = try await makeSelectedApp()

    let report = try app.dictate(["um", "185 for 5 at 8", "185 for 5 at 8"], at: address("w1d1.e0.s0"))

    #expect(report.heard == "um")
    #expect(report.outcome == .rejected)
    #expect(report.rejection == SpokenSetRejectionSnapshot(reason: .ambiguous, field: nil, value: nil))
    #expect(report.set.state == "pending")
    #expect(try app.sync.fetchPendingWriteRecords().isEmpty)
}

@MainActor
@Test func dictatingWithNoTranscriptHeardNothing() async throws {
    let app = try await makeSelectedApp()

    let report = try app.dictate([], at: address("w1d1.e0.s0"))

    #expect(report.heard == "")
    #expect(report.outcome == .rejected)
    #expect(report.rejection?.reason == .nothingHeard)
    #expect(try app.sync.fetchPendingWriteRecords().isEmpty)
}

@available(iOS 26, macOS 26, *)
@MainActor
@Test func hearingRefusesAnUnknownSetAndAFileThatIsNotAudioBeforeItListens() async throws {
    let app = try await makeSelectedApp()
    let notAudio = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).aiff")
    try Data("185 for 5 at 8".utf8).write(to: notAudio)
    defer { try? FileManager.default.removeItem(at: notAudio) }

    await #expect(throws: ApplicationError.notFound(.set, name: "w1d1.e0.s9", candidates: ["w1d1.e0.s0", "w1d1.e0.s1", "w1d1.e0.s2"])) {
        try await app.hear(notAudio, at: address("w1d1.e0.s9")) { _ in }
    }
    await #expect(throws: ApplicationError.unreadableRecording(notAudio.path)) {
        try await app.hear(notAudio, at: address("w1d1.e0.s0")) { _ in }
    }
    #expect(try app.sync.fetchPendingWriteRecords().isEmpty)
}

@MainActor
@Test func aHeardSetReportsEveryTranscriptBesideWhatTheMostLikelyOneDid() async throws {
    let app = try await makeSelectedApp()
    let candidates = ["135 for 5 at 8.", "135 four 5 at 8."]
    let report = HearReport(candidates: candidates, report: try app.dictate(candidates, at: address("w1d1.e0.s0")))

    let json = try #require(try JSONSerialization.jsonObject(with: JSONEncoder().encode(report)) as? [String: Any])

    #expect(json["candidates"] as? [String] == candidates)
    #expect(json["heard"] as? String == "135 for 5 at 8.")
    #expect(json["outcome"] as? String == "logged")
    #expect(json["setLog"] as? String == "135x5@8")
    #expect(json["captions"] == nil)
}

@MainActor
@Test func aPacedHearReportsEachCaptionWithWhenItArrived() async throws {
    let app = try await makeSelectedApp()
    let candidates = ["135 for 5 at 8."]
    let captions = [HearReport.Caption(atMs: 900, heard: "135"), HearReport.Caption(atMs: 1200, heard: "135 for 5 at 8.")]
    let report = HearReport(
        candidates: candidates,
        captions: captions,
        report: try app.dictate(candidates, at: address("w1d1.e0.s0"))
    )

    let json = try #require(try JSONSerialization.jsonObject(with: JSONEncoder().encode(report)) as? [String: Any])

    let encoded = try #require(json["captions"] as? [[String: Any]])
    #expect(encoded.map { $0["atMs"] as? Int } == [900, 1200])
    #expect(encoded.map { $0["heard"] as? String } == ["135", "135 for 5 at 8."])
    #expect(json["setLog"] as? String == "135x5@8")
}

@MainActor
@Test func dictatingAWholeSetFromTheMostLikelyTranscriptLogsIt() async throws {
    let app = try await makeSelectedApp()

    let report = try app.dictate(["185 for 5 at 8", "185 for 5 at 9"], at: address("w1d1.e0.s0"))

    #expect(report.outcome == .logged)
    #expect(report.setLog == "185x5@8")
    #expect(report.set.state == "logged")
    #expect(report.pendingWriteCount == 1)
}
