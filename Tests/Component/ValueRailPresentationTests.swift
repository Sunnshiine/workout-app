import Testing

@testable import WorkoutTracker

@MainActor
@Test func repsRailListsOneToOneHundred() {
    let rail = RepsScalePresentation(prescribedReps: PrescribedReps("5"), selection: "5")

    #expect(rail.chips.count == 100)
    #expect(rail.chips.first?.label == "1")
    #expect(rail.chips.last?.label == "100")
}

@MainActor
@Test func repsRailMarksSelectedAndPrescribedIndependently() {
    let rail = RepsScalePresentation(prescribedReps: PrescribedReps("5"), selection: "8")

    #expect(rail.chips.filter(\.isSelected).map(\.label) == ["8"])
    #expect(rail.chips.filter(\.isPrescribed).map(\.label) == ["5"])
}

@MainActor
@Test func repsRailCentersOnSelectionThenPrescribedThenDefault() {
    #expect(RepsScalePresentation(prescribedReps: PrescribedReps("5"), selection: "5").selectedIndex == 4)
    #expect(RepsScalePresentation(prescribedReps: PrescribedReps("12"), selection: "").selectedIndex == 11)
    #expect(RepsScalePresentation(prescribedReps: PrescribedReps("AMRAP"), selection: "").selectedIndex == 4)
}

@MainActor
@Test func repsRailLeavesNothingSelectedWhenSelectionIsEmpty() {
    let rail = RepsScalePresentation(prescribedReps: PrescribedReps("5"), selection: "")

    #expect(rail.chips.filter(\.isSelected).isEmpty)
    #expect(rail.chips.filter(\.isPrescribed).map(\.label) == ["5"])
    // Still centers on the prescription so the athlete taps near their target.
    #expect(rail.selectedIndex == 4)
}

@MainActor
@Test func repsRailTicksEveryValueOfARangeAndCentersOnItsLowEnd() {
    let rail = RepsScalePresentation(prescribedReps: PrescribedReps("11-12"), selection: "")

    #expect(rail.chips.filter(\.isPrescribed).map(\.label) == ["11", "12"])
    #expect(rail.selectedIndex == 10)
}

@MainActor
@Test func repsRailReadsARangeWrittenWithAnEnDashAndSpaces() {
    let rail = RepsScalePresentation(prescribedReps: PrescribedReps("7 – 8"), selection: "")

    #expect(rail.chips.filter(\.isPrescribed).map(\.label) == ["7", "8"])
}

@MainActor
@Test func repsRailTicksOnlyItsOwnValuesForARangeReachingPastThem() {
    let rail = RepsScalePresentation(prescribedReps: PrescribedReps("1-9223372036854775807"), selection: "")

    #expect(rail.chips.filter(\.isPrescribed).count == 100)
    #expect(rail.selectedIndex == 0)
}

@MainActor
@Test(arguments: ["AMRAP", "12-8", "5+"])
func repsRailTicksNothingForRepsTextItDoesNotInterpret(prescribedReps: String) {
    let rail = RepsScalePresentation(prescribedReps: PrescribedReps(prescribedReps), selection: "")

    #expect(rail.chips.filter(\.isPrescribed).isEmpty)
    #expect(rail.selectedIndex == 4)
}

@MainActor
@Test func rpeRailExposesTheSharedChipShapeCenteredOnItsTarget() {
    let rail = RPEScalePresentation(prescribedRPE: .eight, selection: "8.5")

    #expect(rail.chips.count == 10)
    #expect(rail.chips.filter(\.isSelected).map(\.label) == ["8.5"])
    #expect(rail.chips.filter(\.isPrescribed).map(\.label) == ["8"])
    // 8.5 is the seventh value [5, 6, 6.5, 7, 7.5, 8, 8.5, …] → index 6.
    #expect(rail.selectedIndex == 6)
}

@Test func theRailSpeaksItsSelectionOrThatNoneIsSet() {
    #expect(RPEScalePresentation(prescribedRPE: .seven, selection: "8.5").chips.spokenSelection == "8.5")
    // "RPE 5.5" is text the app does not interpret, so the rail centres on 8 with nothing selected.
    #expect(RPEScalePresentation(prescribedRPE: nil, selection: "").chips.spokenSelection == "Not set")
    #expect(RepsScalePresentation(prescribedReps: PrescribedReps("5"), selection: "").chips.spokenSelection == "Not set")
}
