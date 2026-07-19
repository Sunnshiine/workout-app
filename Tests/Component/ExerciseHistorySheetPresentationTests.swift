import Foundation
import Testing

@testable import WorkoutTracker

private func entry(
    fullName: String,
    baseName: String,
    resultText: String,
    source: String,
    performedOn: Date
) -> LastPerformedOccurrence {
    LastPerformedOccurrence(
        fullName: fullName,
        baseName: baseName,
        resultText: resultText,
        performedOn: performedOn,
        source: source
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
        entry(
            fullName: "Bench Press",
            baseName: "Bench Press",
            resultText: "185x5@8",
            source: "Block 26 · W2 D1",
            performedOn: date(30)
        ),
        entry(
            fullName: "Bench Press",
            baseName: "Bench Press",
            resultText: "190x5@8",
            source: "Block 27 · W1 D1",
            performedOn: date(10)
        ),
        entry(
            fullName: "Bench Press",
            baseName: "Bench Press",
            resultText: "195x5@8",
            source: "Block 27 · W2 D1",
            performedOn: date(3)
        )
    ]

    let presentation = ExerciseHistorySheetPresentation(anchorBaseName: "Bench Press", entries: entries)

    #expect(presentation.blocks.map(\.header) == ["BLOCK 27", "BLOCK 26"])
    // Newest Block first, strict recency within: W2 (3 days ago) before W1 (10 days ago).
    #expect(presentation.blocks[0].rows.map(\.gutter) == ["W2 D1", "W1 D1"])
    #expect(presentation.blocks[1].rows.map(\.gutter) == ["W2 D1"])
}

@Test func historyRowSplitsStructuredSetsIntoChipsWithMutedRPE() {
    let presentation = ExerciseHistorySheetPresentation(
        anchorBaseName: "Bench Press",
        entries: [
            entry(
                fullName: "Bench Press",
                baseName: "Bench Press",
                resultText: "27.5x10@8, 27.5x10@8, 27.5x9@9",
                source: "Block 27 · W1 D1",
                performedOn: date(1)
            )
        ]
    )

    let row = presentation.blocks[0].rows[0]
    #expect(
        row.chips == [
            .init(load: "27.5×10", rpe: "8"),
            .init(load: "27.5×10", rpe: "8"),
            .init(load: "27.5×9", rpe: "9")
        ]
    )
    // A clean structured entry hides nothing: no `*`, no well.
    #expect(row.annotations.isEmpty)
    #expect(row.hasWell == false)
}

@Test func historyRowCarriesCadenceBeneathGutter() {
    let presentation = ExerciseHistorySheetPresentation(
        anchorBaseName: "Squat",
        entries: [
            entry(
                fullName: "3-0:1:0 Squat",
                baseName: "Squat",
                resultText: "315x3@8",
                source: "Block 27 · W1 D1",
                performedOn: date(1)
            )
        ]
    )

    #expect(presentation.blocks[0].rows[0].cadence == "3-0:1:0")
}

@Test func historyRowOmitsSkippedSetsAndCollectsThemInTheWell() {
    // Skipped Sets never render as chips — they hide behind the `*` well (DESIGN.md §5.6).
    let presentation = ExerciseHistorySheetPresentation(
        anchorBaseName: "Bench Press",
        entries: [
            entry(
                fullName: "Bench Press",
                baseName: "Bench Press",
                resultText: "185x5@8, skip, 185x4@9",
                source: "Block 27 · W1 D1",
                performedOn: date(1)
            )
        ]
    )

    let row = presentation.blocks[0].rows[0]
    #expect(
        row.chips == [
            .init(load: "185×5", rpe: "8"),
            .init(load: "185×4", rpe: "9")
        ]
    )
    #expect(row.annotations == [.skipped(1)])
    #expect(row.hasWell)
}

@Test func historyRowParsesStructuredTokensWhileHidingRawnessInTheWell() {
    // A mixed entry (a structured Set Log followed by an Unstructured Set Log): the structured token
    // becomes a chip; the free text hides in the `*` well rather than sitting in the ledger.
    let presentation = ExerciseHistorySheetPresentation(
        anchorBaseName: "Squat",
        entries: [
            entry(
                fullName: "Squat",
                baseName: "Squat",
                resultText: "185x5@7, amrap",
                source: "Block 27 · W1 D1",
                performedOn: date(1)
            )
        ]
    )

    let row = presentation.blocks[0].rows[0]
    #expect(row.chips == [.init(load: "185×5", rpe: "7")])
    #expect(row.annotations == [.asEntered("amrap")])
}

@Test func historyRowKeepsInternalCommasOfARawSetLogInTheWell() {
    // Raw text hidden in the well must render verbatim — adjacent fragments coalesce back with ", "
    // rather than becoming separate segments (ADR-0005 "never normalized").
    let presentation = ExerciseHistorySheetPresentation(
        anchorBaseName: "Squat",
        entries: [
            entry(
                fullName: "Squat",
                baseName: "Squat",
                resultText: "185x5@7, amrap, felt smooth",
                source: "Block 27 · W1 D1",
                performedOn: date(1)
            )
        ]
    )

    let row = presentation.blocks[0].rows[0]
    #expect(row.chips == [.init(load: "185×5", rpe: "7")])
    #expect(row.annotations == [.asEntered("amrap, felt smooth")])
}

@Test func historyRowRendersLegacyTextBestEffortWithTheRawnessInTheWell() {
    // A fully Legacy Log parses best-effort into chips (none here) and keeps its raw text verbatim in
    // the well (ADR-0005). Nothing is normalized into the ledger.
    let raw = "worked up to 315, felt easy"
    let presentation = ExerciseHistorySheetPresentation(
        anchorBaseName: "Squat",
        entries: [
            entry(
                fullName: "Squat",
                baseName: "Squat",
                resultText: raw,
                source: "Block 27 · W1 D1",
                performedOn: date(1)
            )
        ]
    )

    let row = presentation.blocks[0].rows[0]
    #expect(row.chips.isEmpty)
    #expect(row.annotations == [.asEntered(raw)])
    #expect(row.hasWell)
}

@Test func historyRowAnnotatesSpellingVariantInTheWell() {
    let presentation = ExerciseHistorySheetPresentation(
        anchorBaseName: "Standing Calf Raise",
        entries: [
            entry(
                fullName: "Standing Calve Raises",
                baseName: "Standing Calve Raises",
                resultText: "90x12@8",
                source: "Block 27 · W1 D1",
                performedOn: date(1)
            )
        ]
    )

    let row = presentation.blocks[0].rows[0]
    #expect(row.chips == [.init(load: "90×12", rpe: "8")])
    #expect(row.annotations == [.asName("Standing Calve Raises")])
}

@Test func historyRowDoesNotAnnotateCaseOnlyDifference() {
    let presentation = ExerciseHistorySheetPresentation(
        anchorBaseName: "Bench Press",
        entries: [
            entry(
                fullName: "bench press",
                baseName: "bench press",
                resultText: "185x5@8",
                source: "Block 27 · W1 D1",
                performedOn: date(1)
            )
        ]
    )

    #expect(presentation.blocks[0].rows[0].annotations.isEmpty)
    #expect(presentation.blocks[0].rows[0].hasWell == false)
}

@Test func historyWellOrdersSpellingThenSkipsThenRawness() {
    // A single entry can carry every annotation kind — the well keeps a stable order so the view can
    // render it deterministically: spelling first, then skips, then the raw text.
    let presentation = ExerciseHistorySheetPresentation(
        anchorBaseName: "Squat",
        entries: [
            entry(
                fullName: "Squat",
                baseName: "Squats",
                resultText: "315x3@8, skip, amrap",
                source: "Block 27 · W1 D1",
                performedOn: date(1)
            )
        ]
    )

    #expect(
        presentation.blocks[0].rows[0].annotations == [
            .asName("Squats"),
            .skipped(1),
            .asEntered("amrap")
        ]
    )
}

@Test func historySheetCapsAtFiveEntriesNewestFirst() {
    let entries = (0..<8).map { index in
        entry(
            fullName: "Bench Press",
            baseName: "Bench Press",
            resultText: "\(180 + index)x5@8",
            source: "Block 27 · W\(index + 1) D1",
            performedOn: date(index)
        )
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
        entry(
            fullName: "Bench Press",
            baseName: "Bench Press",
            resultText: "185x5@8",
            source: "Block 27 · W1 D1",
            performedOn: date(1)
        ),
        entry(
            fullName: "Bench Press",
            baseName: "Bench Press",
            resultText: "190x5@8",
            source: "Block 27 · W2 D1",
            performedOn: date(0)
        )
    ]

    let presentation = ExerciseHistorySheetPresentation(anchorBaseName: "Bench Press", entries: entries)

    let rowCount = presentation.blocks.reduce(0) { $0 + $1.rows.count }
    #expect(rowCount == 2)
    #expect(presentation.isEmpty == false)
}

@Test func mayStillDeepenTracksWhetherTheMovementIsBelowTheEntryCap() {
    // Below the cap the affordance is allowed; at or above it the Movement is "full" and the
    // fill-in-progress affordance is scoped out even while a fill runs for other Movements.
    let belowCap = (0..<3).map { index in
        entry(
            fullName: "Bench Press",
            baseName: "Bench Press",
            resultText: "\(180 + index)x5@8",
            source: "Block 27 · W\(index + 1) D1",
            performedOn: date(index)
        )
    }
    #expect(ExerciseHistorySheetPresentation(anchorBaseName: "Bench Press", entries: belowCap).mayStillDeepen)

    let atCap = (0..<5).map { index in
        entry(
            fullName: "Bench Press",
            baseName: "Bench Press",
            resultText: "\(180 + index)x5@8",
            source: "Block 27 · W\(index + 1) D1",
            performedOn: date(index)
        )
    }
    #expect(ExerciseHistorySheetPresentation(anchorBaseName: "Bench Press", entries: atCap).mayStillDeepen == false)

    // No entries yet — history can certainly still deepen.
    #expect(ExerciseHistorySheetPresentation(anchorBaseName: "Bench Press", entries: []).mayStillDeepen)
}

// MARK: - Volume points

@Test func volumePointSumsWeightTimesRepsAcrossAnEntrysStructuredSets() {
    let presentation = ExerciseHistorySheetPresentation(
        anchorBaseName: "Bench Press",
        entries: [
            entry(
                fullName: "Bench Press",
                baseName: "Bench Press",
                resultText: "27.5x10@8, 27.5x10@8, 27.5x9@9",
                source: "Block 27 · W1 D1",
                performedOn: date(1)
            )
        ]
    )

    let volume: Double = 27.5 * 10 + 27.5 * 10 + 27.5 * 9
    #expect(
        presentation.volumePoints == [
            .init(blockHeader: "BLOCK 27", gutter: "W1 D1", volume: volume, approximate: false)
        ]
    )
}

@Test func volumePointExcludesSkippedSetsAndStaysExact() {
    // A Skipped Set contributes no volume and does not make the total approximate.
    let presentation = ExerciseHistorySheetPresentation(
        anchorBaseName: "Bench Press",
        entries: [
            entry(
                fullName: "Bench Press",
                baseName: "Bench Press",
                resultText: "185x5@8, skip, 185x4@9",
                source: "Block 27 · W1 D1",
                performedOn: date(1)
            )
        ]
    )

    let volume: Double = 185 * 5 + 185 * 4
    #expect(
        presentation.volumePoints == [
            .init(blockHeader: "BLOCK 27", gutter: "W1 D1", volume: volume, approximate: false)
        ]
    )
}

@Test func volumePointFlagsLegacyRawnessAsApproximate() {
    // A mixed entry with un-parseable rawness plots its best-effort total as a hollow `≈` dot.
    let presentation = ExerciseHistorySheetPresentation(
        anchorBaseName: "Squat",
        entries: [
            entry(
                fullName: "Squat",
                baseName: "Squat",
                resultText: "185x5@7, amrap",
                source: "Block 27 · W1 D1",
                performedOn: date(1)
            )
        ]
    )

    let volume: Double = 185 * 5
    #expect(
        presentation.volumePoints == [
            .init(blockHeader: "BLOCK 27", gutter: "W1 D1", volume: volume, approximate: true)
        ]
    )
}

@Test func volumePointOmittedWhenNothingParsesIntoAChip() {
    // A fully Legacy Log with no parseable Set contributes no chart point — the total is unknown, not
    // zero, so it is left off the chart rather than plotted misleadingly.
    let presentation = ExerciseHistorySheetPresentation(
        anchorBaseName: "Squat",
        entries: [
            entry(
                fullName: "Squat",
                baseName: "Squat",
                resultText: "worked up to 315, felt easy",
                source: "Block 27 · W1 D1",
                performedOn: date(1)
            )
        ]
    )

    #expect(presentation.volumePoints.isEmpty)
}

@Test func volumePointsRunOldestToNewestCarryingBlockHeadersForTheSeam() {
    // The chart reads left→right oldest→newest (the reverse of the newest-first ledger), and each
    // point carries its Block header so the view can draw the dotted Block seam at the boundary.
    let entries = [
        entry(
            fullName: "Bench Press",
            baseName: "Bench Press",
            resultText: "180x5@8",
            source: "Block 26 · W2 D1",
            performedOn: date(30)
        ),
        entry(
            fullName: "Bench Press",
            baseName: "Bench Press",
            resultText: "185x5@8",
            source: "Block 27 · W1 D1",
            performedOn: date(10)
        ),
        entry(
            fullName: "Bench Press",
            baseName: "Bench Press",
            resultText: "190x5@8",
            source: "Block 27 · W2 D1",
            performedOn: date(3)
        )
    ]

    let presentation = ExerciseHistorySheetPresentation(anchorBaseName: "Bench Press", entries: entries)

    let volumes: [Double] = [180 * 5, 185 * 5, 190 * 5]
    #expect(presentation.volumePoints.map(\.gutter) == ["W2 D1", "W1 D1", "W2 D1"])
    #expect(presentation.volumePoints.map(\.blockHeader) == ["BLOCK 26", "BLOCK 27", "BLOCK 27"])
    #expect(presentation.volumePoints.map(\.volume) == volumes)
    // The dotted Block seam sits between the Block 26 point and the first Block 27 point.
    #expect(presentation.volumeBlockSeamIndices == [1])
}

@Test func volumeBlockSeamIndicesMarkEveryBlockBoundaryAndNothingWithin() {
    // Two entries in Block 26, then two in Block 27: the only boundary the chart seams is the
    // crossing at index 2; consecutive points inside a Block never seam.
    let entries = [
        entry(
            fullName: "Bench Press",
            baseName: "Bench Press",
            resultText: "180x5@8",
            source: "Block 26 · W1 D1",
            performedOn: date(40)
        ),
        entry(
            fullName: "Bench Press",
            baseName: "Bench Press",
            resultText: "182x5@8",
            source: "Block 26 · W2 D1",
            performedOn: date(30)
        ),
        entry(
            fullName: "Bench Press",
            baseName: "Bench Press",
            resultText: "185x5@8",
            source: "Block 27 · W1 D1",
            performedOn: date(20)
        ),
        entry(
            fullName: "Bench Press",
            baseName: "Bench Press",
            resultText: "190x5@8",
            source: "Block 27 · W2 D1",
            performedOn: date(10)
        )
    ]

    let presentation = ExerciseHistorySheetPresentation(anchorBaseName: "Bench Press", entries: entries)

    #expect(presentation.volumePoints.map(\.blockHeader) == ["BLOCK 26", "BLOCK 26", "BLOCK 27", "BLOCK 27"])
    #expect(presentation.volumeBlockSeamIndices == [2])
}

@Test func volumeBlockSeamIndicesAreEmptyWithoutTwoPointsOrABoundary() {
    // A single point cannot seam; a whole series inside one Block never seams either.
    let single = ExerciseHistorySheetPresentation(
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
    #expect(single.volumeBlockSeamIndices.isEmpty)

    let sameBlock = ExerciseHistorySheetPresentation(
        anchorBaseName: "Bench Press",
        entries: [
            entry(
                fullName: "Bench Press",
                baseName: "Bench Press",
                resultText: "185x5@8",
                source: "Block 27 · W1 D1",
                performedOn: date(10)
            ),
            entry(
                fullName: "Bench Press",
                baseName: "Bench Press",
                resultText: "190x5@8",
                source: "Block 27 · W2 D1",
                performedOn: date(3)
            )
        ]
    )
    #expect(sameBlock.volumePoints.count == 2)
    #expect(sameBlock.volumeBlockSeamIndices.isEmpty)
}
