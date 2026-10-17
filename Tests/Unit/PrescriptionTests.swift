import Testing

@testable import WorkoutTracker

@Test(
    "A Load cell reads as exactly one Prescribed Load",
    arguments: [
        ("BW", PrescribedLoad.bodyweight),
        (" bw ", .bodyweight),
        ("Drop 17.5%", .drop(percent: 17.5)),
        ("drop  10%", .drop(percent: 10)),
        ("Drop 10% from top set", .uninterpreted),
        ("Drop10%", .uninterpreted),
        ("RPE8", .rpe(.eight)),
        (" rpe 6.5 ", .rpe(.sixPointFive)),
        ("RPE 5.5", .uninterpreted),
        ("RPE 11", .uninterpreted),
        ("RPE", .uninterpreted),
        ("225", .uninterpreted),
        ("Start conservative", .uninterpreted),
        ("", .uninterpreted)
    ]
)
func aLoadCellReadsAsOnePrescribedLoad(cell: String, expected: PrescribedLoad) {
    #expect(PrescribedLoad(cell) == expected)
}

@Test func onlyAnRPETargetNamesAPrescribedRPE() {
    #expect(PrescribedLoad("RPE 7.5").rpeTarget == .sevenPointFive)
    #expect(PrescribedLoad("BW").rpeTarget == nil)
    #expect(PrescribedLoad("Drop 10%").rpeTarget == nil)
    #expect(PrescribedLoad("RPE 5.5").rpeTarget == nil)
}

@Test(
    "A Reps cell reads as a rep target or uninterpreted text",
    arguments: [
        ("5", PrescribedReps.target(5...5)),
        (" 5 ", .target(5...5)),
        ("8-10", .target(8...10)),
        ("7 - 8", .target(7...8)),
        ("7 – 8", .target(7...8)),
        ("5-5", .target(5...5)),
        ("13", .target(13...13)),
        ("12-8", .uninterpreted),
        ("AMRAP", .uninterpreted),
        ("5+", .uninterpreted),
        ("40 sec", .uninterpreted),
        ("-5", .uninterpreted),
        ("", .uninterpreted)
    ]
)
func aRepsCellReadsAsPrescribedReps(cell: String, expected: PrescribedReps) {
    #expect(PrescribedReps(cell) == expected)
}

@Test(
    "A %1RM cell reads as a percentage",
    arguments: [("75%", 75.0), ("75", 75), (" 72.5% ", 72.5)] as [(String, Double)]
)
func aPercentOneRMCellReadsAsAPercentage(cell: String, expected: Double) {
    #expect(Prescription(reps: "5", load: "RPE8", percentOneRM: cell).percentOneRM == expected)
}

@Test(arguments: [nil, "", "%", "seventy"] as [String?])
func aPercentOneRMCellThatIsNotANumberReadsAsNone(cell: String?) {
    #expect(Prescription(reps: "5", load: "RPE8", percentOneRM: cell).percentOneRM == nil)
}

@MainActor
@Test func aSetsPrescriptionReadsItsThreeCells() {
    let set = ExerciseSet(index: 0, prescribedReps: "8-10", prescribedLoad: "RPE 8", percentOneRM: "70%", state: .pending)

    #expect(set.prescription.reps == .target(8...10))
    #expect(set.prescription.load == .rpe(.eight))
    #expect(set.prescription.percentOneRM == 70)
}
