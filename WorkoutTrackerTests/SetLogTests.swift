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
