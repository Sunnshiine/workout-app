import Testing

@testable import WorkoutTracker

@MainActor
@Test func rpeScaleListsWholeAndHalfStepsFromFiveToTen() {
    let scale = RPEScalePresentation(prescribedRPE: nil, selection: "")

    #expect(scale.chips.map(\.label) == ["5", "6", "6.5", "7", "7.5", "8", "8.5", "9", "9.5", "10"])
}

@MainActor
@Test func rpeScaleMarksPrescribedChipAndSelectedChipIndependently() {
    let scale = RPEScalePresentation(prescribedRPE: .eight, selection: "7.5")

    #expect(scale.chips.filter(\.isPrescribed).map(\.label) == ["8"])
    #expect(scale.chips.filter(\.isSelected).map(\.label) == ["7.5"])
}

@MainActor
@Test func rpeScaleMarksAHalfPointPrescriptionFromThePrescribedLoad() {
    let scale = RPEScalePresentation(prescribedRPE: RPE(prescribedLoad: "RPE 6.5"), selection: "")

    #expect(scale.chips.filter(\.isPrescribed).map(\.label) == ["6.5"])
}

@MainActor
@Test func rpeScaleSelectionMatchesWholeStepWrittenWithoutDecimal() {
    let scale = RPEScalePresentation(prescribedRPE: nil, selection: "8")

    #expect(scale.chips.filter(\.isSelected).map(\.label) == ["8"])
}

@MainActor
@Test func rpeScaleCentersOnSelectionThenPrescribedThenDefault() {
    #expect(RPEScalePresentation(prescribedRPE: .eight, selection: "9.5").selectedIndex == 8)
    #expect(RPEScalePresentation(prescribedRPE: .eight, selection: "").selectedIndex == 5)
    #expect(RPEScalePresentation(prescribedRPE: nil, selection: "").selectedIndex == 5)
}
