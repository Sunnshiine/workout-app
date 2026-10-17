import Foundation
import Testing

@testable import WorkoutTracker

private func outcome(
    of transcript: String,
    draft: SetLogDraft = SetLogDraft(weight: nil, reps: nil, rpe: nil),
    previous: SetLog? = nil
) -> Result<SpokenSetOutcome, SpokenSet.Rejection> {
    SpokenSet.parse(transcript).flatMap { $0.resolved(against: draft, previous: previous) }
}

private let squatDraft = SetLogDraft(weight: .pounds(185), reps: 5, rpe: .eight)

@Test(
    "Each value said replaces the draft's and the rest keep it",
    arguments: [
        ("185 for 5 at 8", SetLog(weight: .pounds(185), reps: 5, rpe: .eight)),
        ("at 9", SetLog(weight: .pounds(185), reps: 5, rpe: .nine)),
        ("190", SetLog(weight: .pounds(190), reps: 5, rpe: .eight)),
        ("for 3", SetLog(weight: .pounds(185), reps: 3, rpe: .eight)),
        ("4 reps at 9.5", SetLog(weight: .pounds(185), reps: 4, rpe: .ninePointFive)),
        ("bodyweight", SetLog(weight: .bodyweight, reps: 5, rpe: .eight))
    ]
)
func eachValueSaidReplacesTheDraftsAndTheRestKeepIt(transcript: String, logged: SetLog) {
    #expect(outcome(of: transcript, draft: squatDraft) == .success(.log(logged)))
}

@Test func aFreshBlocksFirstSetHasNoWeightToKeepSoAnRPEAloneIsMissingTheWeight() {
    let firstSet = SetLogDraft(weight: nil, reps: 5, rpe: .seven)

    let heard = outcome(of: "RPE 9", draft: firstSet)

    #expect(heard == .success(.missingValues(SetLogDraft(weight: nil, reps: 5, rpe: .nine))))
    guard case .success(.missingValues(let values)) = heard else { return }
    #expect(values.missingFields == [.weight])
}

@Test func aBodyweightDraftTakesTheRPESaidForIt() {
    let pullUp = SetLogDraft(weight: .bodyweight, reps: 12, rpe: nil)

    #expect(outcome(of: "at 7", draft: pullUp) == .success(.log(SetLog(weight: .bodyweight, reps: 12, rpe: .seven))))
}

@Test func weightAndRepsSaidTakeThePrescribedRPEFromTheDraft() {
    let rdl = SetLogDraft(weight: nil, reps: 10, rpe: .eight)

    #expect(outcome(of: "135 for 8", draft: rdl) == .success(.log(SetLog(weight: .pounds(135), reps: 8, rpe: .eight))))
}

@Test func valuesWithNothingInTheDraftToCompleteThemAreMissingValues() {
    #expect(outcome(of: "135 for 8") == .success(.missingValues(SetLogDraft(weight: .pounds(135), reps: 8, rpe: nil))))
}

@Test func sameAgainLogsTheEarlierSetLogWhateverTheDraftHolds() {
    let previous = SetLog(weight: .pounds(180), reps: 5, rpe: .eightPointFive)

    #expect(outcome(of: "same again", draft: squatDraft, previous: previous) == .success(.log(previous)))
}

@Test func sameAgainWithNoEarlierSetLogHasNothingToRepeat() {
    #expect(outcome(of: "same again", draft: squatDraft) == .failure(.nothingToRepeat))
}

@Test func skipSkipsTheSetWhateverTheDraftHolds() {
    #expect(outcome(of: "skip", draft: squatDraft) == .success(.skip))
}

@Test func aRejectedTranscriptStaysRejectedWhateverTheDraftHolds() {
    #expect(outcome(of: "185 for 5 at 4", draft: squatDraft) == .failure(.offLadderRPE(4)))
}
