import Foundation
import Testing

@testable import WorkoutTracker

/// "4 at 9" can reach the transcript as "49", but "1 at 5" is rarely said, so only a second digit of
/// 6 to 9 reads two ways. A count of 100 or more reads two ways whatever its digits and however it was
/// said: the recognizer writes "808" for "8 at an 8", "343" for "3 for 3", and "110" for "1 at 10", and
/// nobody logs 100 reps unlabelled. Past 100 it is implausible, so the athlete is asked again.
@Test func aRepCountAfterForThatMayBeRepsAtAnRPEIsAmbiguous() {
    #expect(SpokenSet.parse("135 for 49") == .failure(.ambiguous))
    #expect(SpokenSet.parse("135 for 808") == .failure(.implausible(.reps)))
    #expect(SpokenSet.parse("225 for 343") == .failure(.implausible(.reps)))
    #expect(SpokenSet.parse("405 for 110") == .failure(.implausible(.reps)))
    #expect(SpokenSet.parse("135 for 100") == .failure(.ambiguous))
    #expect(SpokenSet.parse("four hundred five for one hundred") == .failure(.ambiguous))
    #expect(SpokenSet.parse("135 for one hundred") == .failure(.ambiguous))
    #expect(SpokenSet.parse("185 for one hundred and ten") == .failure(.implausible(.reps)))
    #expect(SpokenSet.parse("135 for a hundred") == .failure(.ambiguous))
    #expect(SpokenSet.parse("135 for one hundred reps") == values(.pounds(135), 100, nil))
    #expect(SpokenSet.parse("135 for 100 at 8") == values(.pounds(135), 100, .eight))
    #expect(SpokenSet.parse("BW for 129") == .failure(.implausible(.reps)))
    #expect(SpokenSet.parse("135 for 100 reps") == values(.pounds(135), 100, nil))
    #expect(SpokenSet.parse("135 for 808 at 8") == .failure(.implausible(.reps)))
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
