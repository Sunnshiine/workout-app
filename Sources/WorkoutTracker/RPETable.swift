import Foundation

struct RPEChartPoint: Equatable, Sendable {
    private static let reps = 1...12

    private let halfReps: Int
    private let rpe: RPE

    init?(reps: Int, rpe: RPE) {
        self.init(halfReps: reps * 2, rpe: rpe)
    }

    init?(prescribedReps: String, prescribedLoad: String) {
        guard let rpe = RPE(prescribedLoad: prescribedLoad), let reps = Self.repRange(prescribedReps),
            reps.clamped(to: Self.reps) == reps
        else { return nil }
        self.init(halfReps: reps.lowerBound + reps.upperBound, rpe: rpe)
    }

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

    var share: Double {
        RPETable.share(effectiveHalfReps: halfReps + Int((10 - rpe.rawValue) * 2))
    }
}

private enum RPETable {
    private static let percentByEffectiveHalfStep: [Double] = [
        100, 97.8, 95.5, 93.9, 92.2, 90.7, 89.2, 87.8, 86.3, 85.0, 83.7, 82.4, 81.1, 79.9, 78.6, 77.4,
        76.2, 75.1, 73.9, 72.3, 70.7, 69.4, 68.0, 66.7, 65.3, 64.0, 62.6, 61.3, 59.9, 58.6, 57.4
    ]

    static func share(effectiveHalfReps: Int) -> Double {
        percentByEffectiveHalfStep[effectiveHalfReps - 2] / 100
    }
}
