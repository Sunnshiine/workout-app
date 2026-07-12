import Foundation
import Testing

@testable import WorkoutTracker

@Test func extractsLastPerformedEntriesFromLoggedParsedSets() throws {
    let olderDate = try #require(DateFormatter.testDate.date(from: "5/1/2026"))
    let newerDate = try #require(DateFormatter.testDate.date(from: "5/8/2026"))
    let block = ParsedBlockModel(
        tabName: "Block 27",
        weeks: [
            week(
                1,
                date: olderDate,
                exercises: [
                    exercise(
                        "Squat",
                        sets: [
                            loggedSet(index: 0, weight: 185, reps: 5, rpe: 7),
                            loggedSet(index: 1, weight: 195, reps: 5, rpe: 8)
                        ]
                    ),
                    exercise("Bench Press", sets: [loggedSet(index: 0, weight: 155, reps: 6, rpe: 7)])
                ]
            ),
            week(
                2,
                date: newerDate,
                exercises: [
                    exercise(
                        "Squat",
                        sets: [
                            pendingSet(index: 0),
                            loggedSet(index: 1, weight: 205, reps: 4, rpe: 8)
                        ]
                    ),
                    exercise("Deadlift", sets: [skippedSet(index: 0)])
                ]
            )
        ]
    )

    let entries = LastPerformedExtractor.entries(from: block)

    // Append-only: every evidence-bearing (Exercise, Session) occurrence is emitted —
    // Squat is logged in both weeks, so both entries survive instead of collapsing.
    #expect(entries.count == 3)

    let squats = entries.filter { $0.fullName == "Squat" }
    #expect(squats.count == 2)
    let olderSquat = try #require(squats.first { $0.source == "Block 27 · W1 D1" })
    #expect(olderSquat.performedOn == olderDate)
    #expect(olderSquat.displayResultText == "185x5@7, 195x5@8")
    let newerSquat = try #require(squats.first { $0.source == "Block 27 · W2 D1" })
    #expect(newerSquat.baseName == "Squat")
    #expect(newerSquat.result == SetLog(weight: .pounds(205), reps: 4, rpe: 8))
    #expect(newerSquat.performedOn == newerDate)

    let bench = try #require(entries.first { $0.fullName == "Bench Press" })
    #expect(bench.result == SetLog(weight: .pounds(155), reps: 6, rpe: 7))
    #expect(bench.source == "Block 27 · W1 D1")
}

@Test func emitsSeparateEntryPerSessionForARepeatedExercise() throws {
    let block = ParsedBlockModel(
        tabName: "Block 27",
        weeks: [
            week(1, date: nil, exercises: [
                exercise("Bench Press", sets: [loggedSet(index: 0, weight: 155, reps: 6, rpe: 7)])
            ]),
            week(2, date: nil, exercises: [
                exercise("Bench Press", sets: [loggedSet(index: 0, weight: 165, reps: 5, rpe: 8)])
            ])
        ]
    )

    let entries = LastPerformedExtractor.entries(from: block)

    #expect(entries.count == 2)
    #expect(Set(entries.map(\.source)) == ["Block 27 · W1 D1", "Block 27 · W2 D1"])
}

@Test func extractsEveryLoggedSetLogOfTheExerciseInSetOrder() throws {
    let block = ParsedBlockModel(
        tabName: "Block 27",
        weeks: [
            week(
                1,
                date: nil,
                exercises: [
                    exercise(
                        "BB RDL",
                        sets: [
                            loggedSet(index: 0, weight: 70, reps: 8, rpe: 8),
                            loggedSet(index: 1, weight: 75, reps: 8, rpe: 9.5)
                        ]
                    )
                ]
            )
        ]
    )

    let entry = try #require(LastPerformedExtractor.entries(from: block).first)

    #expect(entry.displayResultText == "70x8@8, 75x8@9.5")
    #expect(entry.result == nil)
}

@Test func multiSetEvidenceKeepsSkipMarkersButDropsPendingSets() throws {
    let block = ParsedBlockModel(
        tabName: "Block 27",
        weeks: [
            week(
                1,
                date: nil,
                exercises: [
                    exercise(
                        "Squat",
                        sets: [
                            loggedSet(index: 2, weight: 205, reps: 5, rpe: 9),
                            skippedSet(index: 1),
                            loggedSet(index: 0, weight: 185, reps: 5, rpe: 7),
                            pendingSet(index: 3)
                        ]
                    )
                ]
            )
        ]
    )

    let entry = try #require(LastPerformedExtractor.entries(from: block).first)

    // Partial skips survive into the display string in Set order (ADR-0012); pending
    // Sets, which carry no evidence, are dropped.
    #expect(entry.displayResultText == "185x5@7, skip, 205x5@9")
}

@Test func unstructuredOnlyExerciseProducesEntryWithRawEnteredText() throws {
    let block = ParsedBlockModel(
        tabName: "Block 27",
        weeks: [
            week(
                1,
                date: nil,
                exercises: [
                    exercise(
                        "Standing Calve Raises",
                        sets: [
                            unstructuredSet(index: 0, "a few sets of 12"),
                            unstructuredSet(index: 1, "felt easy")
                        ]
                    )
                ]
            )
        ]
    )

    let entry = try #require(LastPerformedExtractor.entries(from: block).first)

    // Unstructured Set Logs now count as completion evidence (ADR-0012), rendered as
    // the raw entered text in Set order — never normalized.
    #expect(entry.displayResultText == "a few sets of 12, felt easy")
    #expect(entry.result == nil)
}

@Test func mixedStructuredAndUnstructuredLinesProduceEntry() throws {
    let block = ParsedBlockModel(
        tabName: "Block 27",
        weeks: [
            week(
                1,
                date: nil,
                exercises: [
                    exercise(
                        "Squat",
                        sets: [
                            loggedSet(index: 0, weight: 185, reps: 5, rpe: 7),
                            unstructuredSet(index: 1, "amrap")
                        ]
                    )
                ]
            )
        ]
    )

    let entry = try #require(LastPerformedExtractor.entries(from: block).first)

    #expect(entry.displayResultText == "185x5@7, amrap")
    #expect(entry.result == nil)
}

@Test func fullySkippedOccurrenceProducesNoEntry() {
    let block = ParsedBlockModel(
        tabName: "Block 27",
        weeks: [
            week(
                1,
                date: nil,
                exercises: [
                    exercise(
                        "Squat",
                        sets: [
                            skippedSet(index: 0),
                            skippedSet(index: 1)
                        ]
                    )
                ]
            )
        ]
    )

    #expect(LastPerformedExtractor.entries(from: block).isEmpty)
}

@Test func partialSkipsKeepSkipMarkersAlongsideUnstructuredEvidence() throws {
    let block = ParsedBlockModel(
        tabName: "Block 27",
        weeks: [
            week(
                1,
                date: nil,
                exercises: [
                    exercise(
                        "Squat",
                        sets: [
                            loggedSet(index: 0, weight: 185, reps: 5, rpe: 7),
                            skippedSet(index: 1),
                            unstructuredSet(index: 2, "tweaked back")
                        ]
                    )
                ]
            )
        ]
    )

    let entry = try #require(LastPerformedExtractor.entries(from: block).first)

    #expect(entry.displayResultText == "185x5@7, skip, tweaked back")
}

@Test func singleSetEvidenceKeepsStructuredResult() throws {
    let block = ParsedBlockModel(
        tabName: "Block 27",
        weeks: [
            week(
                1,
                date: nil,
                exercises: [
                    exercise("Bench Press", sets: [loggedSet(index: 0, weight: 155, reps: 6, rpe: 7)])
                ]
            )
        ]
    )

    let entry = try #require(LastPerformedExtractor.entries(from: block).first)

    #expect(entry.result == SetLog(weight: .pounds(155), reps: 6, rpe: 7))
    #expect(entry.displayResultText == "155x6@7")
}

@Test func extractorReturnsEmptyArrayWithoutLoggedSets() {
    let block = ParsedBlockModel(
        tabName: "Block 27",
        weeks: [
            week(
                1,
                date: nil,
                exercises: [
                    exercise(
                        "Squat",
                        sets: [
                            pendingSet(index: 0),
                            skippedSet(index: 1)
                        ]
                    )
                ]
            )
        ]
    )

    #expect(LastPerformedExtractor.entries(from: block).isEmpty)
}

@Test func extractsLegacyLogWhenStructuredSetLogsAreAbsent() throws {
    let performedDate = try #require(DateFormatter.testDate.date(from: "5/8/2026"))
    let block = ParsedBlockModel(
        tabName: "Block 27",
        weeks: [
            week(
                1,
                date: performedDate,
                exercises: [
                    exercise(
                        "Standing Calve Raises",
                        legacyLog: "25x12, 12",
                        sets: [
                            loggedUnstructuredSet(index: 0),
                            loggedUnstructuredSet(index: 1)
                        ]
                    )
                ]
            )
        ]
    )

    let entry = try #require(LastPerformedExtractor.entries(from: block).first)

    #expect(entry.fullName == "Standing Calve Raises")
    #expect(entry.resultText == "25x12, 12")
    #expect(entry.result == nil)
    #expect(entry.performedOn == performedDate)
    #expect(entry.source == "Block 27 · W1 D1")
}

@Test func structuredSetLogsTakePrecedenceOverLegacyLogsForLastPerformed() throws {
    let block = ParsedBlockModel(
        tabName: "Block 27",
        weeks: [
            week(
                1,
                date: nil,
                exercises: [
                    exercise(
                        "Standing Calve Raises",
                        legacyLog: "25x12, 12",
                        sets: [
                            loggedSet(index: 0, weight: 35, reps: 12, rpe: 9)
                        ]
                    )
                ]
            )
        ]
    )

    let entry = try #require(LastPerformedExtractor.entries(from: block).first)

    #expect(entry.displayResultText == "35x12@9")
    #expect(entry.result == SetLog(weight: .pounds(35), reps: 12, rpe: 9))
}

private func week(_ number: Int, date: Date?, exercises: [ParsedExercise]) -> ParsedWeek {
    ParsedWeek(
        number: number,
        days: [
            ParsedSession(dayNumber: 1, date: date, exercises: exercises)
        ]
    )
}

private func exercise(_ name: String, legacyLog: String? = nil, sets: [ParsedSet]) -> ParsedExercise {
    ParsedExercise(name: name, baseName: name, cadence: nil, coachNote: nil, legacyLog: legacyLog, sets: sets)
}

private func loggedSet(index: Int, weight: Double, reps: Int, rpe: Double) -> ParsedSet {
    ParsedSet(
        index: index,
        prescribedReps: "\(reps)",
        prescribedLoad: "RPE \(Int(rpe))",
        percentOneRM: nil,
        setLog: SetLog(weight: .pounds(weight), reps: reps, rpe: rpe)
    )
}

private func pendingSet(index: Int) -> ParsedSet {
    ParsedSet(index: index, prescribedReps: "5", prescribedLoad: "RPE 7", percentOneRM: nil)
}

private func loggedUnstructuredSet(index: Int) -> ParsedSet {
    ParsedSet(index: index, prescribedReps: "5", prescribedLoad: "RPE 7", percentOneRM: nil, state: .logged)
}

private func unstructuredSet(index: Int, _ text: String) -> ParsedSet {
    ParsedSet(
        index: index,
        prescribedReps: "5",
        prescribedLoad: "RPE 7",
        percentOneRM: nil,
        state: .logged,
        unstructuredSetLog: text
    )
}

private func skippedSet(index: Int) -> ParsedSet {
    ParsedSet(index: index, prescribedReps: "5", prescribedLoad: "RPE 7", percentOneRM: nil, state: .skipped)
}

extension DateFormatter {
    fileprivate static let testDate: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "M/d/yyyy"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return formatter
    }()
}
