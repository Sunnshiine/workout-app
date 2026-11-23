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
    /// A Timed Set's duration, written as `EffortDuration` reads one: `40 sec`, `25 min`, `0:45`.
    case timed(EffortDuration)
    /// `AMRAP`, `5+`, a pyramid such as `1-2-3-3-2-1`, and any other text.
    case uninterpreted

    init(_ cell: String) {
        let trimmed = Self.repsAfterASetCount(cell.trimmingCharacters(in: .whitespacesAndNewlines))
        guard let match = trimmed.wholeMatch(of: /(\d+)(?:\s*[-–]\s*(\d+))?/), let low = Int(match.1) else {
            self = EffortDuration(trimmed).map(Self.timed) ?? .uninterpreted
            return
        }
        let high = match.2.flatMap { Int($0) } ?? low
        self = low <= high ? .target(low...high) : .uninterpreted
    }

    /// `2 x 8` prescribes the reps after its Set count.
    private static func repsAfterASetCount(_ cell: String) -> String {
        guard cell.contains(where: { "xX×".contains($0) }) else { return cell }
        return cell.wholeMatch(of: /\d+\s*[xX×]\s*(.+)/).map { String($0.1) } ?? cell
    }

    var target: ClosedRange<Int>? {
        guard case .target(let reps) = self else { return nil }
        return reps
    }
}

/// The coach's Load cell. A cell is exactly one of these, so no two readers can take the same
/// text for different instructions.
enum PrescribedLoad: Equatable, Sendable {
    /// `BW` in any casing.
    case bodyweight
    /// `Drop 17.5%`, `20% drop`, `-20%`, `Drop 10% from top set`: that share off the top Set's
    /// weight.
    case drop(percent: Double)
    /// `RPE8`, `rpe 6.5`: one of the ten RPE points.
    case rpe(RPE)
    /// `Start conservative`, `RPE 5.5`, and any other text.
    case uninterpreted

    init(_ cell: String) {
        let trimmed = cell.trimmingCharacters(in: .whitespacesAndNewlines)
        if Weight(text: trimmed) == .bodyweight {
            self = .bodyweight
        } else if let percent = Self.dropPercent(trimmed) {
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

    var isDrop: Bool {
        guard case .drop = self else { return false }
        return true
    }

    private static func dropPercent(_ text: String) -> Double? {
        for wording in dropWordings {
            guard let match = text.wholeMatch(of: wording.pattern), let number = Double(match.1) else { continue }
            let off = wording.shareOff(number)
            return off > 0 && off < 100 ? off : nil
        }
        return nil
    }
}

/// Each wording a coach writes a Drop in, and the share off the top Set it names.
private nonisolated(unsafe) let dropWordings: [(pattern: Regex<(Substring, Substring)>, shareOff: @Sendable (Double) -> Double)] = [
    (/drop\s*(\d+(?:\.\d+)?)\s*%(?:\s+(?:from|off)\s+(?:the\s+)?top(?:\s+set)?)?/.ignoresCase(), { $0 }),
    (/-?\s*(\d+(?:\.\d+)?)\s*%\s+drop/.ignoresCase(), { $0 }),
    (/-\s*(\d+(?:\.\d+)?)\s*%/, { $0 })
]

extension ExerciseSet {
    var prescription: Prescription {
        Prescription(reps: prescribedReps, load: prescribedLoad, percentOneRM: percentOneRM)
    }
}
