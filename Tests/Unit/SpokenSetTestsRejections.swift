import Foundation
import Testing

@testable import WorkoutTracker

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

/// No lifter logs more than 100 reps or a weight finer than the lightest fractional plate, so such a
/// value is more likely misheard than said, as "12.47" for "1247".
@Test func aValueNoLifterLogsIsImplausible() {
    #expect(SpokenSet.parse("135 for 101 at 8") == .failure(.implausible(.reps)))
    #expect(SpokenSet.parse("135 for 101 reps") == .failure(.implausible(.reps)))
    #expect(SpokenSet.parse("180 for 546") == .failure(.implausible(.reps)))
    #expect(SpokenSet.parse("12.47 for 49") == .failure(.implausible(.weight)))
    #expect(SpokenSet.parse("180 for 546 reps at 8") == .failure(.implausible(.reps)))
    #expect(SpokenSet.parse("135 for 100 reps") == values(.pounds(135), 100, nil))
    #expect(SpokenSet.parse("12.47 for 3") == .failure(.implausible(.weight)))
    #expect(SpokenSet.parse("187.55 for 5") == .failure(.implausible(.weight)))
    #expect(SpokenSet.parse("135.123456 for 5") == .failure(.implausible(.weight)))
    #expect(SpokenSet.parse("185.1 pounds") == .failure(.implausible(.weight)))
    #expect(SpokenSet.parse("182.25 for 3") == values(.pounds(182.25), 3, nil))
    #expect(SpokenSet.parse("137.5 for 3") == values(.pounds(137.5), 3, nil))
}

/// Speaking logs any weight and rep count a lifter logs, so none of these is refused for being
/// light, fine, or many reps.
private let anyValueALifterLogs: [(transcript: String, weight: Weight?, reps: Int?, rpe: RPE?)] = [
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
    ("135 for 30", .pounds(135), 30, nil), ("135 for 100 reps", .pounds(135), 100, nil), ("135 for 100 at 8", .pounds(135), 100, .eight),
    ("135 for 49 reps", .pounds(135), 49, nil), ("135 for 49 at 8", .pounds(135), 49, .eight),
    ("RPE 8, 135 for 49", .pounds(135), 49, .eight), ("49 reps", nil, 49, nil), ("bodyweight for 50", .bodyweight, 50, nil),
    ("182.25 for 3", .pounds(182.25), 3, nil), ("137.5 for 3", .pounds(137.5), 3, nil), ("185.75 pounds", .pounds(185.75), nil, nil),
    ("187.25 for 5", .pounds(187.25), 5, nil), ("20 for 20", .pounds(20), 20, nil)
]

@Test(
    "Any weight and rep count a lifter logs is heard as said",
    arguments: anyValueALifterLogs
)
func anyWeightAndRepCountALifterLogsIsHeard(transcript: String, weight: Weight?, reps: Int?, rpe: RPE?) {
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
        "185 for 5 at 8¾", "185 for 5 at 80%", "185+58", "185 for 5 and 8 reps", "185 for 5 at 8 reps"
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
    "Five or more digits with no for or pounds right after them are numbers run together",
    arguments: ["40542 at nine.", "18545 at 8.", "13544 at RPE 9.", "31541 at 9.5.", "405429", "13544, 8 reps, RPE 9", "13548"]
)
func fiveOrMoreDigitsThatMayHideAValueAreFused(transcript: String) {
    #expect(SpokenSet.parse(transcript) == .failure(.fusedNumber))
}

@Test(
    "A number of 1,000 or more is the weight when for, then the reps and the RPE, or pounds, then the reps, follow it",
    arguments: [
        ("1000 for 5 at 8", values(.pounds(1000), 5, .eight)), ("1005 for 5 at 8", values(.pounds(1005), 5, .eight)),
        ("1500 for 5 at 8", values(.pounds(1500), 5, .eight)), ("1000 pounds for 1 at 10", values(.pounds(1000), 1, .ten)),
        ("2000 for 1 at 10", values(.pounds(2000), 1, .ten)), ("1002.5 for 3 at 9.5", values(.pounds(1002.5), 3, .ninePointFive)),
        ("1005 by 1, RPE 10", values(.pounds(1005), 1, .ten)), ("1005 pounds for 1", values(.pounds(1005), 1, nil)),
        ("1005 lb, 5 reps", values(.pounds(1005), 5, nil)), ("9999 x 1 @ 10", values(.pounds(9999), 1, .ten)),
        ("10000 for 5 at 8", values(.pounds(10000), 5, .eight)), ("25,000 pounds for 1", values(.pounds(25000), 1, nil)),
        ("1000 for 5 and 8", rpeCutOff(.pounds(1000), 5, .number(8))), ("1005 for one to 10", rpeCutOff(.pounds(1005), 1, .number(10)))
    ]
)
private func aNumberOfAThousandOrMoreThatHidesNoValueIsTheWeight(transcript: String, heard: HeardSpokenSet) {
    #expect(SpokenSet.parse(transcript) == heard)
}

@Test(
    "A thousand, a teen of hundreds, and a teen before the tens read as one number, as athletes say them",
    arguments: [
        ("one thousand for 5 at 8", values(.pounds(1000), 5, .eight)), ("a thousand for 2 at 9", values(.pounds(1000), 2, .nine)),
        ("one thousand five for 5 at 8", values(.pounds(1005), 5, .eight)),
        ("one thousand and five for 1 at 10", values(.pounds(1005), 1, .ten)),
        ("one thousand five hundred for 1 at 10", values(.pounds(1500), 1, .ten)),
        ("two thousand two hundred and fifty pounds for 1", values(.pounds(2250), 1, nil)),
        ("one thousand and a half for 1 at 10", values(.pounds(1000.5), 1, .ten)),
        ("thousand fifty for 1 at 10", values(.pounds(1050), 1, .ten)),
        ("eleven hundred for 5 at 8", values(.pounds(1100), 5, .eight)),
        ("fifteen hundred and fifty for 1 at 10", values(.pounds(1550), 1, .ten)),
        ("twenty five hundred pounds for 1", values(.pounds(2500), 1, nil)), ("ten fifty for 5 at 8", values(.pounds(1050), 5, .eight)),
        ("ten oh five for 1 at 10", values(.pounds(1005), 1, .ten)), ("twelve twenty five for 3 at 9", values(.pounds(1225), 3, .nine)),
        ("one thousand pounds for 1 at 10", values(.pounds(1000), 1, .ten)),
        ("ten thousand for 5 at 8", values(.pounds(10000), 5, .eight)),
        ("twenty five thousand pounds for 1", values(.pounds(25000), 1, nil))
    ]
)
private func thousandsSaidInWordsReadAsTheNumberMeant(transcript: String, heard: HeardSpokenSet) {
    #expect(SpokenSet.parse(transcript) == heard)
}

/// "one thousand five" may be "1000 for 5" and "ten fifty" "10 for 50", so a number of 1,000 or more
/// said in words meets the same rule as one in digits.
@Test(
    "A number of 1,000 or more said in words that may hide another value is numbers run together",
    arguments: [
        "one thousand for 5", "one thousand five", "ten fifty", "eleven hundred", "a thousand at 8", "twelve twenty reps",
        "135 for twelve ten", "135 for one thousand at 8", "ten thousand at 8"
    ]
)
func aNumberOfAThousandOrMoreInWordsThatMayHideAValueIsFused(transcript: String) {
    #expect(SpokenSet.parse(transcript) == .failure(.fusedNumber))
}

/// The recognizer writes a weight of 1,000 or more with a comma before its last three digits, and a
/// comma before anything else is punctuation.
@Test func aCommaBeforeThreeDigitsSeparatesThousands() {
    #expect(SpokenSet.parse("1,000 for 5 at 8") == values(.pounds(1000), 5, .eight))
    #expect(SpokenSet.parse("1,005 pounds for 5 at 8") == values(.pounds(1005), 5, .eight))
    #expect(SpokenSet.parse("£1,005 for 1 at 10") == values(.pounds(1005), 1, .ten))
    #expect(SpokenSet.parse("1,002.5 for 3 at 9") == values(.pounds(1002.5), 3, .nine))
    #expect(SpokenSet.parse("1,000") == .failure(.fusedNumber))
    #expect(SpokenSet.parse("1,000,000 for 5 at 8") == values(.pounds(1_000_000), 5, .eight))
    #expect(SpokenSet.parse("135, 8 reps, RPE 9") == values(.pounds(135), 8, .nine))
    #expect(SpokenSet.parse("135,8 reps, RPE 9") == values(.pounds(135), 8, .nine))
    #expect(SpokenSet.parse("135,85 for 5") == .failure(.ambiguous))
    #expect(SpokenSet.parse("185 for 5,8") == .failure(.ambiguous))
    #expect(SpokenSet.parse("1,0005 for 5 at 8") == .failure(.unrecognized))
}

/// "1358" may be "135 for 8" and "4510" "45 for 10", so a number of 1,000 or more that words do not
/// show hides no value is numbers run together, even where the rest would read.
@Test(
    "A number of 1,000 or more that may hide another value is numbers run together",
    arguments: [
        "1358", "1358 at 9", "4510", "405-4209", "1000 for 5", "1005 for 1, 8", "1358 reps at 9", "1358 reps, RPE 9", "1005 pounds",
        "1005 pounds at 8", "135 for 1000 at 8", "135 for 5 at 1000", "8 reps at 1005 pounds", "2000.5 for 5", "1854.5 for 5",
        "2543 at an island", "4105 or one at 10", "1854 5 rips at our PE8.", "1005, 1 rep, RPE 10",
        "1000 at 8 for 5"
    ]
)
func aNumberOfAThousandOrMoreThatMayHideAValueIsFused(transcript: String) {
    #expect(SpokenSet.parse(transcript) == .failure(.fusedNumber))
}
