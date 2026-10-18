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

private func rpeCutOff(_ weight: Weight, _ reps: Int, _ remnant: SpokenRemnant = .nothing) -> Heard {
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
        "185 for 5 at 9 are fee", "185 for 5 R fee 9", "185 for 5 reps at our pe 9"
    ]
)
func theWordsTheRecognizerWritesForRepsAndRPELabelTheNumber(transcript: String) {
    #expect(SpokenSet.parse(transcript) == values(.pounds(185), 5, .nine))
}

/// "135, a representative, RP9" says 135 reps at RPE 9 with no weight, and a Set missing a value is
/// never written, so the recognizer dropping the rep count costs the athlete a tap, not a wrong Set.
@Test func aRecognizerThatDropsTheRepCountLeavesAPartialSet() {
    #expect(SpokenSet.parse("135, a representative, RP9") == values(nil, 135, .nine))
    #expect(SpokenSet.parse("225 for 3 RPA") == rpeCutOff(.pounds(225), 3))
}

@Test func aSingleADoubleAndATripleAreOneTwoAndThreeReps() {
    #expect(SpokenSet.parse("225 for a triple at 8") == values(.pounds(225), 3, .eight))
    #expect(SpokenSet.parse("315 for a single at 9") == values(.pounds(315), 1, .nine))
    #expect(SpokenSet.parse("225 for a double RPE 8") == values(.pounds(225), 2, .eight))
    #expect(SpokenSet.parse("225 for a triple 8") == .failure(.ambiguous))
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

/// The recognizer writes the "for" of "135 for 8 reps, RPE 9" as a comma more often than not. With the
/// reps and the RPE both labelled after it, the weight is the only value left for a number that leads.
@Test(
    "A leading number is the weight when words label the reps and the RPE after it",
    arguments: [
        "135, 8 reps, RPE 9", "135 8 reps, RPE9.", "135, 8 reps, at 9", "135 8 reps RPE 9", "135, eight reps, RPE nine",
        "one thirty five, 8 reps, RPE 9"
    ]
)
func aLeadingNumberIsTheWeightWhenWordsLabelTheRepsAndTheRPEAfterIt(transcript: String) {
    #expect(SpokenSet.parse(transcript) == values(.pounds(135), 8, .nine))
}

/// "RPE" after a number labels that number, so "135, RPE 9, 8 reps" reads an RPE of 135 and leaves the 9.
@Test(
    "A number stays ambiguous unless it leads and both other values are labelled",
    arguments: [
        "8 reps, RPE 9, 135", "8 reps, 135, RPE 9", "135, 8 reps", "135, RPE 9", "135, 5, 8 reps, RPE 9",
        "135, 8 reps, 9", "135 pounds, 8, RPE 9", "9, 8 reps, 135 pounds", "135, 8 reps, at 12", "135, RPE 9, 8 reps"
    ]
)
func aNumberThatDoesNotLeadWithBothOtherValuesLabelledIsAmbiguous(transcript: String) {
    #expect(SpokenSet.parse(transcript) == .failure(.ambiguous))
}

@Test func aLeadingWeightNeverExcusesARepCountSaidTwice() {
    #expect(SpokenSet.parse("135, 8 reps, RPE 9, 5 reps") == .failure(.conflicting(.reps)))
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
        "same again", "Same.", "same as last", "repeat", "repeat that", "again", "same as before", "do the same",
        "repeat last set"
    ]
)
func sameAgainInAnyPhrasing(transcript: String) {
    #expect(SpokenSet.parse(transcript) == .success(.sameAgain))
}

@Test(
    "Skip in any phrasing skips the Set",
    arguments: ["skip", "Skip it.", "skip set", "skip this set", "skip this one", "skip that one", "skipped", "I skipped it"]
)
func skipInAnyPhrasing(transcript: String) {
    #expect(SpokenSet.parse(transcript) == .success(.skip))
}

/// A command acts on this Set or the one before it, so a number or a time in one may name another.
@Test(
    "A command that names which Set or Session is ambiguous",
    arguments: [
        "skip set one", "skip one set", "skip set 2", "same as set one", "repeat set one", "repeat set two", "same as last time",
        "the same as last time", "same as last week", "repeat that one time", "one again", "same one", "skip 185 for 5",
        "same again at 9"
    ]
)
func aCommandThatNamesWhichSetIsAmbiguous(transcript: String) {
    #expect(SpokenSet.parse(transcript) == .failure(.ambiguous))
}

@Test func aCommandWithAWordOutsideItsOwnIsUnrecognized() {
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
    #expect(SpokenSet.parse("185 for 5 RPE 4") == .failure(.offLadderRPE(4)))
    #expect(SpokenSet.parse("185x5@185") == .failure(.offLadderRPE(185)))
    #expect(SpokenSet.parse("185 for 5 RPE 7.25") == .failure(.offLadderRPE(7.25)))
    #expect(SpokenSet.parse("at RPE 4.5") == .failure(.offLadderRPE(4.5)))
    #expect(SpokenSet.parse("185 for 5 @ 11") == .failure(.offLadderRPE(11)))
}

@Test func atNamesTheRPEOnTheLadderAndTheWeightOffIt() {
    #expect(SpokenSet.parse("12 reps at 30") == values(.pounds(30), 12, nil))
    #expect(SpokenSet.parse("at 20") == values(.pounds(20), nil, nil))
    #expect(SpokenSet.parse("at 15") == values(.pounds(15), nil, nil))
    #expect(SpokenSet.parse("at 14") == values(.pounds(14), nil, nil))
    #expect(SpokenSet.parse("at 12") == values(.pounds(12), nil, nil))
    #expect(SpokenSet.parse("8 reps at 12") == values(.pounds(12), 8, nil))
    #expect(SpokenSet.parse("at 4.5") == values(.pounds(4.5), nil, nil))
    #expect(SpokenSet.parse("at 10") == values(nil, nil, .ten))
    #expect(SpokenSet.parse("at 9") == values(nil, nil, .nine))
    #expect(SpokenSet.parse("at 5") == values(nil, nil, .five))
    #expect(SpokenSet.parse("at 6.5") == values(nil, nil, .sixPointFive))
    #expect(SpokenSet.parse("12 reps at bodyweight") == values(.bodyweight, 12, nil))
}

/// A weight for reps holds one weight, so a number off the ladder after "at" is a second one.
@Test func aNumberOffTheLadderAfterAtAfterAWeightConflictsWithIt() {
    #expect(SpokenSet.parse("185 for 5 at 4") == .failure(.conflicting(.weight)))
    #expect(SpokenSet.parse("185 for 5 at 7.25") == .failure(.conflicting(.weight)))
    #expect(SpokenSet.parse("185 for 5 at 11") == .failure(.conflicting(.weight)))
}

@Test func atBeforeAWeightInPoundsNamesTheWeightWhateverItWeighs() {
    #expect(SpokenSet.parse("12 reps at 25 pounds") == values(.pounds(25), 12, nil))
    #expect(SpokenSet.parse("12 reps at 10 pounds") == values(.pounds(10), 12, nil))
    #expect(SpokenSet.parse("12 reps at 4 pounds") == values(.pounds(4), 12, nil))
    #expect(SpokenSet.parse("8 reps at 135 lbs") == values(.pounds(135), 8, nil))
    #expect(SpokenSet.parse("8 reps at 135 lbs at 9") == values(.pounds(135), 8, .nine))
    #expect(SpokenSet.parse("12 reps at 10") == values(nil, 12, .ten))
    #expect(SpokenSet.parse("185 for 5 at 8 pounds") == .failure(.conflicting(.weight)))
}

/// "with 8" may be "with an RPE of 8", so a number on the RPE ladder after "with" is no weight.
@Test func withBeforeBodyweightOrANumberOffTheRPELadderNamesTheWeightAndIsFillerElsewhere() {
    #expect(SpokenSet.parse("5 reps with 185") == values(.pounds(185), 5, nil))
    #expect(SpokenSet.parse("5 reps with 12") == values(.pounds(12), 5, nil))
    #expect(SpokenSet.parse("5 reps with 4.5") == values(.pounds(4.5), 5, nil))
    #expect(SpokenSet.parse("5 reps with 10 pounds") == values(.pounds(10), 5, nil))
    #expect(SpokenSet.parse("5 reps with 10") == .failure(.ambiguous))
    #expect(SpokenSet.parse("5 reps with 185 at 8") == values(.pounds(185), 5, .eight))
    #expect(SpokenSet.parse("12 reps with bodyweight") == values(.bodyweight, 12, nil))
    #expect(SpokenSet.parse("5 reps with 25 pounds") == values(.pounds(25), 5, nil))
    #expect(SpokenSet.parse("for 5 with 8") == .failure(.ambiguous))
    #expect(SpokenSet.parse("185 for 5 with an RPE of 8") == values(.pounds(185), 5, .eight))
    #expect(SpokenSet.parse("185 for 5 with") == values(.pounds(185), 5, nil))
}

@Test func poundsAfterTheWeightAfterWithLabelsIt() {
    #expect(SpokenSet.parse("5 reps with 185 pounds") == values(.pounds(185), 5, nil))
    #expect(SpokenSet.parse("with 185 pounds for 5") == values(.pounds(185), 5, nil))
    #expect(SpokenSet.parse("with 185 pounds for 5 at 8") == values(.pounds(185), 5, .eight))
    #expect(SpokenSet.parse("eight reps with one thirty five pounds") == values(.pounds(135), 8, nil))
}

@Test func twoDifferentNumbersForOneValueConflict() {
    #expect(SpokenSet.parse("135 for 4, 8 reps, RPE 9") == .failure(.conflicting(.reps)))
    #expect(SpokenSet.parse("135 pounds 185 for 5") == .failure(.conflicting(.weight)))
    #expect(SpokenSet.parse("RPE 8 at 9") == .failure(.conflicting(.rpe)))
    #expect(SpokenSet.parse("bodyweight 135 for 5") == .failure(.conflicting(.weight)))
}

/// "185 for 5 for 5 for 5" may be three Sets of five, and "185 for 5 and 3 at 8" a Set at 8 after one
/// at an RPE cut off, so a value said twice, even as the same number, is never read as one.
@Test(
    "A value said a second time conflicts, even as the same number or cut off",
    arguments: [
        ("135 for 8, 8 reps", SetLogDraft.Field.reps), ("135 for eight, 8 reps", .reps), ("185 for 5 for 5 for 5", .reps),
        ("185 for 5 reps, 5 reps, 5 reps", .reps), ("135 for 5 at 8 for", .reps), ("135 for 5 at 8 x", .reps),
        ("185 for 5 and 3 at 8", .rpe), ("185 for 5 and 5 RPE 8", .rpe), ("185 for 5 and 8 at 9", .rpe),
        ("135 for 3 and 135 at 9", .rpe), ("135 for 5 at 8 at", .rpe), ("135 for 5 at 8 of", .rpe), ("135 for 5 at 8 add", .rpe),
        ("RPE 9 RPE 9", .rpe)
    ]
)
func aValueSaidASecondTimeConflicts(transcript: String, field: SetLogDraft.Field) {
    #expect(SpokenSet.parse(transcript) == .failure(.conflicting(field)))
}

@Test func anRPEMarkerAfterTheRPEAfterAtLabelsItRatherThanAskingForASecond() {
    #expect(SpokenSet.parse("at 9 RPE") == values(nil, nil, .nine))
    #expect(SpokenSet.parse("135 for 5 at 5 rpe") == values(.pounds(135), 5, .five))
}

@Test(
    "Two Sets said in one breath conflict on the first value said again",
    arguments: [
        ("185 for 5, 185 for 5", SetLogDraft.Field.weight), ("185 for 5 at 8 and 185 for 5 at 8", .weight),
        ("185 for 5, 185 for 5 and 8", .weight), ("bodyweight for 12, bodyweight for 12", .weight),
        ("185 pounds for 5, 185 for 5", .weight), ("8 reps at 135, 8 reps at 135", .reps)
    ]
)
func twoSetsSaidInOneBreathConflict(transcript: String, field: SetLogDraft.Field) {
    #expect(SpokenSet.parse(transcript) == .failure(.conflicting(field)))
}

@Test func kilogramsAreRejectedBecauseEverySetLogIsInPounds() {
    for transcript in ["100 kilos for 5", "100 kg for 5", "100kg for 5", "100 kilograms", "a hundred k g for 5", "60 KGs"] {
        #expect(SpokenSet.parse(transcript) == .failure(.kilograms), "\(transcript)")
    }
}

@Test func silenceAndFillerAreNothingHeard() {
    for transcript in ["", "   ", "um", "Uh, um.", "okay so", "yeah", "thank you", "okay thanks", "please", "and", "of", "with", "um and"] {
        #expect(SpokenSet.parse(transcript) == .failure(.nothingHeard), "\(transcript)")
    }
}

/// A Set with no load is bodyweight and a Set not done is Skipped, so 0 pounds and 0 reps are no Set
/// Log, and a rep count is whole.
@Test func noLoadNoRepsAndAFractionOfARepAreOutOfRange() {
    #expect(SpokenSet.parse("135 for 0") == .failure(.outOfRange(.reps)))
    #expect(SpokenSet.parse("135 for zero") == .failure(.outOfRange(.reps)))
    #expect(SpokenSet.parse("135 for 8.5") == .failure(.outOfRange(.reps)))
    #expect(SpokenSet.parse("135 for 1e20") == .failure(.unrecognized))
    #expect(SpokenSet.parse("0 for 5") == .failure(.outOfRange(.weight)))
    #expect(SpokenSet.parse("0 pounds") == .failure(.outOfRange(.weight)))
    #expect(SpokenSet.parse("135 for 005") == .failure(.unrecognized))
    #expect(SpokenSet.parse("999 for 1 at 10") == values(.pounds(999), 1, .ten))
}

/// Speaking logs any weight and rep count the card's Set Log form accepts, so none of these is
/// refused for being light, fine, or many reps.
private let anyValueTheCardAccepts: [(transcript: String, weight: Weight?, reps: Int?, rpe: RPE?)] = [
    ("4 for 5", .pounds(4), 5, nil), ("10 for 12", .pounds(10), 12, nil), ("5 by 5", .pounds(5), 5, nil),
    ("5 x 5", .pounds(5), 5, nil), ("five by five", .pounds(5), 5, nil), ("8 x 8", .pounds(8), 8, nil),
    ("10 by 10", .pounds(10), 10, nil), ("5 for 5", .pounds(5), 5, nil), ("5 x 3", .pounds(5), 3, nil),
    ("6 by 8", .pounds(6), 8, nil), ("7 for 5", .pounds(7), 5, nil), ("10 for 25", .pounds(10), 25, nil),
    ("12 for 30", .pounds(12), 30, nil), ("15 for 25", .pounds(15), 25, nil), ("19.75 for 5", .pounds(19.75), 5, nil),
    ("12 times 12 at 8", .pounds(12), 12, .eight), ("5 by 5 at 8", .pounds(5), 5, .eight),
    ("10 for 12 at 8", .pounds(10), 12, .eight), ("4.5 pounds", .pounds(4.5), nil, nil),
    ("12 reps at 12 pounds", .pounds(12), 12, nil), ("10 for 45", .pounds(10), 45, nil), ("12 for 95", .pounds(12), 95, nil),
    ("twelve for ninety five", .pounds(12), 95, nil), ("8 four 95", .pounds(8), 95, nil),
    ("135 for 45", .pounds(135), 45, nil), ("135 for forty five", .pounds(135), 45, nil), ("135 for 31", .pounds(135), 31, nil),
    ("135 for 30", .pounds(135), 30, nil), ("135 for 100 reps", .pounds(135), 100, nil), ("135 for 101 at 8", .pounds(135), 101, .eight),
    ("135 for 49 reps", .pounds(135), 49, nil), ("135 for 49 at 8", .pounds(135), 49, .eight),
    ("RPE 8, 135 for 49", .pounds(135), 49, .eight), ("49 reps", nil, 49, nil), ("bodyweight for 50", .bodyweight, 50, nil),
    ("187.55 for 5", .pounds(187.55), 5, nil), ("135.123456 for 5", .pounds(135.123456), 5, nil),
    ("185.1 pounds", .pounds(185.1), nil, nil), ("187.25 for 5", .pounds(187.25), 5, nil), ("20 for 20", .pounds(20), 20, nil)
]

@Test(
    "Any weight and rep count the card accepts is heard as said",
    arguments: anyValueTheCardAccepts
)
func anyWeightAndRepCountTheCardAcceptsIsHeard(transcript: String, weight: Weight?, reps: Int?, rpe: RPE?) {
    #expect(SpokenSet.parse(transcript) == values(weight, reps, rpe))
}

/// Every weight, separator, rep count, and RPE below, crossed, reads as the Set it says.
private let setGrid: [(transcript: String, weight: Weight, reps: Int, rpe: RPE?)] = {
    let weights: [(String, Weight)] = [
        ("45", .pounds(45)), ("135", .pounds(135)), ("185.5", .pounds(185.5)), ("225", .pounds(225)), ("BW", .bodyweight)
    ]
    let rpes: [(String, RPE?)] = [(" at 8", .eight), (" RPE 9.5", .ninePointFive), ("", nil)]
    return weights.flatMap { said, weight in
        ["for", "x", "by", "times"].flatMap { separator in
            [1, 5, 12].flatMap { reps in rpes.map { ("\(said) \(separator) \(reps)\($0.0)", weight, reps, $0.1) } }
        }
    }
}()

@Test(
    "Every weight for reps in the grid reads as the Set said",
    arguments: setGrid
)
func everyWeightForRepsInTheGridReadsAsTheSetSaid(transcript: String, weight: Weight, reps: Int, rpe: RPE?) {
    #expect(SpokenSet.parse(transcript) == values(weight, reps, rpe))
}

@Test func theGridCrossesEveryWeightSeparatorRepCountAndRPE() {
    #expect(Set(setGrid.map(\.transcript)).count == 5 * 4 * 3 * 3)
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
        ("185 for 5 and 8.", rpeCutOff(.pounds(185), 5, .number(8))),
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
        ("135 for four of nine.", rpeCutOff(.pounds(135), 4, .number(9))),
        ("Body weight for 12 to 7", rpeCutOff(.bodyweight, 12, .number(7))),
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

/// Verbatim from the same recordings, where the transcriber misheard the Set. One misread is not here:
/// "235 for three at eight and a half." for "two twenty-five" reads as a whole Set with one digit
/// wrong, which no grammar can tell from a Set said that way.
@Test(
    "What Apple's transcribers misheard for a spoken Set is rejected, never logged",
    arguments: [
        ("135 before an RPM.", SpokenSet.Rejection.unrecognized), ("135 for Florida RP", .unrecognized),
        ("185+58", .unrecognized), ("Body weight for sale at seven.", .unrecognized),
        ("Body weight for sale seven", .unrecognized), ("135 parade reps, RPE9.", .unrecognized),
        ("135, Toyota, RTV9.", .unrecognized), ("135 parade rat RTD nine", .unrecognized), ("135 RT nine", .unrecognized),
        ("Play again", .unrecognized), ("Yes", .nothingHeard), ("Two.", .ambiguous), ("245 for three 8 1/2", .ambiguous),
        ("315 for 19.5", .outOfRange(.reps)), ("4510", .fusedNumber), ("95 pounds to 67", .unrecognized),
        ("40542 is known.", .fusedNumber), ("135 for 49", .ambiguous), ("135 for four of mine.", .unrecognized),
        ("135 for mom", .unrecognized), ("13548 representatives RPE line.", .fusedNumber), ("225 or 3 at 8.5 .", .ambiguous),
        ("45 or 10.", .ambiguous), ("135 or 4 at 9.", .ambiguous),
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
/// 6 to 9 reads two ways. A count of 100 or more reads two ways whatever its digits and however it was
/// said: the recognizer writes "808" for "8 at an 8", "343" for "3 for 3", and "110" for "1 at 10", and
/// nobody logs 100 reps unlabelled.
@Test func aRepCountAfterForThatMayBeRepsAtAnRPEIsAmbiguous() {
    #expect(SpokenSet.parse("135 for 49") == .failure(.ambiguous))
    #expect(SpokenSet.parse("135 for 808") == .failure(.ambiguous))
    #expect(SpokenSet.parse("225 for 343") == .failure(.ambiguous))
    #expect(SpokenSet.parse("405 for 110") == .failure(.ambiguous))
    #expect(SpokenSet.parse("135 for 100") == .failure(.ambiguous))
    #expect(SpokenSet.parse("four hundred five for one hundred") == .failure(.ambiguous))
    #expect(SpokenSet.parse("135 for one hundred") == .failure(.ambiguous))
    #expect(SpokenSet.parse("185 for one hundred and ten") == .failure(.ambiguous))
    #expect(SpokenSet.parse("135 for a hundred") == .failure(.ambiguous))
    #expect(SpokenSet.parse("135 for one hundred reps") == values(.pounds(135), 100, nil))
    #expect(SpokenSet.parse("135 for 101 at 8") == values(.pounds(135), 101, .eight))
    #expect(SpokenSet.parse("BW for 129") == .failure(.ambiguous))
    #expect(SpokenSet.parse("135 for 100 reps") == values(.pounds(135), 100, nil))
    #expect(SpokenSet.parse("135 for 808 at 8") == values(.pounds(135), 808, .eight))
    #expect(SpokenSet.parse("100 reps") == values(nil, 100, nil))
    #expect(SpokenSet.parse("for 16") == .failure(.ambiguous))
    #expect(SpokenSet.parse("135 x 15") == values(.pounds(135), 15, nil))
    #expect(SpokenSet.parse("135 for 15") == values(.pounds(135), 15, nil))
    #expect(SpokenSet.parse("for 25") == values(nil, 25, nil))
    #expect(SpokenSet.parse("135 for sixteen") == values(.pounds(135), 16, nil))
    #expect(SpokenSet.parse("135 for 19") == .failure(.ambiguous))
    #expect(SpokenSet.parse("135 for 19 reps") == values(.pounds(135), 19, nil))
    #expect(SpokenSet.parse("135 for 19 at 8") == values(.pounds(135), 19, .eight))
    #expect(SpokenSet.parse("RPE 8, 135 for 19") == values(.pounds(135), 19, .eight))
    #expect(SpokenSet.parse("bodyweight for 12") == values(.bodyweight, 12, nil))
    #expect(SpokenSet.parse("19 reps") == values(nil, 19, nil))
}

/// The transcriber writes "and" for "at", but "185 for 5 and 5" may be five Sets of five, so the
/// number after it is never an RPE: the RPE was said and not heard.
@Test(
    "And, of, or add before a number after a weight for reps cuts the RPE off, never reads it",
    arguments: [
        ("185 for 5 and 8", Weight.pounds(185), 5, 8.0), ("185 for 5 and 5", .pounds(185), 5, 5), ("50 for 10 and 10", .pounds(50), 10, 10),
        ("bodyweight for 10 and 10", .bodyweight, 10, 10), ("135 for 8 and 6", .pounds(135), 8, 6), ("185 for 5 and 3", .pounds(185), 5, 3),
        ("185 for 5 reps and 5", .pounds(185), 5, 5), ("185 for 5 of 5", .pounds(185), 5, 5), ("135 for four of nine", .pounds(135), 4, 9),
        ("185 for 5 add 8", .pounds(185), 5, 8), ("185 pounds for 5 reps and 8.5", .pounds(185), 5, 8.5),
        ("185 for 5 and 12", .pounds(185), 5, 12), ("225 for 3 to 8", .pounds(225), 3, 8), ("225 for 3 to 8.5", .pounds(225), 3, 8.5),
        ("455 for one to 10", .pounds(455), 1, 10), ("10 for 12 too 8", .pounds(10), 12, 8)
    ]
)
func aNumberAfterAndOfOrAddCutsTheRPEOff(transcript: String, weight: Weight, reps: Int, number: Double) {
    #expect(SpokenSet.parse(transcript) == rpeCutOff(weight, reps, .number(number)))
}

@Test func andOrOfBeforeAnRPEMarkerIsFillerAndAddOrToAnywhereElseIsUnrecognized() {
    #expect(SpokenSet.parse("135 for 8 and RPE 9") == values(.pounds(135), 8, .nine))
    #expect(SpokenSet.parse("95 pounds per six of RPE 7") == values(.pounds(95), 6, .seven))
    #expect(SpokenSet.parse("add 185 for 5") == .failure(.unrecognized))
    #expect(SpokenSet.parse("to 185 for 5") == .failure(.unrecognized))
    #expect(SpokenSet.parse("185 for 20 to 25 reps") == .failure(.unrecognized))
}

@Test func aMarkerSaidLastCutsOffTheValueItAskedFor() {
    #expect(SpokenSet.parse("185 for 5 at") == rpeCutOff(.pounds(185), 5))
    #expect(SpokenSet.parse("185 for 5 RTE") == rpeCutOff(.pounds(185), 5))
    #expect(SpokenSet.parse("185 for 5 of") == rpeCutOff(.pounds(185), 5))
    #expect(SpokenSet.parse("185 for 5 to") == rpeCutOff(.pounds(185), 5))
    #expect(SpokenSet.parse("185 for 5 add um") == rpeCutOff(.pounds(185), 5))
    #expect(SpokenSet.parse("185 by") == .success(.values(weight: .heard(.pounds(185)), reps: .cutOff(.nothing), rpe: .notSaid)))
    #expect(SpokenSet.parse("for 5 and") == .success(.values(weight: .notSaid, reps: .heard(5), rpe: .cutOff(.nothing))))
    #expect(SpokenSet.parse("8 reps at") == .success(.values(weight: .notSaid, reps: .heard(8), rpe: .cutOff(.nothing))))
    #expect(SpokenSet.parse("185 for 5 at 8 RPE") == values(.pounds(185), 5, .eight))
    #expect(SpokenSet.parse("185 pounds") == values(.pounds(185), nil, nil))
    #expect(SpokenSet.parse("at") == .failure(.unrecognized))
}

/// "at 8 and a" is "at 8 and a half" with the half cut off, so the 8 is not the RPE said.
@Test(
    "A half or a decimal started last cuts its number off, never reads the whole number",
    arguments: [
        ("135 for 5 at 9 and a", 9.0), ("135 for 5 at 8 and", 8), ("135 for 5 at eight and a", 8), ("135 for 5 at 8 point", 8),
        ("135 for 5 rpe 8 and", 8), ("135 for 5 reps at 8 and a", 8), ("135 for 5 at 8 and uh", 8), ("135 for 5 at 8 and then", 8),
        ("135 for 5 at 8 so and", 8), ("135 for 5 at nine point", 9)
    ]
)
func aFractionStartedLastCutsItsNumberOff(transcript: String, whole: Double) {
    #expect(SpokenSet.parse(transcript) == rpeCutOff(.pounds(135), 5, .wholePart(whole)))
}

@Test func aFractionStartedLastAfterARepCountCutsOffTheRPEBecauseRepsAreWhole() {
    #expect(SpokenSet.parse("185 for 5 and") == rpeCutOff(.pounds(185), 5))
    #expect(SpokenSet.parse("185 for 5 and a") == rpeCutOff(.pounds(185), 5))
    #expect(SpokenSet.parse("185 for 5 point") == rpeCutOff(.pounds(185), 5))
    #expect(SpokenSet.parse("5 reps and") == .success(.values(weight: .notSaid, reps: .heard(5), rpe: .cutOff(.nothing))))
    #expect(SpokenSet.parse("8 reps at 9 and") == .success(.values(weight: .notSaid, reps: .heard(8), rpe: .cutOff(.wholePart(9)))))
}

@Test func aFractionStartedLastCutsOffTheWeightOrRPEItFollows() {
    #expect(SpokenSet.parse("rpe 8 and") == .success(.values(weight: .notSaid, reps: .notSaid, rpe: .cutOff(.wholePart(8)))))
    #expect(SpokenSet.parse("at 6 and a") == .success(.values(weight: .notSaid, reps: .notSaid, rpe: .cutOff(.wholePart(6)))))
    #expect(SpokenSet.parse("5 reps with 185 and a") == .success(.values(weight: .cutOff(.wholePart(185)), reps: .heard(5), rpe: .notSaid)))
    #expect(SpokenSet.parse("135 for 5 at 8 and 9") == .failure(.ambiguous))
    #expect(SpokenSet.parse("185 and") == .failure(.ambiguous))
    #expect(SpokenSet.parse("135 for 5 at eight and half") == values(.pounds(135), 5, .eightPointFive))
}

@Test func rteRtdAndRtvAreAMisheardRPE() {
    #expect(SpokenSet.parse("135 for 4 RTD 9") == values(.pounds(135), 4, .nine))
    #expect(SpokenSet.parse("135 for 8 reps RTV9") == values(.pounds(135), 8, .nine))
}

/// A weight for reps falls from the weight to the reps, so "per" between bodyweight or a weight and
/// fewer reps is its "for". Between any other two numbers it may be a rate or a range.
@Test func perAfterBodyweightOrAWeightHeavierThanTheRepsIsTheForOfWeightForReps() {
    #expect(SpokenSet.parse("95 pounds per six") == values(.pounds(95), 6, nil))
    #expect(SpokenSet.parse("bodyweight per 12") == values(.bodyweight, 12, nil))
    #expect(SpokenSet.parse("45 per 10") == values(.pounds(45), 10, nil))
    #expect(SpokenSet.parse("21 per 20") == values(.pounds(21), 20, nil))
    #expect(SpokenSet.parse("20 per 10") == values(.pounds(20), 10, nil))
    #expect(SpokenSet.parse("19 per 5") == values(.pounds(19), 5, nil))
    #expect(SpokenSet.parse("4 per 3") == values(.pounds(4), 3, nil))
    #expect(SpokenSet.parse("12.5 per 8") == values(.pounds(12.5), 8, nil))
    #expect(SpokenSet.parse("5 per 5") == .failure(.ambiguous))
    #expect(SpokenSet.parse("25 per 30") == .failure(.ambiguous))
    #expect(SpokenSet.parse("20 per 25") == .failure(.ambiguous))
    #expect(SpokenSet.parse("20 per 20") == .failure(.ambiguous))
    #expect(SpokenSet.parse("per 5") == .failure(.unrecognized))
    #expect(SpokenSet.parse("185 per") == .failure(.unrecognized))
}

/// "or" offers a choice, as in "20 or 25 reps", and the recognizer's "or" for "for" reads the same,
/// so it is never the "for" of a weight for reps.
@Test(
    "Or anywhere is ambiguous",
    arguments: [
        "45 or 10", "20 or 5", "bodyweight or 12", "225 or 3 at 8.5", "135 or 4 at 9", "30 or 25 reps", "40 or 30", "19 or 5",
        "five or six reps at eight", "20 or 25 reps", "twenty or twenty five reps", "30 or 40 reps", "20 or 20",
        "twenty five or thirty reps at eight", "45 or 50 pounds for 10", "45 pounds or 50 pounds", "for 20 or 25 at 8",
        "bodyweight for 20 or 25", "or 5", "185 for or 5"
    ]
)
func orAnywhereIsAmbiguous(transcript: String) {
    #expect(SpokenSet.parse(transcript) == .failure(.ambiguous))
}

@Test func aPoundSignOrAClockReadsAsTheWeightItWrote() {
    #expect(SpokenSet.parse("8 reps £135") == values(.pounds(135), 8, nil))
    #expect(SpokenSet.parse("for 5 at £25") == values(.pounds(25), 5, nil))
    #expect(SpokenSet.parse("2:25 for 3") == values(.pounds(225), 3, nil))
    #expect(SpokenSet.parse("£105 for 6") == values(.pounds(105), 6, nil))
    #expect(SpokenSet.parse("10:35 for 5") == .failure(.fusedNumber))
}

@Test func aMinusSignBeforeANumberIsKeptAndUnrecognizedButADashIsDropped() {
    #expect(SpokenSet.parse("135 for -5") == .failure(.unrecognized))
    #expect(SpokenSet.parse("135 for 5 at -8") == .failure(.unrecognized))
    #expect(SpokenSet.parse("-135 for 5") == .failure(.unrecognized))
    #expect(SpokenSet.parse("135 for -05") == .failure(.unrecognized))
    #expect(SpokenSet.parse("135 for 5 − 8") == .failure(.unrecognized))
    #expect(SpokenSet.parse("135 for 5 - at 8") == values(.pounds(135), 5, .eight))
    #expect(SpokenSet.parse("two twenty-five for five") == values(.pounds(225), 5, nil))
    #expect(SpokenSet.parse("405-4209") == .failure(.fusedNumber))
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

private func chosen(_ heard: Heard) -> Result<SpokenSet.Chosen, SpokenSet.Rejection> {
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
