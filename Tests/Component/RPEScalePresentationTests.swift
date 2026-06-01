import Testing

@testable import WorkoutTracker

@MainActor
@Test func rpeScaleListsWholeAndHalfStepsFromFiveToTenAndDimsTheLowEdge() {
    let scale = RPEScalePresentation(prescribedRPE: nil, selection: "")

    #expect(scale.chips.map(\.value) == [5, 6, 6.5, 7, 7.5, 8, 8.5, 9, 9.5, 10])
    #expect(scale.chips.map(\.label) == ["5", "6", "6.5", "7", "7.5", "8", "8.5", "9", "9.5", "10"])
    #expect(scale.chips.filter(\.isDimmed).map(\.value) == [5])
}

@MainActor
@Test func rpeScaleMarksPrescribedChipAndSelectedChipIndependently() {
    let scale = RPEScalePresentation(prescribedRPE: 8, selection: "7.5")

    #expect(scale.chips.filter(\.isPrescribed).map(\.value) == [8])
    #expect(scale.chips.filter(\.isSelected).map(\.value) == [7.5])
}

@MainActor
@Test func rpeScaleSelectionMatchesWholeStepWrittenWithoutDecimal() {
    let scale = RPEScalePresentation(prescribedRPE: nil, selection: "8")

    #expect(scale.chips.filter(\.isSelected).map(\.value) == [8])
}

@MainActor
@Test func rpeScaleScrollTargetPrefersSelectionThenPrescribedThenDefault() {
    #expect(RPEScalePresentation(prescribedRPE: 8, selection: "9.5").scrollTarget == 9.5)
    #expect(RPEScalePresentation(prescribedRPE: 8, selection: "").scrollTarget == 8)
    #expect(RPEScalePresentation(prescribedRPE: nil, selection: "").scrollTarget == RPEScalePresentation.defaultScrollTarget)
}
