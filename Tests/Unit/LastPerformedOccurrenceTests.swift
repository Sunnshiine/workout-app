import Foundation
import Testing

@testable import WorkoutTracker

// The canonical Last Performed value type (PRD #330 / #382): one Sendable occurrence with a
// single already-derived display text, that the persisted `LastPerformedEntry` initializes from
// and projects back to.

@Test func lastPerformedEntryRoundTripsThroughTheCanonicalOccurrence() {
    let occurrence = LastPerformedOccurrence(
        fullName: "2-3:1:0 BB RDL",
        baseName: "BB RDL",
        resultText: "185x7@7",
        performedOn: Date(timeIntervalSinceReferenceDate: 100),
        source: "Block 26 · W3 D1"
    )

    #expect(LastPerformedEntry(occurrence).occurrence == occurrence)
}

@Test func extractorEmitsCanonicalOccurrencesWithDerivedDisplayText() throws {
    let block = ParsedBlockModel(
        tabName: "Block 27",
        weeks: [
            occurrenceWeek(exercises: [
                occurrenceExercise("Squat", sets: [
                    occurrenceLoggedSet(index: 0, weight: 185, reps: 5, rpe: .seven),
                    occurrenceLoggedSet(index: 1, weight: 195, reps: 5, rpe: .eight)
                ])
            ])
        ]
    )

    let occurrence = try #require(LastPerformedExtractor.occurrences(from: block).first)

    #expect(occurrence.fullName == "Squat")
    #expect(occurrence.baseName == "Squat")
    #expect(occurrence.resultText == "185x5@7, 195x5@8")
    #expect(occurrence.source == "Block 27 · W1 D1")
}

// The three evidence shapes must derive byte-identical display text through the canonical type.

@Test func occurrenceDerivesSingleStructuredSetDisplayText() throws {
    let block = occurrenceBlock(
        occurrenceExercise("Bench Press", sets: [occurrenceLoggedSet(index: 0, weight: 155, reps: 6, rpe: .seven)])
    )

    let occurrence = try #require(LastPerformedExtractor.occurrences(from: block).first)
    #expect(occurrence.resultText == "155x6@7")
}

@Test func occurrenceDerivesMultiSetDisplayTextInSetOrderWithSkipAndUnstructuredTokens() throws {
    let block = occurrenceBlock(
        occurrenceExercise("Squat", sets: [
            occurrenceLoggedSet(index: 0, weight: 185, reps: 5, rpe: .seven),
            occurrenceSkippedSet(index: 1),
            occurrenceUnstructuredSet(index: 2, "tweaked back")
        ])
    )

    let occurrence = try #require(LastPerformedExtractor.occurrences(from: block).first)
    #expect(occurrence.resultText == "185x5@7, skip, tweaked back")
}

@Test func occurrenceDerivesLegacyLogRawText() throws {
    let block = occurrenceBlock(
        occurrenceExercise(
            "Standing Calve Raises",
            legacyLog: "25x12, 12",
            sets: [occurrenceLoggedUnstructuredSet(index: 0)]
        )
    )

    let occurrence = try #require(LastPerformedExtractor.occurrences(from: block).first)
    #expect(occurrence.resultText == "25x12, 12")
}

private func occurrenceBlock(_ exercise: ParsedExercise) -> ParsedBlockModel {
    ParsedBlockModel(tabName: "Block 27", weeks: [occurrenceWeek(exercises: [exercise])])
}

private func occurrenceWeek(exercises: [ParsedExercise]) -> ParsedWeek {
    ParsedWeek(number: 1, days: [ParsedSession(dayNumber: 1, date: nil, exercises: exercises)])
}

private func occurrenceExercise(_ name: String, legacyLog: String? = nil, sets: [ParsedSet]) -> ParsedExercise {
    ParsedExercise(name: name, baseName: name, cadence: nil, coachNote: nil, legacyLog: legacyLog, sets: sets)
}

private func occurrenceLoggedSet(index: Int, weight: Double, reps: Int, rpe: RPE) -> ParsedSet {
    ParsedSet(
        index: index,
        prescribedReps: "\(reps)",
        prescribedLoad: "RPE \(rpe.label)",
        percentOneRM: nil,
        setLog: SetLog(weight: .pounds(weight), reps: reps, rpe: rpe)
    )
}

private func occurrenceLoggedUnstructuredSet(index: Int) -> ParsedSet {
    ParsedSet(index: index, prescribedReps: "5", prescribedLoad: "RPE 7", percentOneRM: nil, state: .logged)
}

private func occurrenceUnstructuredSet(index: Int, _ text: String) -> ParsedSet {
    ParsedSet(
        index: index,
        prescribedReps: "5",
        prescribedLoad: "RPE 7",
        percentOneRM: nil,
        state: .logged,
        unstructuredSetLog: text
    )
}

private func occurrenceSkippedSet(index: Int) -> ParsedSet {
    ParsedSet(index: index, prescribedReps: "5", prescribedLoad: "RPE 7", percentOneRM: nil, state: .skipped)
}

private func occurrence(resultText: String) -> LastPerformedOccurrence {
    LastPerformedOccurrence(
        fullName: "Back Squat",
        baseName: "Back Squat",
        resultText: resultText,
        performedOn: Date(timeIntervalSinceReferenceDate: 0),
        source: "Block 27 · W1 D2"
    )
}

@Test func aLegacyLogOccurrenceHoldsNoSetLogs() {
    #expect(occurrence(resultText: "55x8, 60x7@9.5").setLogs == nil)
}

@Test func anOccurrenceWithASkipHoldsTheSetLogsAroundIt() {
    #expect(
        occurrence(resultText: "315x5@7, skip, 325x5@8").setLogs
            == [SetLog(weight: .pounds(315), reps: 5, rpe: .seven), SetLog(weight: .pounds(325), reps: 5, rpe: .eight)]
    )
}
