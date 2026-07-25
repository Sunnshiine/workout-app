import CoreGraphics
import Testing

@testable import WorkoutTracker

@MainActor
@Test func repsRailListsOneToOneHundred() {
    let rail = RepsScalePresentation(prescribedReps: "5", selection: "5")

    #expect(rail.chips.count == 100)
    #expect(rail.chips.first?.label == "1")
    #expect(rail.chips.last?.label == "100")
    #expect(rail.chips.map(\.value).first == 1)
}

@MainActor
@Test func repsRailMarksSelectedAndPrescribedIndependently() {
    let rail = RepsScalePresentation(prescribedReps: "5", selection: "8")

    #expect(rail.chips.filter(\.isSelected).map(\.label) == ["8"])
    #expect(rail.chips.filter(\.isPrescribed).map(\.label) == ["5"])
}

@MainActor
@Test func repsRailCentersOnSelectionThenPrescribedThenDefault() {
    // Reps=5 sits at index 4 — the offscreen-scroll bug the ledger flagged; the
    // presentation resolves the centered index deterministically, no runtime scroll.
    #expect(RepsScalePresentation(prescribedReps: "5", selection: "5").selectedIndex == 4)
    #expect(RepsScalePresentation(prescribedReps: "12", selection: "").selectedIndex == 11)
    #expect(RepsScalePresentation(prescribedReps: "AMRAP", selection: "").selectedIndex == RepsScalePresentation.defaultSelection - 1)
}

@MainActor
@Test func repsRailLeavesNothingSelectedWhenSelectionIsEmpty() {
    let rail = RepsScalePresentation(prescribedReps: "5", selection: "")

    #expect(rail.chips.filter(\.isSelected).isEmpty)
    #expect(rail.chips.filter(\.isPrescribed).map(\.label) == ["5"])
    // Still centers on the prescription so the athlete taps near their target.
    #expect(rail.selectedIndex == 4)
}

@MainActor
@Test func rpeRailExposesTheSharedChipShapeCenteredOnItsTarget() {
    let rail = RPEScalePresentation(prescribedRPE: 8, selection: "8.5")

    #expect(rail.railChips.count == rail.chips.count)
    #expect(rail.railChips.filter(\.isSelected).map(\.label) == ["8.5"])
    #expect(rail.railChips.filter(\.isPrescribed).map(\.label) == ["8"])
    // 8.5 is the seventh value [5, 6, 6.5, 7, 7.5, 8, 8.5, …] → index 6.
    #expect(rail.selectedIndex == 6)
}

@Test func valueRailContentOffsetCentersTheSelectedCell() {
    // A 150pt track, 48pt cells, no spacing: the first cell's centre is 24pt in,
    // so centring it shifts the strip right by 150/2 − 24 = 51pt.
    #expect(ValueRailLayout.contentOffset(trackWidth: 150, cellWidth: 48, spacing: 0, selectedIndex: 0) == 51)
    // Index 4 (reps=5) sits 4 strides in: centre = 48*4 + 24 = 216, offset = 75 − 216 = −141.
    #expect(ValueRailLayout.contentOffset(trackWidth: 150, cellWidth: 48, spacing: 0, selectedIndex: 4) == -141)
    // Spacing widens the stride: stride 44, centre = 44*2 + 20 = 108, offset = 50 − 108 = −58.
    #expect(ValueRailLayout.contentOffset(trackWidth: 100, cellWidth: 40, spacing: 4, selectedIndex: 2) == -58)
}

@Test func valueRailDragMovesOneDetentPerCellStride() {
    // Dragging left (negative translation) advances to higher values; each 48pt
    // of travel is one detent, rounding at the half-stride boundary.
    #expect(ValueRailLayout.draggedIndex(anchorIndex: 4, translation: -48, cellWidth: 48, spacing: 0, count: 100) == 5)
    #expect(ValueRailLayout.draggedIndex(anchorIndex: 4, translation: -120, cellWidth: 48, spacing: 0, count: 100) == 7)
    #expect(ValueRailLayout.draggedIndex(anchorIndex: 4, translation: 96, cellWidth: 48, spacing: 0, count: 100) == 2)
    #expect(ValueRailLayout.draggedIndex(anchorIndex: 4, translation: -20, cellWidth: 48, spacing: 0, count: 100) == 4)
}

@Test func valueRailDragClampsToTheRailsEnds() {
    #expect(ValueRailLayout.draggedIndex(anchorIndex: 1, translation: 480, cellWidth: 48, spacing: 0, count: 10) == 0)
    #expect(ValueRailLayout.draggedIndex(anchorIndex: 8, translation: -480, cellWidth: 48, spacing: 0, count: 10) == 9)
}
