import Foundation
import Testing

@testable import WorkoutTracker

private func chosen(_ spokenSet: SpokenSet, from source: SpokenSet.Source) -> Result<SpokenSet.Chosen, SpokenSet.Rejection> {
    .success(SpokenSet.Chosen(spokenSet: spokenSet, source: source))
}

private func chosen(_ heard: HeardSpokenSet) -> Result<SpokenSet.Chosen, SpokenSet.Rejection> {
    heard.map { SpokenSet.Chosen(spokenSet: $0, source: .top) }
}

@Test func aTopCandidateThatReadsIsTheSpokenSetWhateverTheAlternativesSay() {
    #expect(SpokenSet.parse(candidates: ["Same again.", "Same again.", "Play again."]) == chosen(.sameAgain, from: .top))
    #expect(
        SpokenSet.parse(candidates: ["185 for 5 at 8", "185 for 5 at 9"])
            == chosen(.values(weight: .heard(.pounds(185)), reps: .heard(5), rpe: .heard(.eight)), from: .top)
    )
    #expect(SpokenSet.parse(candidates: ["skipped it", "skip it"]) == chosen(.skip, from: .top))
}

@Test func alternativesThatAgreeStandInForARejectedTopCandidate() {
    let cutOffRPE = SpokenSet.values(weight: .heard(.pounds(185)), reps: .heard(5), rpe: .cutOff(.nothing))
    #expect(
        SpokenSet.parse(candidates: ["31541", "31541", "315 for one", "315 by one"])
            == chosen(.values(weight: .heard(.pounds(315)), reps: .heard(1), rpe: .notSaid), from: .alternative)
    )
    #expect(SpokenSet.parse(candidates: ["18545 at", "185 x 5 at", "185 for 5 at"]) == chosen(cutOffRPE, from: .alternative))
    #expect(
        SpokenSet.parse(candidates: ["18545 at", "18545 at", "185 x 5 at", "18545, at", "185, 45, at"])
            == chosen(cutOffRPE, from: .alternative)
    )
}

/// The recognizer writes "and" or "add" for "at" in a top transcript and "at" in an alternative.
@Test func alternativesThatHearTheSameSetSettleTheValueTheTopCandidateCutOff() {
    let settled = chosen(.values(weight: .heard(.pounds(135)), reps: .heard(8), rpe: .heard(.nine)), from: .top)
    #expect(SpokenSet.parse(candidates: ["135 for 8 and 9.", "135 for eight and 9.", "135 for 8 at 9.", "135 for 8 and nine."]) == settled)
    #expect(SpokenSet.parse(candidates: ["135 for 8 add nine.", "135 for 8 at 9.", "135 for 8 at RPE 9."]) == settled)
    #expect(
        SpokenSet.parse(candidates: ["135 for 8 at 9 and", "135 for 8 at 9 and a half"])
            == chosen(.values(weight: .heard(.pounds(135)), reps: .heard(8), rpe: .heard(.ninePointFive)), from: .top)
    )
}

/// Verbatim from the matrix of voices, where the alternatives heard a number the top cut off as said.
@Test func alternativesThatAgreeSettleAValueTheTopCutOffWithNoNumberInItsPlace() {
    #expect(
        SpokenSet.parse(candidates: ["135 for 8 at", "135 for 8 at 9"])
            == chosen(.values(weight: .heard(.pounds(135)), reps: .heard(8), rpe: .heard(.nine)), from: .top)
    )
    #expect(
        SpokenSet.parse(candidates: ["185 for", "185 for 5"])
            == chosen(.values(weight: .heard(.pounds(185)), reps: .heard(5), rpe: .notSaid), from: .top)
    )
    #expect(
        SpokenSet.parse(candidates: ["135 for 8 at", "135 for 8 at 9", "135 for 8 at 8"])
            == chosen(.values(weight: .heard(.pounds(135)), reps: .heard(8), rpe: .cutOff(.nothing)), from: .top)
    )
}

/// The parser never contradicts the top transcript: its 9 or 7 is the RPE the recognizer heard, even
/// where it misheard the "at" before it, so an alternative's 8 is another reading, not the one said.
@Test func anAlternativeSettlesANumberTheTopCutOffOnlyAsThatNumber() {
    #expect(SpokenSet.parse(candidates: ["135 for 8 and 9.", "135 for 8 at 8"]) == chosen(rpeCutOff(.pounds(135), 8, .number(9))))
    #expect(SpokenSet.parse(candidates: ["225 for 3 add 7", "225 for 3 at 8"]) == chosen(rpeCutOff(.pounds(225), 3, .number(7))))
    #expect(SpokenSet.parse(candidates: ["135 for 8 at 9 and a", "135 for 8 at 8"]) == chosen(rpeCutOff(.pounds(135), 8, .wholePart(9))))
    #expect(SpokenSet.parse(candidates: ["135 for 8 at 9 and a", "135 for 8 at 9"]) == chosen(rpeCutOff(.pounds(135), 8, .wholePart(9))))
    #expect(SpokenSet.parse(candidates: ["135 for 8 and 9.", "135 for 8 at 9.5"]) == chosen(rpeCutOff(.pounds(135), 8, .number(9))))
    #expect(
        SpokenSet.parse(candidates: ["135 for 8 and 9.", "135 for 8 at 9."])
            == chosen(.values(weight: .heard(.pounds(135)), reps: .heard(8), rpe: .heard(.nine)), from: .top)
    )
}

/// Verbatim from the matrix: Eddy (English (UK)) at 240 words a minute says "1005 for 1 at 10", the
/// top transcript has "to" for "at", and one alternative hears the "at".
@Test func anAlternativeSettlesTheRPEAWeightOfAThousandOrMoreLeftCutOff() {
    let candidates = ["1005 for one to 10.", "105 for one to 10.", "1005 for one at 10.", "1005 for one to 10", "1005 for one to 10?"]
    #expect(
        SpokenSet.parse(candidates: candidates)
            == chosen(.values(weight: .heard(.pounds(1005)), reps: .heard(1), rpe: .heard(.ten)), from: .top)
    )
    #expect(SpokenSet.parse(candidates: ["1005 for one to 10.", "1005 for one at 9."]) == chosen(rpeCutOff(.pounds(1005), 1, .number(10))))
}

/// Verbatim from the matrix: Samantha says "10 for 12 at 8" and "8 reps at 135", and the top
/// transcript loses the number said first, which a pre-filled card would otherwise fill.
@Test func alternativesThatAreTheTopWithWordsBeforeItReadTheSetItsStartCutOff() {
    #expect(
        SpokenSet.parse(candidates: ["for 12 at 8.", "10 for 12 at 8.", "for 12 at eight.", "for 12 8."])
            == chosen(values(.pounds(10), 12, .eight))
    )
    #expect(
        SpokenSet.parse(candidates: ["reps at 135.", "8 reps at 135.", "Reps at 135.", "Eight reps at 135.", "reps at 135"])
            == chosen(values(.pounds(135), 8, nil))
    )
}

@Test func alternativesThatRestoreTheStartDifferentlyAreAmbiguous() {
    #expect(SpokenSet.parse(candidates: ["for 12 at 8", "10 for 12 at 8", "20 for 12 at 8"]) == .failure(.ambiguous))
}

@Test func anAlternativeWithWordsAnywhereButBeforeTheTopRestoresNothing() {
    #expect(SpokenSet.parse(candidates: ["for 5", "for 5 at 8"]) == chosen(values(nil, 5, nil)))
    #expect(SpokenSet.parse(candidates: ["for 5", "go for 5"]) == chosen(values(nil, 5, nil)))
    #expect(
        SpokenSet.parse(candidates: ["um", "185 for 5 at 8 um"])
            == chosen(.values(weight: .heard(.pounds(185)), reps: .heard(5), rpe: .heard(.eight)), from: .alternative)
    )
}

@Test func alternativesThatHearTwoValuesForTheOneCutOffOrAnotherSetLeaveItCutOff() {
    let cutOff = chosen(.values(weight: .heard(.pounds(135)), reps: .heard(8), rpe: .cutOff(.number(9))), from: .top)
    #expect(SpokenSet.parse(candidates: ["135 for 8 and 9", "135 for 8 at 9", "135 for 8 at 8"]) == cutOff)
    #expect(SpokenSet.parse(candidates: ["135 for 8 and 9", "135 for 4 at 9"]) == cutOff)
    #expect(SpokenSet.parse(candidates: ["135 for 8 and 9", "135 for 8 at 11"]) == cutOff)
    #expect(SpokenSet.parse(candidates: ["135 for 8 and 9", "135 for 8 and nine"]) == cutOff)
    #expect(SpokenSet.parse(candidates: ["135 for 8 and 9", "135 for 8"]) == cutOff)
    #expect(SpokenSet.parse(candidates: ["135 for 8 and 9", "skip"]) == cutOff)
    #expect(SpokenSet.parse(candidates: ["135 for 8 and 9"]) == cutOff)
}

@Test func alternativesThatDisagreeAreAmbiguous() {
    #expect(SpokenSet.parse(candidates: ["18545 at 8", "185 for 5 at 8", "185 for 4 at 8"]) == .failure(.ambiguous))
    #expect(SpokenSet.parse(candidates: ["18545 at 8", "185 for 5 at 8", "185 for 45 at 8"]) == .failure(.ambiguous))
}

@Test func anAlternativeNoSetLogHoldsDisagreesWithNone() {
    #expect(
        SpokenSet.parse(candidates: ["18545 at 8", "185 for 5 at 8", "185 for 5.5 at 8"])
            == chosen(.values(weight: .heard(.pounds(185)), reps: .heard(5), rpe: .heard(.eight)), from: .alternative)
    )
}

@Test func withNoAlternativeThatReadsTheTopCandidatesRejectionStands() {
    #expect(SpokenSet.parse(candidates: ["40542 at nine.", "40542 of nine.", "40542 is known."]) == .failure(.fusedNumber))
    #expect(SpokenSet.parse(candidates: ["135 for 49"]) == .failure(.ambiguous))
    #expect(SpokenSet.parse(candidates: ["Two.", "To...", "To.", "2", "Two"]) == .failure(.ambiguous))
    #expect(SpokenSet.parse(candidates: []) == .failure(.nothingHeard))
}
