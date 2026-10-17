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
    #expect(SpokenSet.parse("2001 for 5") == .failure(.outOfRange(.weight)))
    #expect(SpokenSet.parse("2000 for 1 at 10") == values(.pounds(2000), 1, .ten))
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
