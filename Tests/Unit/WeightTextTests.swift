import Testing

@testable import WorkoutTracker

/// The weight-text rule ("BW" case-insensitively, else a finite number of pounds) and the
/// `SetLog(formatted:)` grammar built on it, pinned to literal inputs and outputs.

@Test(arguments: [
    ("185x5@8", SetLog(weight: .pounds(185), reps: 5, rpe: .eight)),
    ("bw x 12 @ 7", SetLog(weight: .bodyweight, reps: 12, rpe: .seven)),
    (" 100.5x3@9.5 ", SetLog(weight: .pounds(100.5), reps: 3, rpe: .ninePointFive))
])
func setLogParsesAFormattedEntry(raw: String, expected: SetLog) {
    #expect(SetLog(formatted: raw) == expected)
}

@Test(arguments: [
    "185x5", "185x5@", "185xfive@8", "infx5@8", "BWx12@nan", "185x5@8@9", "185x5x3@8", "185@5x8", "x@"
])
func setLogRejectsAMalformedEntry(raw: String) {
    #expect(SetLog(formatted: raw) == nil)
}

@Test func setLogFormattedRoundTripsThroughTheParser() {
    #expect(SetLog(formatted: "bw x 12 @ 7")?.formatted == "BWx12@7")
    #expect(SetLog(formatted: " 100.5x3@9.5 ")?.formatted == "100.5x3@9.5")
}

@Test(arguments: [
    ("BW", Weight.bodyweight),
    ("bw", .bodyweight),
    ("Bw", .bodyweight),
    ("185", .pounds(185)),
    ("100.5", .pounds(100.5)),
    ("-5", .pounds(-5)),
    ("0", .pounds(0))
])
func weightParsesItsText(text: String, expected: Weight) {
    #expect(Weight(text: text) == expected)
}

@Test(arguments: ["", " ", "BW ", "body weight", "five", "inf", "-inf", "nan", "185lb"])
func weightRejectsTextThatIsNeitherBodyweightNorAFiniteNumber(text: String) {
    #expect(Weight(text: text) == nil)
}
