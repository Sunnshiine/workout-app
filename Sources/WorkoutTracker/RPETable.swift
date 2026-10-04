import Foundation

/// One point of the RPE Table: a Set's reps and its RPE. Only a point the chart covers can be built
/// (1 to 12 reps, RPE 6 to 10), so `share` answers for every value.
struct RPEChartPoint: Equatable, Sendable {
    private static let reps = 1...12

    /// Reps in half steps, so a rep range's midpoint (`7 - 8` is 7.5 reps) lands on the chart's own
    /// grid and the table index stays an exact integer.
    private let halfReps: Int
    private let rpe: RPE

    init?(reps: Int, rpe: RPE) {
        self.init(halfReps: reps * 2, rpe: rpe)
    }

    /// The prescription's target: an RPE target (`RPE8`) for whole reps (`5`) or for the midpoint of
    /// a range (`8-10`, `7 - 8`, `8–10`) whose bounds both sit inside 1...12. AMRAP, `5+`, timed reps,
    /// and anything else have no point.
    init?(prescribedReps: String, prescribedLoad: String) {
        guard let rpe = RPE(prescribedLoad: prescribedLoad), let reps = Self.repRange(prescribedReps),
            reps.clamped(to: Self.reps) == reps
        else { return nil }
        self.init(halfReps: reps.lowerBound + reps.upperBound, rpe: rpe)
    }

    /// Whole reps are the one-rep range `5...5`, so a range's midpoint and a whole count are one sum.
    private static func repRange(_ prescribedReps: String) -> ClosedRange<Int>? {
        let text = prescribedReps.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let match = text.wholeMatch(of: /(\d+)(?:\s*[-–]\s*(\d+))?/), let low = Int(match.1) else { return nil }
        let high = match.2.flatMap { Int($0) } ?? low
        return low <= high ? low...high : nil
    }

    private init?(halfReps: Int, rpe: RPE) {
        guard (Self.reps.lowerBound * 2...Self.reps.upperBound * 2).contains(halfReps), rpe != .five
        else { return nil }
        self.halfReps = halfReps
        self.rpe = rpe
    }

    /// The share of the Estimated Single this point lifts: 0.786 for 5 @8.
    var share: Double {
        RPETable.share(effectiveHalfReps: halfReps + Int((10 - rpe.rawValue) * 2))
    }
}

/// CONTEXT.md *RPE Table*: the RTS chart as one curve over effective reps, reps + (10 - RPE), in
/// half steps from 1 to 16, each a percent of the Estimated Single.
private enum RPETable {
    private static let percentByEffectiveHalfStep: [Double] = [
        100, 97.8, 95.5, 93.9, 92.2, 90.7, 89.2, 87.8, 86.3, 85.0, 83.7, 82.4, 81.1, 79.9, 78.6, 77.4,
        76.2, 75.1, 73.9, 72.3, 70.7, 69.4, 68.0, 66.7, 65.3, 64.0, 62.6, 61.3, 59.9, 58.6, 57.4
    ]

    /// Every `RPEChartPoint` sits at 2...32 effective half reps, which is exactly this array.
    static func share(effectiveHalfReps: Int) -> Double {
        percentByEffectiveHalfStep[effectiveHalfReps - 2] / 100
    }
}
