import Foundation
import Testing

@testable import WorkoutTracker

private func entry(
    fullName: String,
    baseName: String,
    resultText: String,
    source: String,
    performedOn: Date
) -> ExerciseHistoryEntry {
    ExerciseHistoryEntry(
        fullName: fullName,
        baseName: baseName,
        resultText: resultText,
        source: source,
        performedOn: performedOn
    )
}

private func date(_ daysAgo: Int) -> Date {
    Date(timeIntervalSince1970: 1_700_000_000) - Double(daysAgo) * 86_400
}

@Test func historySheetTitleAndSubtitleUseMovementNameAndCap() {
    let presentation = ExerciseHistorySheetPresentation(
        anchorBaseName: "Bench Press",
        entries: [
            entry(
                fullName: "Bench Press",
                baseName: "Bench Press",
                resultText: "185x5@8",
                source: "Block 27 · W1 D1",
                performedOn: date(1)
            )
        ]
    )

    #expect(presentation.title == "Bench Press")
    #expect(presentation.subtitle == "Exercise History · last 5")
}

@Test func historySheetGroupsUnderBlockHeadersNewestFirst() {
    let entries = [
        entry(fullName: "Bench Press", baseName: "Bench Press", resultText: "185x5@8",
              source: "Block 26 · W2 D1", performedOn: date(30)),
        entry(fullName: "Bench Press", baseName: "Bench Press", resultText: "190x5@8",
              source: "Block 27 · W1 D1", performedOn: date(10)),
        entry(fullName: "Bench Press", baseName: "Bench Press", resultText: "195x5@8",
              source: "Block 27 · W2 D1", performedOn: date(3)),
    ]

    let presentation = ExerciseHistorySheetPresentation(anchorBaseName: "Bench Press", entries: entries)

    #expect(presentation.blocks.map(\.header) == ["BLOCK 27", "BLOCK 26"])
    // Newest Block first, strict recency within: W2 (3 days ago) before W1 (10 days ago).
    #expect(presentation.blocks[0].rows.map(\.gutter) == ["W2 D1", "W1 D1"])
    #expect(presentation.blocks[1].rows.map(\.gutter) == ["W2 D1"])
}

@Test func historyRowSplitsStructuredSetsWithMutedRPE() {
    let presentation = ExerciseHistorySheetPresentation(
        anchorBaseName: "Bench Press",
        entries: [
            entry(fullName: "Bench Press", baseName: "Bench Press",
                  resultText: "27.5x10@8, 27.5x10@8, 27.5x9@9",
                  source: "Block 27 · W1 D1", performedOn: date(1))
        ]
    )

    let row = presentation.blocks[0].rows[0]
    #expect(row.segments == [
        .log(load: "27.5×10", rpe: "8"),
        .log(load: "27.5×10", rpe: "8"),
        .log(load: "27.5×9", rpe: "9"),
    ])
    #expect(row.asEntered == false)
    #expect(row.asName == nil)
}

@Test func historyRowCarriesCadenceBeneathGutter() {
    let presentation = ExerciseHistorySheetPresentation(
        anchorBaseName: "Squat",
        entries: [
            entry(fullName: "3-0:1:0 Squat", baseName: "Squat", resultText: "315x3@8",
                  source: "Block 27 · W1 D1", performedOn: date(1))
        ]
    )

    #expect(presentation.blocks[0].rows[0].cadence == "3-0:1:0")
}

@Test func historyRowRendersPartialSkipMarkersInline() {
    let presentation = ExerciseHistorySheetPresentation(
        anchorBaseName: "Bench Press",
        entries: [
            entry(fullName: "Bench Press", baseName: "Bench Press",
                  resultText: "185x5@8, skip, 185x4@9",
                  source: "Block 27 · W1 D1", performedOn: date(1))
        ]
    )

    let row = presentation.blocks[0].rows[0]
    #expect(row.segments == [
        .log(load: "185×5", rpe: "8"),
        .skip,
        .log(load: "185×4", rpe: "9"),
    ])
    #expect(row.asEntered == false)
}

@Test func historyRowRendersLegacyTextAsEnteredNeverNormalized() {
    let raw = "worked up to 315, felt easy"
    let presentation = ExerciseHistorySheetPresentation(
        anchorBaseName: "Squat",
        entries: [
            entry(fullName: "Squat", baseName: "Squat", resultText: raw,
                  source: "Block 27 · W1 D1", performedOn: date(1))
        ]
    )

    let row = presentation.blocks[0].rows[0]
    #expect(row.segments == [.raw(raw)])
    #expect(row.asEntered == true)
}

@Test func historyRowAnnotatesSpellingVariantAsName() {
    let presentation = ExerciseHistorySheetPresentation(
        anchorBaseName: "Standing Calf Raise",
        entries: [
            entry(fullName: "Standing Calve Raises", baseName: "Standing Calve Raises",
                  resultText: "90x12@8", source: "Block 27 · W1 D1", performedOn: date(1))
        ]
    )

    #expect(presentation.blocks[0].rows[0].asName == "Standing Calve Raises")
}

@Test func historyRowDoesNotAnnotateCaseOnlyDifference() {
    let presentation = ExerciseHistorySheetPresentation(
        anchorBaseName: "Bench Press",
        entries: [
            entry(fullName: "bench press", baseName: "bench press", resultText: "185x5@8",
                  source: "Block 27 · W1 D1", performedOn: date(1))
        ]
    )

    #expect(presentation.blocks[0].rows[0].asName == nil)
}

@Test func historySheetCapsAtFiveEntriesNewestFirst() {
    let entries = (0..<8).map { index in
        entry(fullName: "Bench Press", baseName: "Bench Press", resultText: "\(180 + index)x5@8",
              source: "Block 27 · W\(index + 1) D1", performedOn: date(index))
    }

    let presentation = ExerciseHistorySheetPresentation(anchorBaseName: "Bench Press", entries: entries)

    let rowCount = presentation.blocks.reduce(0) { $0 + $1.rows.count }
    #expect(rowCount == 5)
    // date(0) is newest; the five kept are indices 0...4.
    #expect(presentation.blocks[0].rows.first?.gutter == "W1 D1")
    #expect(presentation.blocks[0].rows.last?.gutter == "W5 D1")
}

@Test func historySheetWithFewerThanFiveShowsWhatExists() {
    let entries = [
        entry(fullName: "Bench Press", baseName: "Bench Press", resultText: "185x5@8",
              source: "Block 27 · W1 D1", performedOn: date(1)),
        entry(fullName: "Bench Press", baseName: "Bench Press", resultText: "190x5@8",
              source: "Block 27 · W2 D1", performedOn: date(0)),
    ]

    let presentation = ExerciseHistorySheetPresentation(anchorBaseName: "Bench Press", entries: entries)

    let rowCount = presentation.blocks.reduce(0) { $0 + $1.rows.count }
    #expect(rowCount == 2)
    #expect(presentation.isEmpty == false)
}
