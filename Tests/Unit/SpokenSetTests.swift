import Foundation
import Testing

@testable import WorkoutTracker

typealias HeardSpokenSet = Result<SpokenSet, SpokenSet.Rejection>

func spoken<Value>(_ value: Value?) -> SpokenValue<Value> {
    value.map(SpokenValue.heard) ?? .notSaid
}

func values(_ weight: Weight?, _ reps: Int?, _ rpe: RPE?) -> HeardSpokenSet {
    .success(.values(weight: spoken(weight), reps: spoken(reps), rpe: spoken(rpe)))
}

func rpeCutOff(_ weight: Weight, _ reps: Int, _ remnant: SpokenRemnant = .nothing) -> HeardSpokenSet {
    .success(.values(weight: .heard(weight), reps: .heard(reps), rpe: .cutOff(remnant)))
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
        ("one ten", 110), ("twenty", 20), ("187.5", 187.5), ("one eighty seven point five", 187.5),
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

@Test(
    "Every number word reads as its number",
    arguments: [
        ("one", 1), ("two", 2), ("three", 3), ("four", 4), ("five", 5), ("six", 6), ("seven", 7), ("eight", 8), ("nine", 9),
        ("ten", 10), ("eleven", 11), ("twelve", 12), ("thirteen", 13), ("fourteen", 14), ("fifteen", 15), ("sixteen", 16),
        ("seventeen", 17), ("eighteen", 18), ("nineteen", 19), ("twenty", 20), ("thirty", 30), ("forty", 40), ("fifty", 50),
        ("sixty", 60), ("seventy", 70), ("eighty", 80), ("ninety", 90)
    ]
)
func everyNumberWordReadsAsItsNumber(word: String, number: Int) {
    #expect(SpokenSet.parse("one hundred \(word) pounds") == values(.pounds(Double(100 + number)), nil, nil))
}

@Test func oneThirtyFiveForEightAtNineReadsEveryNumberAsWords() {
    #expect(SpokenSet.parse("one thirty five for eight at nine") == values(.pounds(135), 8, .nine))
}

@Test func fourBetweenTwoNumbersIsTheForOfWeightForReps() {
    #expect(SpokenSet.parse("135 four 5 at 8") == values(.pounds(135), 5, .eight))
    #expect(SpokenSet.parse("one thirty five four ten at 8") == values(.pounds(135), 10, .eight))
    #expect(SpokenSet.parse("135 pounds four 5") == values(.pounds(135), 5, nil))
    #expect(SpokenSet.parse("bodyweight four 12") == values(.bodyweight, 12, nil))
}

/// "ninety four five" may be 94 and a 5 or 90 for 5, so "four" after a tens word is always its unit.
@Test func fourAfterATensWordIsItsUnit() {
    #expect(SpokenSet.parse("ninety four five at eight") == .failure(.ambiguous))
    #expect(SpokenSet.parse("forty four five") == .failure(.ambiguous))
    #expect(SpokenSet.parse("ninety four five") == .failure(.ambiguous))
    #expect(SpokenSet.parse("ninety four reps") == values(nil, 94, nil))
    #expect(SpokenSet.parse("ninety four pounds for five") == values(.pounds(94), 5, nil))
}

@Test func fourWhereANumberIsAskedForIsTheNumberFour() {
    #expect(SpokenSet.parse("four oh five for four at 9") == values(.pounds(405), 4, .nine))
    #expect(SpokenSet.parse("twenty four reps") == values(nil, 24, nil))
    #expect(SpokenSet.parse("135 pounds four reps") == values(.pounds(135), 4, nil))
    #expect(SpokenSet.parse("at four") == values(.pounds(4), nil, nil))
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

/// Verbatim from the matrix: what the recognizer writes for Karen's "eight".
@Test func ageAndGateAreEight() {
    #expect(SpokenSet.parse("10 for 12 at age.") == values(.pounds(10), 12, .eight))
    #expect(SpokenSet.parse("£135 for age.") == values(.pounds(135), 8, nil))
    #expect(SpokenSet.parse("135 gate reps, RPE 9.") == values(.pounds(135), 8, .nine))
    #expect(SpokenSet.parse("135 for 4, gate rebs, RPE 9.") == .failure(.conflicting(.reps)))
}

/// Verbatim from the matrix: "felt like" is how a lifter says the RPE.
@Test func feltLikeLabelsTheRPE() {
    #expect(SpokenSet.parse("185 for 6, felt like an 8.") == values(.pounds(185), 6, .eight))
    #expect(SpokenSet.parse("185 for 6 felt like an age.") == values(.pounds(185), 6, .eight))
    #expect(SpokenSet.parse("185 for 6 felt like 135") == .failure(.offLadderRPE(135)))
}

@Test(
    "Bodyweight in any spelling is the BW weight",
    arguments: [
        "bodyweight for 12 at 7", "body weight for 12 at 7", "BW for 12 at 7", "B.W. for 12 at 7", "BWx12@7",
        "Body weights for 12 at 7", "Body waits for 12 at 7", "Body wait for 12 at 7", "Bobby waits for 12 at 7",
        "Bobby, wait for 12 at 7"
    ]
)
func bodyweightInAnySpellingIsBW(transcript: String) {
    #expect(SpokenSet.parse(transcript) == values(.bodyweight, 12, .seven))
}

/// Verbatim from the matrix of voices: what the recognizer writes for "reps" and "RPE" said fast.
@Test(
    "The words the recognizer writes for reps and RPE label the number as those do",
    arguments: [
        "5 ribs with 185 pounds, RPE 9", "185 for 5 rips at 9", "185 for 5 representatives at 9", "185, 5 representatives, RPE 9",
        "185 for 5 RPA 9", "185 for 5 reps, 9 PE", "185 for 5 reps, 9 are fee", "185 for five, our fee 9", "185 for 5 at our fee 9",
        "185 for 5 at 9 are fee", "185 for 5 R fee 9", "185 for 5 reps at our pe 9", "185, 5 rebs, RPE9."
    ]
)
func theWordsTheRecognizerWritesForRepsAndRPELabelTheNumber(transcript: String) {
    #expect(SpokenSet.parse(transcript) == values(.pounds(185), 5, .nine))
}
