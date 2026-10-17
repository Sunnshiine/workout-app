import Foundation

/// What the coach asked of one Set, read once from its Reps, Load and %1RM cells. It is derived
/// each time and never stored: `ExerciseSet` keeps the cells as the Sheet holds them (ADR-0001),
/// and anything that displays them reads those raw cells, not this reading.
struct Prescription: Equatable, Sendable {
    let reps: PrescribedReps
    let load: PrescribedLoad
    /// The %1RM cell as a percentage, so `75%` and `75` are both 75. Nil when the cell is blank
    /// or holds anything but a finite number.
    let percentOneRM: Double?

    init(reps: String, load: String, percentOneRM: String?) {
        self.reps = PrescribedReps(reps)
        self.load = PrescribedLoad(load)
        self.percentOneRM = percentOneRM.flatMap(Self.percent)
    }

    private static func percent(from cell: String) -> Double? {
        let trimmed = cell.trimmingCharacters(in: .whitespacesAndNewlines)
        let numberText = trimmed.hasSuffix("%") ? String(trimmed.dropLast()) : trimmed
        guard let percent = Double(numberText), percent.isFinite else { return nil }
        return percent
    }
}

/// The coach's Reps cell, read by ADR-0018's rule.
enum PrescribedReps: Equatable, Sendable {
    /// One whole number, as `5...5`, or a range whose ends both resolve, low end first:
    /// `8-10`, `7 - 8`, `7 – 8`.
    case target(ClosedRange<Int>)
    /// `AMRAP`, `5+`, a timed Set, and any other text.
    case uninterpreted

    init(_ cell: String) {
        let trimmed = cell.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let match = trimmed.wholeMatch(of: /(\d+)(?:\s*[-–]\s*(\d+))?/), let low = Int(match.1) else {
            self = .uninterpreted
            return
        }
        let high = match.2.flatMap { Int($0) } ?? low
        self = low <= high ? .target(low...high) : .uninterpreted
    }
}

/// The coach's Load cell. A cell is exactly one of these, so no two readers can take the same
/// text for different instructions.
enum PrescribedLoad: Equatable, Sendable {
    /// `BW` in any casing.
    case bodyweight
    /// `Drop 17.5%`: that share off the previous Set's weight.
    case drop(percent: Double)
    /// `RPE8`, `rpe 6.5`: one of the ten RPE points.
    case rpe(RPE)
    /// `Start conservative`, `RPE 5.5`, `Drop 10% from top set`, and any other text.
    case uninterpreted

    init(_ cell: String) {
        let trimmed = cell.trimmingCharacters(in: .whitespacesAndNewlines)
        if Weight(text: trimmed) == .bodyweight {
            self = .bodyweight
        } else if let match = trimmed.wholeMatch(of: /Drop\s+([0-9]+(?:\.[0-9]+)?)%/.ignoresCase()), let percent = Double(match.1) {
            self = .drop(percent: percent)
        } else if let match = trimmed.wholeMatch(of: /RPE\s*(.+)/.ignoresCase()), let rpe = RPE(text: String(match.1)) {
            self = .rpe(rpe)
        } else {
            self = .uninterpreted
        }
    }

    var rpeTarget: RPE? {
        guard case .rpe(let rpe) = self else { return nil }
        return rpe
    }
}

extension ExerciseSet {
    var prescription: Prescription {
        Prescription(reps: prescribedReps, load: prescribedLoad, percentOneRM: percentOneRM)
    }
}
