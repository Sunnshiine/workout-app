import Testing

@testable import WorkoutTracker

@Test func parsesTrainingMaxValuesFromHeaderArea() {
    let grid = gridFromA1(
        [
            "E6": "Training Max",
            "C7": "Squat", "E7": "365",
            "C8": "Bench Press", "E8": "245",
            "C9": "Deadlift", "E9": "455"
        ],
        rows: 20,
        cols: 10
    )

    let tm = parseTrainingMax(from: grid)

    #expect(tm[.squat] == 365)
    #expect(tm[.bench] == 245)
    #expect(tm[.deadlift] == 455)
}

@Test func parsesTrainingMaxValuesFromShiftedHeaderArea() {
    let grid = gridFromA1(
        [
            "G7": "Training Max",
            "E8": "Squat", "G8": "405",
            "E9": "Bench Press", "G9": "275",
            "E10": "Deadlift", "G10": "495"
        ],
        rows: 20,
        cols: 10
    )

    let tm = parseTrainingMax(from: grid)

    #expect(tm[.squat] == 405)
    #expect(tm[.bench] == 275)
    #expect(tm[.deadlift] == 495)
}

@Test func trainingMaxValuesAreNilWhenHeaderIsMissingOrValuesAreBlank() {
    let missingHeader = parseTrainingMax(from: gridFromA1([:], rows: 20, cols: 10))
    #expect(missingHeader[.squat] == nil)
    #expect(missingHeader[.bench] == nil)
    #expect(missingHeader[.deadlift] == nil)

    let blankValues = parseTrainingMax(
        from: gridFromA1(
            [
                "E6": "Training Max",
                "C7": "Squat", "E7": "",
                "C8": "Bench Press", "E8": " ",
                "C9": "Deadlift"
            ],
            rows: 20,
            cols: 10
        )
    )
    #expect(blankValues[.squat] == nil)
    #expect(blankValues[.bench] == nil)
    #expect(blankValues[.deadlift] == nil)
}

@Test func aRepeatedTrainingMaxLabelTakesTheFirstParsableValue() {
    let blankThenValue = parseTrainingMax(
        from: gridFromA1(
            ["E6": "Training Max", "C7": "Squat", "E7": "", "C8": "Squat", "E8": "365"],
            rows: 20,
            cols: 10
        )
    )
    #expect(blankThenValue[.squat] == 365)

    let twoValues = parseTrainingMax(
        from: gridFromA1(
            ["E6": "Training Max", "C7": "Squat", "E7": "365", "C8": "Squat", "E8": "400"],
            rows: 20,
            cols: 10
        )
    )
    #expect(twoValues[.squat] == 365)
}

@Test(
    "A Training Max that is not a finite number is absent, as a non-numeric cell is",
    arguments: ["inf", "nan", "Infinity", "1e400", "-nan", "snan"]
)
func aNonFiniteTrainingMaxIsAbsent(cell: String) {
    let tm = parseTrainingMax(
        from: gridFromA1(
            ["E6": "Training Max", "C7": "Squat", "E7": cell, "C8": "Bench Press", "E8": "365"],
            rows: 20,
            cols: 10
        )
    )

    #expect(tm == [.bench: 365])
}

@Test func aRepeatedTrainingMaxLabelPassesOverANonFiniteValue() {
    let tm = parseTrainingMax(
        from: gridFromA1(
            ["E6": "Training Max", "C7": "Squat", "E7": "inf", "C8": "Squat", "E8": "365"],
            rows: 20,
            cols: 10
        )
    )

    #expect(tm == [.squat: 365])
}
