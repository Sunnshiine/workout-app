import Foundation
import Testing

@testable import WorkoutTracker

private typealias Heard = Result<SpokenSet, SpokenSet.Rejection>

private func spoken<Value>(_ value: Value?) -> SpokenValue<Value> {
    value.map(SpokenValue.heard) ?? .notSaid
}

private func values(_ weight: Weight?, _ reps: Int?, _ rpe: RPE?) -> Heard {
    .success(.values(weight: spoken(weight), reps: spoken(reps), rpe: spoken(rpe)))
}

private func rpeCutOff(_ weight: Weight, _ reps: Int) -> Heard {
    .success(.values(weight: .heard(weight), reps: .heard(reps), rpe: .cutOff))
}

@Test(
    "Every way of saying one Set hears its weight, reps, and RPE",
    arguments: [
        "185 for 5 at 8", "185x5@8", "185 x 5 @ 8", "185 X 5 @ 8", "185 × 5 @ 8", "185 by 5 at RPE 8",
        "185 times 5 RPE 8", "185 pounds for 5 reps at RPE 8", "185 for 5 at 8.", "One eighty five for five at eight",
        "185 for 5, 8 RPE"
    ]
)
func everyWayOfSayingOneSetHearsItsValues(transcript: String) {
    #expect(SpokenSet.parse(transcript) == values(.pounds(185), 5, .eight))
}

@Test(
    "A keyword labels the number next to it wherever it sits",
    arguments: [
        "135 for 8 reps RPE 9", "8 reps 135 pounds RPE 9", "RPE 9 135 for 8", "135 lbs 8 reps at 9", "135 lb for 8 rp 9",
        "135 for 8 r p e 9", "135 for 8 R.P.E. 9", "135 for 8 rpe9", "135 for 8 @9", "reps 8 at 135 RPE 9", "9 RPE 135 for 8"
    ]
)
func aKeywordLabelsTheNumberNextToItWhereverItSits(transcript: String) {
    #expect(SpokenSet.parse(transcript) == values(.pounds(135), 8, .nine))
}

@Test(
    "Spoken numbers read as the number the athlete means",
    arguments: [
        ("one thirty five", 135.0), ("one hundred thirty five", 135), ("a hundred and eighty-five", 185),
        ("hundred eighty five", 185), ("two twenty five", 225), ("three fifteen", 315), ("one oh five", 105),
        ("four oh five", 405), ("ninety five", 95), ("forty five", 45), ("two hundred", 200), ("hundred", 100),
        ("one ten", 110), ("twelve", 12), ("187.5", 187.5), ("one eighty seven point five", 187.5),
        ("one eighty seven and a half", 187.5), ("a hundred and a half", 100.5)
    ]
)
func spokenNumbersReadAsTheNumberMeant(words: String, pounds: Double) {
    #expect(SpokenSet.parse("\(words) pounds") == values(.pounds(pounds), nil, nil))
}

@Test(
    "A half or a decimal RPE reads as its half-point",
    arguments: [
        "RPE eight and a half", "RPE 8.5", "at eight point five", "@ 8 and a half", "rpe 8 point 5", "at 8½", "at 8 ½",
        "RPE 8½", "at 8 and half", "at eight and half"
    ]
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
    #expect(SpokenSet.parse("135 pounds four reps") == values(.pounds(135), 4, nil))
    #expect(SpokenSet.parse("at four") == .failure(.offLadderRPE(4)))
}

@Test func ateIsEightAndToIsTwoOnlyWhereANumberIsAskedFor() {
    #expect(SpokenSet.parse("185 for 5 at ate") == values(.pounds(185), 5, .eight))
    #expect(SpokenSet.parse("315 for to at 9") == values(.pounds(315), 2, .nine))
    #expect(SpokenSet.parse("315 for too at 9") == values(.pounds(315), 2, .nine))
    #expect(SpokenSet.parse("to reps") == values(nil, 2, nil))
    #expect(SpokenSet.parse("go to 185") == .failure(.unrecognized))
    #expect(SpokenSet.parse("185 to 5") == .failure(.unrecognized))
    #expect(SpokenSet.parse("5 to 6 reps") == .failure(.unrecognized))
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
    #expect(SpokenSet.parse("reps 8") == values(nil, 8, nil))
    #expect(SpokenSet.parse("for 8") == values(nil, 8, nil))
    #expect(SpokenSet.parse("8 reps at 135") == values(.pounds(135), 8, nil))
    #expect(SpokenSet.parse("bodyweight") == values(.bodyweight, nil, nil))
}

/// Each of these once filled a free value in weight, reps, RPE order and wrote a Set nobody said.
@Test(
    "A number no word places is ambiguous, never filled into the next free value",
    arguments: [
        "185, 5", "185, 5, 8", "RPE 9, 135, 8", "8 reps, 135, 9", "135 for 8, 9", "5 at 8", "for 5, 8", "5 reps, 8",
        "eight reps nine", "four at eight", "185, 45, at 8", "405 42", "1 85", "1,85", "1 8 5", "one 85", "8", "eight",
        "ten", "nine point five", "8½", "185 and 5", "for 5 and 8", "8 reps of 135", "185, 5, 8, 9"
    ]
)
func aNumberNoWordPlacesIsAmbiguous(transcript: String) {
    #expect(SpokenSet.parse(transcript) == .failure(.ambiguous))
}

@Test(
    "Number words in a row that make no one number are ambiguous",
    arguments: ["nine five for five", "at nine five for five", "135 for eight nine", "one eighty five five for 5"]
)
func numberWordsThatMakeNoOneNumberAreAmbiguous(transcript: String) {
    #expect(SpokenSet.parse(transcript) == .failure(.ambiguous))
}

@Test(
    "Same again in any phrasing repeats the last Set",
    arguments: [
        "same again", "Same.", "same as last", "the same as last time", "repeat", "repeat that", "again", "same as before",
        "do the same"
    ]
)
func sameAgainInAnyPhrasing(transcript: String) {
    #expect(SpokenSet.parse(transcript) == .success(.sameAgain))
}

@Test(
    "Skip in any phrasing skips the Set",
    arguments: ["skip", "Skip it.", "skip set", "skip this set", "skip this one", "skipped", "I skipped it"]
)
func skipInAnyPhrasing(transcript: String) {
    #expect(SpokenSet.parse(transcript) == .success(.skip))
}

@Test func aCommandMixedWithNumbersIsUnrecognized() {
    #expect(SpokenSet.parse("skip 185 for 5") == .failure(.unrecognized))
    #expect(SpokenSet.parse("same again at 9") == .failure(.unrecognized))
    #expect(SpokenSet.parse("skip again") == .failure(.unrecognized))
    #expect(SpokenSet.parse("same weight") == .failure(.unrecognized))
}

@Test(
    "Filler around a Set is dropped",
    arguments: [
        "I hit 185 for 5 at 8 thanks", "185 for 5 at 8 please", "um so I did 185 for 5 at 8", "yeah 185 for 5 at 8 thank you",
        "okay just got 185 for 5 at an 8", "185 for 5 at an RPE of 8", "185 for 5, an RPE of 8", "yes 185 for 5 at 8 ok"
    ]
)
func fillerAroundASetIsDropped(transcript: String) {
    #expect(SpokenSet.parse(transcript) == values(.pounds(185), 5, .eight))
}

@Test func anRPEOffTheTenPointLadderIsRejectedWithTheNumberHeard() {
    #expect(SpokenSet.parse("RPE 5.5") == .failure(.offLadderRPE(5.5)))
    #expect(SpokenSet.parse("RPE 11") == .failure(.offLadderRPE(11)))
    #expect(SpokenSet.parse("185 for 5 at 4") == .failure(.offLadderRPE(4)))
    #expect(SpokenSet.parse("185x5@185") == .failure(.offLadderRPE(185)))
    #expect(SpokenSet.parse("185 for 5 at 7.25") == .failure(.offLadderRPE(7.25)))
    #expect(SpokenSet.parse("at 4.5") == .failure(.offLadderRPE(4.5)))
    #expect(SpokenSet.parse("185 for 5 at 11") == .failure(.offLadderRPE(11)))
}

@Test func atNamesTheWeightFrom15AndTheRPEBelowIt() {
    #expect(SpokenSet.parse("12 reps at 30") == values(.pounds(30), 12, nil))
    #expect(SpokenSet.parse("at 15") == values(.pounds(15), nil, nil))
    #expect(SpokenSet.parse("at 14") == .failure(.offLadderRPE(14)))
    #expect(SpokenSet.parse("at 12") == .failure(.offLadderRPE(12)))
    #expect(SpokenSet.parse("at 10") == values(nil, nil, .ten))
    #expect(SpokenSet.parse("12 reps at bodyweight") == values(.bodyweight, 12, nil))
}

@Test func twoDifferentNumbersForOneValueConflict() {
    #expect(SpokenSet.parse("135 for 4, 8 reps, RPE 9") == .failure(.conflicting(.reps)))
    #expect(SpokenSet.parse("135 pounds 185 for 5") == .failure(.conflicting(.weight)))
    #expect(SpokenSet.parse("RPE 8 at 9") == .failure(.conflicting(.rpe)))
    #expect(SpokenSet.parse("bodyweight 135 for 5") == .failure(.conflicting(.weight)))
    #expect(SpokenSet.parse("135 for 8, 8 reps") == values(.pounds(135), 8, nil))
    #expect(SpokenSet.parse("135 for eight, 8 reps") == values(.pounds(135), 8, nil))
}

/// A Set has one weight, so a second weight, even the same one, starts a second Set.
@Test(
    "Two Sets said in one breath conflict on the weight",
    arguments: [
        "185 for 5, 185 for 5", "185 for 5 at 8 and 185 for 5 at 8", "185 for 5, 185 for 5 and 8", "8 reps at 135, 8 reps at 135",
        "bodyweight for 12, bodyweight for 12", "185 pounds for 5, 185 for 5"
    ]
)
func twoSetsSaidInOneBreathConflictOnTheWeight(transcript: String) {
    #expect(SpokenSet.parse(transcript) == .failure(.conflicting(.weight)))
}

@Test func kilogramsAreRejectedBecauseEverySetLogIsInPounds() {
    for transcript in ["100 kilos for 5", "100 kg for 5", "100kg for 5", "100 kilograms", "a hundred k g for 5", "60 KGs"] {
        #expect(SpokenSet.parse(transcript) == .failure(.kilograms), "\(transcript)")
    }
}

@Test func silenceAndFillerAreNothingHeard() {
    for transcript in ["", "   ", "um", "Uh, um.", "okay so", "yeah", "thank you", "okay thanks", "please"] {
        #expect(SpokenSet.parse(transcript) == .failure(.nothingHeard), "\(transcript)")
    }
}

@Test func valuesOutsideWhatAnySetHoldsAreOutOfRange() {
    #expect(SpokenSet.parse("135 for 0") == .failure(.outOfRange(.reps)))
    #expect(SpokenSet.parse("135 for 101") == .failure(.outOfRange(.reps)))
    #expect(SpokenSet.parse("135 for 8.5") == .failure(.outOfRange(.reps)))
    #expect(SpokenSet.parse("135 for 1e20") == .failure(.unrecognized))
    #expect(SpokenSet.parse("0 for 5") == .failure(.outOfRange(.weight)))
    #expect(SpokenSet.parse("4 for 5") == .failure(.outOfRange(.weight)))
    #expect(SpokenSet.parse("4.5 pounds") == .failure(.outOfRange(.weight)))
    #expect(SpokenSet.parse("5 for 5") == values(.pounds(5), 5, nil))
    #expect(SpokenSet.parse("999 for 1 at 10") == values(.pounds(999), 1, .ten))
    #expect(SpokenSet.parse("135 for 100") == values(.pounds(135), 100, nil))
}

@Test func anythingElseIsUnrecognized() {
    let transcripts = [
        "banana", "the quick brown fox", "reps", "RPE", "for", "nan for 5", "for bodyweight", "185 and a half point five",
        "one thousand for 5", "185 for 5 at 8¾", "185 for 5 at 80%", "185+58", "185 for 5 and 8 reps", "185 for 5 at 8 reps"
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
        ("185 for 5 and 8.", rpeCutOff(.pounds(185), 5)),
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
        ("95 pounds for six and RPE seven", values(.pounds(95), 6, .seven)),
        ("135 for four of nine.", rpeCutOff(.pounds(135), 4)),
        ("225 or 3 at 8.5 .", values(.pounds(225), 3, .eightPointFive)),
        ("135 for four at RPE nine", values(.pounds(135), 4, .nine)),
        ("135 for four RTE nine", values(.pounds(135), 4, .nine)),
        ("225 for three at 8 1/2", values(.pounds(225), 3, .eightPointFive)),
        ("Bodyweight for 12 at seven", values(.bodyweight, 12, .seven)),
        ("45 or 10.", values(.pounds(45), 10, nil)),
        ("135 or 4 at 9.", values(.pounds(135), 4, .nine)),
        ("1:35 for 5 at 8", values(.pounds(135), 5, .eight))
    ]
)
func whatTheTranscribersWroteReadsAsTheSetSaid(transcript: String, heard: Result<SpokenSet, SpokenSet.Rejection>) {
    #expect(SpokenSet.parse(transcript) == heard)
}

/// Verbatim from the same recordings, where the transcriber misheard the Set. One misread is not here:
/// "235 for three at eight and a half." for "two twenty-five" reads as a whole Set with one digit
/// wrong, which no grammar can tell from a Set said that way.
@Test(
    "What Apple's transcribers misheard for a spoken Set is rejected, never logged",
    arguments: [
        ("135 before an RPM.", SpokenSet.Rejection.unrecognized), ("135 for Florida RP", .unrecognized),
        ("185+58", .unrecognized), ("Body weight for sale at seven.", .unrecognized), ("Body weight for 12 to 7", .unrecognized),
        ("Body weight for sale seven", .unrecognized), ("135 parade reps, RPE9.", .unrecognized),
        ("135, Toyota, RTV9.", .unrecognized), ("135 parade rat RTD nine", .unrecognized), ("135 RT nine", .unrecognized),
        ("Play again", .unrecognized), ("Yes", .nothingHeard), ("Two.", .ambiguous), ("245 for three 8 1/2", .ambiguous),
        ("315 for 19.5", .outOfRange(.reps)), ("4510", .fusedNumber), ("95 pounds to 67", .unrecognized),
        ("40542 is known.", .fusedNumber), ("135 for 49", .ambiguous), ("135 for four of mine.", .unrecognized),
        ("135 for mom", .unrecognized), ("13548 representatives RPE line.", .fusedNumber),
        ("He waits for as well, match seven.", .unrecognized)
    ]
)
func whatTheTranscribersMisheardIsRejected(transcript: String, rejection: SpokenSet.Rejection) {
    #expect(SpokenSet.parse(transcript) == .failure(rejection))
}

@Test(
    "A number whose whole part has four or more digits is numbers run together, never a weight",
    arguments: [
        "40542 at nine.", "18545 at 8.", "13544 at RPE 9.", "31541 at 9.5.", "4510", "405-4209", "405429", "2000 for 1 at 10",
        "2000.5 for 5", "1854.5 for 5"
    ]
)
func aNumberWithFourOrMoreWholeDigitsIsFused(transcript: String) {
    #expect(SpokenSet.parse(transcript) == .failure(.fusedNumber))
}

/// "4 at 9" can reach the transcript as "49", but "1 at 5" is rarely said, so only a second digit of
/// 6 to 9 reads two ways.
@Test func aRepCountAfterForThatMayBeRepsAtAnRPEIsAmbiguous() {
    #expect(SpokenSet.parse("135 for 49") == .failure(.ambiguous))
    #expect(SpokenSet.parse("for 16") == .failure(.ambiguous))
    #expect(SpokenSet.parse("135 x 15") == values(.pounds(135), 15, nil))
    #expect(SpokenSet.parse("135 for 15") == values(.pounds(135), 15, nil))
    #expect(SpokenSet.parse("for 25") == values(nil, 25, nil))
    #expect(SpokenSet.parse("135 for sixteen") == values(.pounds(135), 16, nil))
    #expect(SpokenSet.parse("135 for 49 reps") == values(.pounds(135), 49, nil))
    #expect(SpokenSet.parse("135 for 49 at 8") == values(.pounds(135), 49, .eight))
    #expect(SpokenSet.parse("RPE 8, 135 for 49") == values(.pounds(135), 49, .eight))
    #expect(SpokenSet.parse("bodyweight for 12") == values(.bodyweight, 12, nil))
    #expect(SpokenSet.parse("49 reps") == values(nil, 49, nil))
}

/// The transcriber writes "and" for "at", but "185 for 5 and 5" may be five Sets of five, so the
/// number after it is never an RPE: the RPE was said and not heard.
@Test(
    "And, of, or add before a number after a weight for reps cuts the RPE off, never reads it",
    arguments: [
        ("185 for 5 and 8", Weight.pounds(185), 5), ("185 for 5 and 5", .pounds(185), 5), ("50 for 10 and 10", .pounds(50), 10),
        ("bodyweight for 10 and 10", .bodyweight, 10), ("135 for 8 and 6", .pounds(135), 8), ("185 for 5 and 3", .pounds(185), 5),
        ("185 for 5 reps and 5", .pounds(185), 5), ("185 for 5 of 5", .pounds(185), 5), ("135 for four of nine", .pounds(135), 4),
        ("185 for 5 add 8", .pounds(185), 5), ("185 pounds for 5 reps and 8.5", .pounds(185), 5), ("185 for 5 and 12", .pounds(185), 5)
    ]
)
func aNumberAfterAndOfOrAddCutsTheRPEOff(transcript: String, weight: Weight, reps: Int) {
    #expect(SpokenSet.parse(transcript) == rpeCutOff(weight, reps))
}

@Test func andOrOfBeforeAnRPEMarkerIsFillerAndAddAnywhereElseIsUnrecognized() {
    #expect(SpokenSet.parse("135 for 8 and RPE 9") == values(.pounds(135), 8, .nine))
    #expect(SpokenSet.parse("95 pounds per six of RPE 7") == values(.pounds(95), 6, .seven))
    #expect(SpokenSet.parse("add 185 for 5") == .failure(.unrecognized))
}

@Test func aMarkerSaidLastCutsOffTheValueItAskedForUnlessThatValueWasHeard() {
    #expect(SpokenSet.parse("185 for 5 at") == rpeCutOff(.pounds(185), 5))
    #expect(SpokenSet.parse("185 for 5 RTE") == rpeCutOff(.pounds(185), 5))
    #expect(SpokenSet.parse("185 for 5 of") == rpeCutOff(.pounds(185), 5))
    #expect(SpokenSet.parse("185 for 5 add um") == rpeCutOff(.pounds(185), 5))
    #expect(SpokenSet.parse("185 by") == .success(.values(weight: .heard(.pounds(185)), reps: .cutOff, rpe: .notSaid)))
    #expect(SpokenSet.parse("for 5 and") == .success(.values(weight: .notSaid, reps: .heard(5), rpe: .cutOff)))
    #expect(SpokenSet.parse("8 reps at") == .success(.values(weight: .notSaid, reps: .heard(8), rpe: .cutOff)))
    #expect(SpokenSet.parse("185 for 5 at 8 RPE") == values(.pounds(185), 5, .eight))
    #expect(SpokenSet.parse("185 pounds") == values(.pounds(185), nil, nil))
    #expect(SpokenSet.parse("at") == .failure(.unrecognized))
}

@Test func rteRtdAndRtvAreAMisheardRPE() {
    #expect(SpokenSet.parse("135 for 4 RTD 9") == values(.pounds(135), 4, .nine))
    #expect(SpokenSet.parse("135 for 8 reps RTV9") == values(.pounds(135), 8, .nine))
}

@Test func perAfterAWeightOfAtLeast20AndOrAfterOneHeavierThanTheRepsAreTheForOfWeightForReps() {
    #expect(SpokenSet.parse("45 or 10") == values(.pounds(45), 10, nil))
    #expect(SpokenSet.parse("20 or 5") == values(.pounds(20), 5, nil))
    #expect(SpokenSet.parse("bodyweight or 12") == values(.bodyweight, 12, nil))
    #expect(SpokenSet.parse("95 pounds per six") == values(.pounds(95), 6, nil))
    #expect(SpokenSet.parse("bodyweight per 12") == values(.bodyweight, 12, nil))
    #expect(SpokenSet.parse("19 per 5") == .failure(.unrecognized))
    #expect(SpokenSet.parse("or 5") == .failure(.unrecognized))
    #expect(SpokenSet.parse("185 for or 5") == .failure(.unrecognized))
}

/// A weight for reps falls from the weight to the reps, and a range such as "20 or 25" climbs.
@Test(
    "Or between two numbers where it can't be the for of a weight for reps is ambiguous",
    arguments: [
        "19 or 5", "five or six reps at eight", "20 or 25 reps", "twenty or twenty five reps", "30 or 40 reps", "20 or 20",
        "twenty five or thirty reps at eight", "45 or 50 pounds for 10", "45 pounds or 50 pounds", "for 20 or 25 at 8",
        "bodyweight for 20 or 25"
    ]
)
func orBetweenTwoNumbersItCannotSeparateIsAmbiguous(transcript: String) {
    #expect(SpokenSet.parse(transcript) == .failure(.ambiguous))
}

@Test func aPoundSignOrAClockReadsAsTheWeightItWrote() {
    #expect(SpokenSet.parse("8 reps £135") == values(.pounds(135), 8, nil))
    #expect(SpokenSet.parse("for 5 at £8") == .failure(.unrecognized))
    #expect(SpokenSet.parse("2:25 for 3") == values(.pounds(225), 3, nil))
}

@Test func aHalfWrittenAsOneOverTwoAddsAHalfOnlyAfterANumber() {
    #expect(SpokenSet.parse("at 9 1/2") == values(nil, nil, .ninePointFive))
    #expect(SpokenSet.parse("at 1/2") == .failure(.unrecognized))
    #expect(SpokenSet.parse("at ½") == .failure(.unrecognized))
    #expect(SpokenSet.parse("at 8.5 and a half") == .failure(.unrecognized))
}

private func chosen(_ spokenSet: SpokenSet, from source: SpokenSet.Source) -> Result<SpokenSet.Chosen, SpokenSet.Rejection> {
    .success(SpokenSet.Chosen(spokenSet: spokenSet, source: source))
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
    let cutOffRPE = SpokenSet.values(weight: .heard(.pounds(185)), reps: .heard(5), rpe: .cutOff)
    #expect(
        SpokenSet.parse(candidates: ["31541", "31541", "315 for one", "315 or one"])
            == chosen(.values(weight: .heard(.pounds(315)), reps: .heard(1), rpe: .notSaid), from: .alternative)
    )
    #expect(SpokenSet.parse(candidates: ["18545 at", "185 or 5 at", "185 for 5 at"]) == chosen(cutOffRPE, from: .alternative))
    #expect(
        SpokenSet.parse(candidates: ["18545 at", "18545 at", "185 or 5 at", "18545, at", "185, 45, at"])
            == chosen(cutOffRPE, from: .alternative)
    )
}

@Test func alternativesThatDisagreeAreAmbiguous() {
    #expect(SpokenSet.parse(candidates: ["18545 at 8", "185 for 5 at 8", "185 for 45 at 8"]) == .failure(.ambiguous))
}

@Test func withNoAlternativeThatReadsTheTopCandidatesRejectionStands() {
    #expect(SpokenSet.parse(candidates: ["40542 at nine.", "40542 of nine.", "40542 is known."]) == .failure(.fusedNumber))
    #expect(SpokenSet.parse(candidates: ["135 for 49"]) == .failure(.ambiguous))
    #expect(SpokenSet.parse(candidates: ["Two.", "To...", "To.", "2", "Two"]) == .failure(.ambiguous))
    #expect(SpokenSet.parse(candidates: []) == .failure(.nothingHeard))
}
