import Foundation
import Testing

@testable import WorkoutTracker

// MARK: - Volume points

@Test func volumePointSumsWeightTimesRepsAcrossAnEntrysStructuredSets() {
    let presentation = ExerciseHistorySheetPresentation(
        anchor: "Bench Press",
        entries: [
            entry(
                name: "Bench Press",
                resultText: "27.5x10@8, 27.5x10@8, 27.5x9@9",
                source: "Block 27 · W1 D1",
                performedOn: date(1)
            )
        ]
    )

    let volume: Double = 27.5 * 10 + 27.5 * 10 + 27.5 * 9
    #expect(
        presentation.volumePoints == [
            .init(blockHeader: "Block 27", gutter: "W1 D1", volume: volume, approximate: false)
        ]
    )
}

@Test func volumePointExcludesSkippedSetsAndStaysExact() {
    // A Skipped Set contributes no volume and does not make the total approximate.
    let presentation = ExerciseHistorySheetPresentation(
        anchor: "Bench Press",
        entries: [
            entry(
                name: "Bench Press",
                resultText: "185x5@8, skip, 185x4@9",
                source: "Block 27 · W1 D1",
                performedOn: date(1)
            )
        ]
    )

    let volume: Double = 185 * 5 + 185 * 4
    #expect(
        presentation.volumePoints == [
            .init(blockHeader: "Block 27", gutter: "W1 D1", volume: volume, approximate: false)
        ]
    )
}

@Test func volumePointFlagsLegacyRawnessAsApproximate() {
    // A mixed entry with un-parseable rawness plots its best-effort total as a hollow `≈` dot.
    let presentation = ExerciseHistorySheetPresentation(
        anchor: "Squat",
        entries: [
            entry(
                name: "Squat",
                resultText: "185x5@7, amrap",
                source: "Block 27 · W1 D1",
                performedOn: date(1)
            )
        ]
    )

    let volume: Double = 185 * 5
    #expect(
        presentation.volumePoints == [
            .init(blockHeader: "Block 27", gutter: "W1 D1", volume: volume, approximate: true)
        ]
    )
}

@Test func volumePointOmittedWhenNothingParsesIntoAChip() {
    // A fully Legacy Log with no parseable Set contributes no chart point — the total is unknown, not
    // zero, so it is left off the chart rather than plotted misleadingly.
    let presentation = ExerciseHistorySheetPresentation(
        anchor: "Squat",
        entries: [
            entry(
                name: "Squat",
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
            name: "Bench Press",
            resultText: "180x5@8",
            source: "Block 26 · W2 D1",
            performedOn: date(30)
        ),
        entry(
            name: "Bench Press",
            resultText: "185x5@8",
            source: "Block 27 · W1 D1",
            performedOn: date(10)
        ),
        entry(
            name: "Bench Press",
            resultText: "190x5@8",
            source: "Block 27 · W2 D1",
            performedOn: date(3)
        )
    ]

    let presentation = ExerciseHistorySheetPresentation(anchor: "Bench Press", entries: entries)

    let volumes: [Double] = [180 * 5, 185 * 5, 190 * 5]
    #expect(presentation.volumePoints.map(\.gutter) == ["W2 D1", "W1 D1", "W2 D1"])
    #expect(presentation.volumePoints.map(\.blockHeader) == ["Block 26", "Block 27", "Block 27"])
    #expect(presentation.volumePoints.map(\.volume) == volumes)
    // The dotted Block seam sits between the Block 26 point and the first Block 27 point.
    #expect(presentation.volumeBlockSeamIndices == [1])
}

@Test func volumeBlockSeamIndicesMarkEveryBlockBoundaryAndNothingWithin() {
    // Two entries in Block 26, then two in Block 27: the only boundary the chart seams is the
    // crossing at index 2; consecutive points inside a Block never seam.
    let entries = [
        entry(
            name: "Bench Press",
            resultText: "180x5@8",
            source: "Block 26 · W1 D1",
            performedOn: date(40)
        ),
        entry(
            name: "Bench Press",
            resultText: "182x5@8",
            source: "Block 26 · W2 D1",
            performedOn: date(30)
        ),
        entry(
            name: "Bench Press",
            resultText: "185x5@8",
            source: "Block 27 · W1 D1",
            performedOn: date(20)
        ),
        entry(
            name: "Bench Press",
            resultText: "190x5@8",
            source: "Block 27 · W2 D1",
            performedOn: date(10)
        )
    ]

    let presentation = ExerciseHistorySheetPresentation(anchor: "Bench Press", entries: entries)

    #expect(presentation.volumePoints.map(\.blockHeader) == ["Block 26", "Block 26", "Block 27", "Block 27"])
    #expect(presentation.volumeBlockSeamIndices == [2])
}

@Test func volumeBlockSeamIndicesAreEmptyWithoutTwoPointsOrABoundary() {
    // A single point cannot seam; a whole series inside one Block never seams either.
    let single = ExerciseHistorySheetPresentation(
        anchor: "Bench Press",
        entries: [
            entry(
                name: "Bench Press",
                resultText: "185x5@8",
                source: "Block 27 · W1 D1",
                performedOn: date(1)
            )
        ]
    )
    #expect(single.volumeBlockSeamIndices.isEmpty)

    let sameBlock = ExerciseHistorySheetPresentation(
        anchor: "Bench Press",
        entries: [
            entry(
                name: "Bench Press",
                resultText: "185x5@8",
                source: "Block 27 · W1 D1",
                performedOn: date(10)
            ),
            entry(
                name: "Bench Press",
                resultText: "190x5@8",
                source: "Block 27 · W2 D1",
                performedOn: date(3)
            )
        ]
    )
    #expect(sameBlock.volumePoints.count == 2)
    #expect(sameBlock.volumeBlockSeamIndices.isEmpty)
}

// MARK: - Volume height fractions (the chart's value→height mapping)

@Test func volumeHeightFractionsNormalizeTheSeriesMinToFloorAndMaxToCeiling() {
    // Volumes 180×5=900 (Block 26), 185×5=925, 190×5=950 (Block 27) run oldest→newest.
    let entries = [
        entry(
            name: "Bench Press",
            resultText: "180x5@8",
            source: "Block 26 · W2 D1",
            performedOn: date(30)
        ),
        entry(
            name: "Bench Press",
            resultText: "185x5@8",
            source: "Block 27 · W1 D1",
            performedOn: date(10)
        ),
        entry(
            name: "Bench Press",
            resultText: "190x5@8",
            source: "Block 27 · W2 D1",
            performedOn: date(3)
        )
    ]

    let presentation = ExerciseHistorySheetPresentation(anchor: "Bench Press", entries: entries)

    // min (900) → 0, max (950) → 1, the middle (925) exactly halfway; aligned with volumePoints order.
    #expect(presentation.volumeHeightFractions == [0, 0.5, 1])
    #expect(presentation.volumeHeightFractions.count == presentation.volumePoints.count)
}

@Test func volumeHeightFractionsCenterAFlatSeriesSoItReadsCalm() {
    // Two identical totals: a zero span must map to the vertical centre, never divide by zero.
    let entries = [
        entry(
            name: "Bench Press",
            resultText: "185x5@8",
            source: "Block 27 · W1 D1",
            performedOn: date(10)
        ),
        entry(
            name: "Bench Press",
            resultText: "185x5@8",
            source: "Block 27 · W2 D1",
            performedOn: date(3)
        )
    ]

    let presentation = ExerciseHistorySheetPresentation(anchor: "Bench Press", entries: entries)

    #expect(presentation.volumeHeightFractions == [0.5, 0.5])
}

@Test func volumeHeightFractionsCenterASinglePointAndAreEmptyWithNoPoints() {
    let single = ExerciseHistorySheetPresentation(
        anchor: "Bench Press",
        entries: [
            entry(
                name: "Bench Press",
                resultText: "185x5@8",
                source: "Block 27 · W1 D1",
                performedOn: date(1)
            )
        ]
    )
    #expect(single.volumeHeightFractions == [0.5])

    // A fully-unparseable entry plots no point, so there are no fractions to map.
    let none = ExerciseHistorySheetPresentation(
        anchor: "Squat",
        entries: [
            entry(
                name: "Squat",
                resultText: "worked up to 315",
                source: "Block 27 · W1 D1",
                performedOn: date(1)
            )
        ]
    )
    #expect(none.volumeHeightFractions.isEmpty)
}
