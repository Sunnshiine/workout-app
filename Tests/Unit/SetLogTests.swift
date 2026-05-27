import Testing

@testable import WorkoutTracker

@Test func setLogFormatsWeightedAndBodyweight() {
    let weighted = SetLog(weight: .pounds(185), reps: 7, rpe: 6)
    #expect(weighted.formatted == "185x7@6")

    let bw = SetLog(weight: .bodyweight, reps: 12, rpe: 7)
    #expect(bw.formatted == "BWx12@7")
}

@Test func weightDropsTrailingZero() {
    #expect(Weight.pounds(182.5).label == "182.5")
    #expect(Weight.pounds(185).label == "185")
}

@MainActor
@Test func setDisplayUsesLoggedSetLogWhenPresent() throws {
    let logged = ExerciseSet(index: 0, prescribedReps: "12", prescribedLoad: "RPE8", percentOneRM: nil, state: .logged)
    logged.setLog = SetLog(weight: .pounds(25), reps: 12, rpe: 7)

    #expect(logged.displayReps == "25x12@7")
    #expect(logged.displayLoad == nil)

    let pending = ExerciseSet(index: 1, prescribedReps: "10", prescribedLoad: "RPE9", percentOneRM: nil, state: .pending)
    #expect(pending.displayReps == "10")
    #expect(pending.displayLoad == "RPE9")
}
