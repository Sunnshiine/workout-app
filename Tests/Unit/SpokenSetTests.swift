import Foundation
import Testing

@testable import WorkoutTracker

private typealias Heard = Result<SpokenSet, SpokenSet.Rejection>

private func values(_ weight: Weight?, _ reps: Int?, _ rpe: RPE?) -> Heard {
    .success(.values(SetLogDraft(weight: weight, reps: reps, rpe: rpe)))
}

@Test(
    "Every way of saying one Set hears its weight, reps, and RPE",
    arguments: [
        "185 for 5 at 8", "185x5@8", "185 x 5 @ 8", "185 X 5 @ 8", "185 × 5 @ 8", "185 by 5 at RPE 8",
        "185 times 5 RPE 8", "185, 5, 8", "185 pounds for 5 reps at RPE 8", "185 for 5 at 8.", "One eighty five for five at eight"
    ]
)
func everyWayOfSayingOneSetHearsItsValues(transcript: String) {
    #expect(SpokenSet.parse(transcript) == values(.pounds(185), 5, .eight))
}

@Test(
    "A keyword labels the number next to it wherever it sits",
    arguments: [
        "135 for 8 reps RPE 9", "8 reps 135 pounds RPE 9", "RPE 9 135 for 8", "135 lbs 8 reps at 9", "135 lb for 8 rp 9",
        "135 for 8 r p e 9", "135 for 8 R.P.E. 9", "135 for 8 rpe9", "135 for 8 @9", "8 reps at 135, 9"
    ]
)
func aKeywordLabelsTheNumberNextToItWhereverItSits(transcript: String) {
    #expect(SpokenSet.parse(transcript) == values(.pounds(135), 8, .nine))
}

@Test(
    "Spoken numbers read as the number the athlete means",
    arguments: [
        ("one thirty five", 135.0), ("one hundred thirty five", 135), ("a hundred and eighty-five", 185),
        ("two twenty five", 225), ("three fifteen", 315), ("one oh five", 105), ("four oh five", 405),
        ("ninety five", 95), ("forty five", 45), ("two hundred", 200), ("one ten", 110), ("twelve", 12),
        ("187.5", 187.5), ("one eighty seven point five", 187.5), ("one eighty seven and a half", 187.5),
        ("a hundred and a half", 100.5)
    ]
)
func spokenNumbersReadAsTheNumberMeant(words: String, pounds: Double) {
    #expect(SpokenSet.parse(words) == values(.pounds(pounds), nil, nil))
}

@Test(
    "A half or a decimal RPE reads as its half-point",
    arguments: ["RPE eight and a half", "RPE 8.5", "at eight point five", "@ 8 and a half", "rpe 8 point 5"]
)
func aHalfOrDecimalRPEReadsAsItsHalfPoint(transcript: String) {
    #expect(SpokenSet.parse(transcript) == values(nil, nil, .eightPointFive))
}

@Test func oneThirtyFiveForEightAtNineReadsEveryNumberAsWords() {
    #expect(SpokenSet.parse("one thirty five for eight at nine") == values(.pounds(135), 8, .nine))
}

@Test func fourBetweenTwoNumbersIsTheForOfWeightForReps() {
    #expect(SpokenSet.parse("135 four 5 at 8") == values(.pounds(135), 5, .eight))
    #expect(SpokenSet.parse("one thirty five four ten at 8") == values(.pounds(135), 10, .eight))
    #expect(SpokenSet.parse("ninety four five at eight") == values(.pounds(90), 5, .eight))
    #expect(SpokenSet.parse("135 pounds four 5") == values(.pounds(135), 5, nil))
    #expect(SpokenSet.parse("bodyweight four 12") == values(.bodyweight, 12, nil))
}

@Test func fourWhereANumberIsAskedForIsTheNumberFour() {
    #expect(SpokenSet.parse("four oh five for four at 9") == values(.pounds(405), 4, .nine))
    #expect(SpokenSet.parse("twenty four reps") == values(nil, 24, nil))
    #expect(SpokenSet.parse("135 four reps") == values(.pounds(135), 4, nil))
    #expect(SpokenSet.parse("at four") == .failure(.offLadderRPE(4)))
}

@Test func ateIsEightAndToIsTwoOnlyWhereANumberIsAskedFor() {
    #expect(SpokenSet.parse("185 for 5 at ate") == values(.pounds(185), 5, .eight))
    #expect(SpokenSet.parse("315 for to at 9") == values(.pounds(315), 2, .nine))
    #expect(SpokenSet.parse("315 for too at 9") == values(.pounds(315), 2, .nine))
    #expect(SpokenSet.parse("to reps") == values(nil, 2, nil))
    #expect(SpokenSet.parse("go to 185") == .failure(.unrecognized))
    #expect(SpokenSet.parse("185 to 5") == .failure(.unrecognized))
}

@Test(
    "Bodyweight in any spelling is the BW weight",
    arguments: ["bodyweight for 12 at 7", "body weight for 12 at 7", "BW for 12 at 7", "B.W. for 12 at 7", "BWx12@7"]
)
func bodyweightInAnySpellingIsBW(transcript: String) {
    #expect(SpokenSet.parse(transcript) == values(.bodyweight, 12, .seven))
}

@Test func aPartialSetHearsOnlyWhatWasSaid() {
    #expect(SpokenSet.parse("135 for 8") == values(.pounds(135), 8, nil))
    #expect(SpokenSet.parse("RPE 9") == values(nil, nil, .nine))
    #expect(SpokenSet.parse("at 7") == values(nil, nil, .seven))
    #expect(SpokenSet.parse("8 reps") == values(nil, 8, nil))
    #expect(SpokenSet.parse("for 8") == values(nil, 8, nil))
    #expect(SpokenSet.parse("8 reps at 135") == values(.pounds(135), 8, nil))
    #expect(SpokenSet.parse("bodyweight") == values(.bodyweight, nil, nil))
}

@Test func unlabeledNumbersFillWhatIsLeftInWeightRepsRPEOrder() {
    #expect(SpokenSet.parse("RPE 9, 135, 8") == values(.pounds(135), 8, .nine))
    #expect(SpokenSet.parse("8 reps, 135, 9") == values(.pounds(135), 8, .nine))
    #expect(SpokenSet.parse("135 for 8, 9") == values(.pounds(135), 8, .nine))
    #expect(SpokenSet.parse("185, 5") == values(.pounds(185), 5, nil))
}

@Test(
    "Same again in any phrasing repeats the last Set",
    arguments: ["same again", "Same.", "same as last", "the same as last time", "repeat", "repeat that", "again"]
)
func sameAgainInAnyPhrasing(transcript: String) {
    #expect(SpokenSet.parse(transcript) == .success(.sameAgain))
}

@Test("Skip in any phrasing skips the Set", arguments: ["skip", "Skip it.", "skip set", "skip this set", "skip this one"])
func skipInAnyPhrasing(transcript: String) {
    #expect(SpokenSet.parse(transcript) == .success(.skip))
}

@Test func aCommandMixedWithNumbersIsUnrecognized() {
    #expect(SpokenSet.parse("skip 185 for 5") == .failure(.unrecognized))
    #expect(SpokenSet.parse("same again at 9") == .failure(.unrecognized))
    #expect(SpokenSet.parse("skip again") == .failure(.unrecognized))
}

@Test func anRPEOffTheTenPointLadderIsRejectedWithTheNumberHeard() {
    #expect(SpokenSet.parse("RPE 5.5") == .failure(.offLadderRPE(5.5)))
    #expect(SpokenSet.parse("RPE 11") == .failure(.offLadderRPE(11)))
    #expect(SpokenSet.parse("185 for 5 at 4") == .failure(.offLadderRPE(4)))
    #expect(SpokenSet.parse("185x5@185") == .failure(.offLadderRPE(185)))
    #expect(SpokenSet.parse("185, 5, 7.25") == .failure(.offLadderRPE(7.25)))
}

@Test func twoDifferentNumbersForOneValueConflict() {
    #expect(SpokenSet.parse("135 for 4, 8 reps, RPE 9") == .failure(.conflicting(.reps)))
    #expect(SpokenSet.parse("135 pounds 185 for 5") == .failure(.conflicting(.weight)))
    #expect(SpokenSet.parse("RPE 8 at 9") == .failure(.conflicting(.rpe)))
    #expect(SpokenSet.parse("bodyweight 135 for 5") == .failure(.conflicting(.weight)))
    #expect(SpokenSet.parse("135 for 8, 8 reps") == values(.pounds(135), 8, nil))
}

@Test func kilogramsAreRejectedBecauseEverySetLogIsInPounds() {
    for transcript in ["100 kilos for 5", "100 kg for 5", "100kg for 5", "100 kilograms", "a hundred k g for 5", "60 KGs"] {
        #expect(SpokenSet.parse(transcript) == .failure(.kilograms), "\(transcript)")
    }
}

@Test func silenceAndFillerAreNothingHeard() {
    for transcript in ["", "   ", "um", "Uh, um.", "okay so"] {
        #expect(SpokenSet.parse(transcript) == .failure(.nothingHeard), "\(transcript)")
    }
}

@Test func valuesOutsideWhatAnySetHoldsAreOutOfRange() {
    #expect(SpokenSet.parse("135 for 0") == .failure(.outOfRange(.reps)))
    #expect(SpokenSet.parse("135 for 101") == .failure(.outOfRange(.reps)))
    #expect(SpokenSet.parse("135 for 8.5") == .failure(.outOfRange(.reps)))
    #expect(SpokenSet.parse("135 for 1e20") == .failure(.unrecognized))
    #expect(SpokenSet.parse("0 for 5") == .failure(.outOfRange(.weight)))
    #expect(SpokenSet.parse("2000.5 for 5") == .failure(.outOfRange(.weight)))
    #expect(SpokenSet.parse("999 for 1 at 10") == values(.pounds(999), 1, .ten))
    #expect(SpokenSet.parse("135 for 100") == values(.pounds(135), 100, nil))
}

@Test func anythingElseIsUnrecognized() {
    let transcripts = [
        "banana", "185 for 5 at 8 please", "the quick brown fox", "reps", "RPE", "for", "185, 5, 8, 9", "nan for 5",
        "for bodyweight", "185 and a half point five", "one thousand for 5"
    ]
    for transcript in transcripts {
        #expect(SpokenSet.parse(transcript) == .failure(.unrecognized), "\(transcript)")
    }
}

/// Verbatim from Apple's SpeechTranscriber and DictationTranscriber on spoken Sets, clean and in noise.
@Test(
    "What Apple's transcribers wrote for a spoken Set reads as the Set said",
    arguments: [
        ("135 for 4 at RPE9.", values(.pounds(135), 4, .nine)),
        ("185 for 5 and 8.", values(.pounds(185), 5, .eight)),
        ("Body weight for 12 at 7.", values(.bodyweight, 12, .seven)),
        ("135 for 8 reps, RPE9.", values(.pounds(135), 8, .nine)),
        ("Same again.", .success(.sameAgain)),
        ("Skip.", .success(.skip)),
        ("225 for 3 at 8.5 .", values(.pounds(225), 3, .eightPointFive)),
        ("225 for three at eight and a half.", values(.pounds(225), 3, .eightPointFive)),
        ("315 for one at 9.5.", values(.pounds(315), 1, .ninePointFive)),
        ("45 for 10.", values(.pounds(45), 10, nil)),
        ("£95 for 6 at RPE 7.", values(.pounds(95), 6, .seven)),
        ("95 pounds per six of RPE 7.", values(.pounds(95), 6, .seven)),
        ("135 for four of nine.", values(.pounds(135), 4, .nine)),
        ("225 or 3 at 8.5 .", values(.pounds(225), 3, .eightPointFive)),
        ("135 for four at RPE nine", values(.pounds(135), 4, .nine)),
        ("135 for four RTE nine", values(.pounds(135), 4, .nine)),
        ("225 for three at 8 1/2", values(.pounds(225), 3, .eightPointFive)),
        ("Bodyweight for 12 at seven", values(.bodyweight, 12, .seven)),
        ("1:35 for 5 at 8", values(.pounds(135), 5, .eight))
    ]
)
func whatTheTranscribersWroteReadsAsTheSetSaid(transcript: String, heard: Result<SpokenSet, SpokenSet.Rejection>) {
    #expect(SpokenSet.parse(transcript) == heard)
}

@Test(
    "A whole number of four or more digits is numbers run together, never a weight",
    arguments: ["40542 at nine.", "18545 at 8.", "13544 at RPE 9.", "31541 at 9.5.", "4510", "405-4209", "405429", "2000 for 1 at 10"]
)
func aWholeNumberOfFourOrMoreDigitsIsFused(transcript: String) {
    #expect(SpokenSet.parse(transcript) == .failure(.fusedNumber))
}

@Test func aLastTwoDigitRepCountThatCouldBeRepsAtAnRPEIsAmbiguous() {
    #expect(SpokenSet.parse("135 for 49") == .failure(.ambiguous))
    #expect(SpokenSet.parse("135 x 15") == .failure(.ambiguous))
    #expect(SpokenSet.parse("135 for 49 reps") == values(.pounds(135), 49, nil))
    #expect(SpokenSet.parse("135 for 49 at 8") == values(.pounds(135), 49, .eight))
    #expect(SpokenSet.parse("RPE 8, 135 for 49") == values(.pounds(135), 49, .eight))
    #expect(SpokenSet.parse("bodyweight for 12") == values(.bodyweight, 12, nil))
    #expect(SpokenSet.parse("49 reps") == values(nil, 49, nil))
}

@Test func andOfAndAddBeforeTheLastNumberAreAMisheardAt() {
    #expect(SpokenSet.parse("for 5 and 8") == values(nil, 5, .eight))
    #expect(SpokenSet.parse("185 for 5 add 8") == values(.pounds(185), 5, .eight))
    #expect(SpokenSet.parse("8 reps of 135") == values(.pounds(135), 8, nil))
    #expect(SpokenSet.parse("135 for 8 and RPE 9") == values(.pounds(135), 8, .nine))
    #expect(SpokenSet.parse("add 185 for 5") == .failure(.unrecognized))
    #expect(SpokenSet.parse("185 and 5") == values(.pounds(185), nil, .five))
}

@Test func rteRtdAndRtvAreAMisheardRPE() {
    #expect(SpokenSet.parse("135 for 4 RTD 9") == values(.pounds(135), 4, .nine))
    #expect(SpokenSet.parse("135 for 8 reps RTV9") == values(.pounds(135), 8, .nine))
}

@Test func perAndOrBetweenTwoNumbersAreTheForOfWeightForReps() {
    #expect(SpokenSet.parse("45 or 10") == values(.pounds(45), 10, nil))
    #expect(SpokenSet.parse("bodyweight per 12") == values(.bodyweight, 12, nil))
    #expect(SpokenSet.parse("or 5") == .failure(.unrecognized))
    #expect(SpokenSet.parse("185 for or 5") == .failure(.unrecognized))
}

@Test func aPoundSignOrAClockReadsAsTheWeightItWrote() {
    #expect(SpokenSet.parse("8 reps £135") == values(.pounds(135), 8, nil))
    #expect(SpokenSet.parse("for 5 at £8") == .failure(.unrecognized))
    #expect(SpokenSet.parse("2:25 for 3") == values(.pounds(225), 3, nil))
}

@Test func aHalfWrittenAsOneOverTwoAddsAHalfOnlyAfterANumber() {
    #expect(SpokenSet.parse("at 9 1/2") == values(nil, nil, .ninePointFive))
    #expect(SpokenSet.parse("at 1/2") == .failure(.unrecognized))
}

private func chosen(_ spokenSet: SpokenSet, from source: SpokenSet.Source) -> Result<SpokenSet.Chosen, SpokenSet.Rejection> {
    .success(SpokenSet.Chosen(spokenSet: spokenSet, source: source))
}

@Test func aTopCandidateThatReadsIsTheSpokenSetWhateverTheAlternativesSay() {
    #expect(SpokenSet.parse(candidates: ["Same again.", "Same again.", "Play again."]) == chosen(.sameAgain, from: .top))
    #expect(
        SpokenSet.parse(candidates: ["185 for 5 at 8", "185 for 5 at 9"])
            == chosen(.values(SetLogDraft(weight: .pounds(185), reps: 5, rpe: .eight)), from: .top)
    )
}

@Test func alternativesThatAgreeStandInForARejectedTopCandidate() {
    #expect(
        SpokenSet.parse(candidates: ["31541", "31541", "315 for one", "315 or one"])
            == chosen(.values(SetLogDraft(weight: .pounds(315), reps: 1, rpe: nil)), from: .alternative)
    )
}

@Test func alternativesThatDisagreeAreAmbiguous() {
    #expect(SpokenSet.parse(candidates: ["18545 at", "18545 at", "185 or 5 at", "18545, at", "185, 45, at"]) == .failure(.ambiguous))
}

@Test func withNoAlternativeThatReadsTheTopCandidatesRejectionStands() {
    #expect(SpokenSet.parse(candidates: ["40542 at nine.", "40542 of nine.", "40542 is known."]) == .failure(.fusedNumber))
    #expect(SpokenSet.parse(candidates: ["135 for 49"]) == .failure(.ambiguous))
    #expect(SpokenSet.parse(candidates: []) == .failure(.nothingHeard))
}
