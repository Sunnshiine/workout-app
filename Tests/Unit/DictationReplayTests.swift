import Foundation
import Testing

@testable import WorkoutTracker

private let squat = SetLog(weight: .pounds(185), reps: 5, rpe: .eight)

@Test func twoOutcomesDecideAlikeWhenTheyDoTheSameToTheSetWhateverEachHeard() {
    let logged = DictationRecord.Outcome(.logged(squat, heard: "185 for 5 at 8."))

    #expect(logged.decidesAlike(DictationRecord.Outcome(.logged(squat, heard: "185 for five at 8"))))
    #expect(
        !logged.decidesAlike(DictationRecord.Outcome(.logged(SetLog(weight: .pounds(185), reps: 5, rpe: .nine), heard: "185 for 5 at 8.")))
    )
    #expect(!logged.decidesAlike(DictationRecord.Outcome(.filled(SetLogDraft(squat), heard: "185 for 5 at 8."))))
    let nothingHeard = DictationRecord.Outcome(.rejected(.spokenSet(.nothingHeard), heard: ""))
    #expect(!nothingHeard.decidesAlike(DictationRecord.Outcome(.rejected(.spokenSet(.ambiguous), heard: ""))))
}

@Test func pressesReplayInGroupsByTheSpeechModelVersionTheyWereReadWithInTheOrderEachFirstAppears() throws {
    let revised = DictationRecordFixtures.lines[4].replacingOccurrences(of: "0f63a7800b00dd0226abd051b906c246e1907482", with: "a1b2c3d")
    let records = try [DictationRecordFixtures.lines[0], revised, DictationRecordFixtures.lines[2], DictationRecordFixtures.lines[3]]
        .map(DictationRecordFixtures.record)

    let replay = DictationReplay(records, unreadableLines: 0, labels: nil)

    #expect(replay.versions.map(\.version.modelRevision) == ["0f63a7800b00dd0226abd051b906c246e1907482", "a1b2c3d"])
    #expect(replay.versions.map(\.decided) == [2, 1])
    #expect(replay.versions.map { $0.rules["gate"]?.differsFromDecided } == [1, 1])
    #expect(replay.versions.allSatisfy { $0.labelled == nil && $0.rules.values.allSatisfy { $0.scored == nil } })
    #expect(replay.cancelled == 1)
}
