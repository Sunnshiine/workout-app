import Foundation

/// The RTS chart (ADR-0018).
enum RPETable {
    private static let supportedReps = 1...12
    private static let supportedRPE: ClosedRange<Double> = 6...10

    /// One RPE point below 10 is one rep in reserve, so every row of the RTS chart is a shift of this one
    /// curve over effective reps (reps plus reps in reserve). Each key is a whole or half number, which a
    /// Double holds exactly, so a key built by adding two of them always matches.
    private static let percentByEffectiveReps: [Double: Double] = [
        1: 100, 1.5: 97.8,
        2: 95.5, 2.5: 93.9,
        3: 92.2, 3.5: 90.7,
        4: 89.2, 4.5: 87.8,
        5: 86.3, 5.5: 85.0,
        6: 83.7, 6.5: 82.4,
        7: 81.1, 7.5: 79.9,
        8: 78.6, 8.5: 77.4,
        9: 76.2, 9.5: 75.1,
        10: 73.9, 10.5: 72.3,
        11: 70.7, 11.5: 69.4,
        12: 68.0, 12.5: 66.7,
        13: 65.3, 13.5: 64.0,
        14: 62.6, 14.5: 61.3,
        15: 59.9, 15.5: 58.6,
        16: 57.4
    ]

    static func share(reps: Int, rpe: RPE) -> Double? {
        share(reps: reps...reps, rpe: rpe)
    }

    static func share(reps: ClosedRange<Int>, rpe: RPE) -> Double? {
        guard supportedReps.contains(reps.lowerBound), supportedReps.contains(reps.upperBound),
            supportedRPE.contains(rpe.rawValue)
        else { return nil }
        let midpoint = Double(reps.lowerBound + reps.upperBound) / 2
        let repsInReserve = 10 - rpe.rawValue
        guard let percent = percentByEffectiveReps[midpoint + repsInReserve] else {
            preconditionFailure("A covered Set has \(midpoint + repsInReserve) effective reps, a key of the curve")
        }
        return percent / 100
    }
}
