import Testing

@testable import WorkoutTracker

@Test func repsPrescriptionRepeatsTheLastListedValueForEveryLaterSet() {
    let reps = PrescriptionValueList.reps("5, 5, 3")
    #expect(reps.value(at: 0) == "5")
    #expect(reps.value(at: 2) == "3")
    #expect(reps.value(at: 7) == "3")
}

@Test func aSinglePrescribedValueAppliesToEverySet() {
    let reps = PrescriptionValueList.reps("7 - 8")
    #expect(reps.value(at: 0) == "7 - 8")
    #expect(reps.value(at: 3) == "7 - 8")
}

@Test func anEmptyPrescriptionCellReadsEmptyForEverySet() {
    let reps = PrescriptionValueList.reps("")
    #expect(reps.value(at: 0) == "")
    #expect(reps.value(at: 4) == "")
}

@Test func loadPrescriptionCarriesTheLeadingUnitPrefixAcrossBareNumbers() {
    let load = PrescriptionValueList.load("BW+25, 35, RPE8")
    #expect(load.value(at: 0) == "BW+25")
    #expect(load.value(at: 1) == "BW+35")
    #expect(load.value(at: 2) == "RPE8")
    #expect(load.value(at: 9) == "RPE8")
}

@Test func loadPrescriptionLeavesAPurelyNumericListAlone() {
    let load = PrescriptionValueList.load("185, 195")
    #expect(load.value(at: 0) == "185")
    #expect(load.value(at: 1) == "195")
    #expect(load.value(at: 2) == "195")
}

// The parser reads the same rule through both templates: a Prescription Line of 3 Sets whose Reps
// cell lists only 2 values gives the third Set the last listed value.
@Test func aPrescriptionLineOfThreeSetsRepeatsItsLastListedRepsAndLoad() throws {
    let grid = gridFromA1(
        [
            "C12": "Day 1", "S12": "Day 2",
            "D14": "Sets", "F14": "Reps", "H14": "Load", "K14": "Notes",
            "C15": "Squat", "D15": "1", "F15": "5", "H15": "225",
            "D16": "3", "F16": "5, 3", "H16": "BW+25, 35",
            "C20": "Bench", "D20": "1"
        ],
        rows: 24,
        cols: 30
    )
    let section = locateWeekSections(in: grid)[0]

    let squat = parseDay(in: grid, section: section, headerIndex: 0)[0]

    #expect(squat.sets.map(\.prescribedReps) == ["5", "5", "3", "3"])
    #expect(squat.sets.map(\.prescribedLoad) == ["225", "BW+25", "BW+35", "BW+35"])
}
