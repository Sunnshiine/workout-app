import Foundation
import Testing

@testable import WorkoutTracker

/// "135, a representative, RP9" is "135, 8 reps, RPE 9" with the rep count dropped. Read as 135 reps
/// with no weight, it would log on any card that pre-fills a weight, so the "a" keeps the 135 from the
/// label after it, and the label then labels nothing.
@Test func aRecognizerThatDropsTheRepCountIsNeverASet() {
    #expect(SpokenSet.parse("135, a representative, RP9") == .failure(.unrecognized))
    #expect(SpokenSet.parse("135 a reps") == .failure(.unrecognized))
    #expect(SpokenSet.parse("135, a triple, RPE 9") == values(.pounds(135), 3, .nine))
    #expect(SpokenSet.parse("225 for 3 RPA") == rpeCutOff(.pounds(225), 3))
}

/// Verbatim from the matrix: in every "for a" before a number, the "a" stood for the "8 at" of "135
/// for 8 at 9", so the number after it is no rep count.
@Test func aBetweenForAndANumberLetsForLabelNothing() {
    #expect(SpokenSet.parse("135 for a 9.") == .failure(.unrecognized))
    #expect(SpokenSet.parse("135 for a 9 RP.") == .failure(.unrecognized))
    #expect(SpokenSet.parse("225 for a triple at 8") == values(.pounds(225), 3, .eight))
    #expect(SpokenSet.parse("135 for a hundred reps") == values(.pounds(135), 100, nil))
    #expect(SpokenSet.parse("225 for 3 at a 9") == values(.pounds(225), 3, .nine))
}

@Test func aSingleADoubleAndATripleAreOneTwoAndThreeReps() {
    #expect(SpokenSet.parse("225 for a triple at 8") == values(.pounds(225), 3, .eight))
    #expect(SpokenSet.parse("315 for a single at 9") == values(.pounds(315), 1, .nine))
    #expect(SpokenSet.parse("225 for a double RPE 8") == values(.pounds(225), 2, .eight))
    #expect(SpokenSet.parse("225 for a triple 8") == .failure(.ambiguous))
    #expect(SpokenSet.parse("225, a triple, RPE 8") == values(.pounds(225), 3, .eight))
    #expect(SpokenSet.parse("8 reps at a triple") == .failure(.unrecognized))
}

/// A single, a double, or a triple is a rep count with its own label, never a digit of a number.
@Test func aSingleADoubleOrATripleNeverJoinsANumberWord() {
    #expect(SpokenSet.parse("one eighty single for 5") == .failure(.ambiguous))
    #expect(SpokenSet.parse("225 for twenty triple") == .failure(.ambiguous))
    #expect(SpokenSet.parse("one hundred double for 5") == .failure(.ambiguous))
    #expect(SpokenSet.parse("225 for 3 triple") == .failure(.conflicting(.reps)))
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
