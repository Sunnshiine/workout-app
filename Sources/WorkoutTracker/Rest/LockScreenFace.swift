import Foundation

/// Which Card Face the Lock Screen card shows of the Set it is on. The card keeps no state of its
/// own, so each of its controls names the face it turns to and the app draws it.
enum LockScreenFace: Equatable, Sendable {
    /// The countdown, the Cadence, and the Set's numbers.
    case rest
    /// The Coach Note where the numbers were.
    case coachNote
    case reps
    /// The RPE Chips for the Reps the athlete tapped, which each chip carries to its log.
    case rpe(reps: Int)

    var choosesTheSetLog: Bool {
        switch self {
        case .reps, .rpe: true
        case .rest, .coachNote: false
        }
    }
}

/// One of the three numbers the card's rest face shows: the weight the Set's card holds, then the
/// coach's Reps and RPE.
struct LockScreenStat: Equatable, Sendable {
    /// The value's unit, `lbs`, which the card draws over it in capitals. Empty over a value that names
    /// itself, as `BW` does.
    let label: String
    /// `267.5`, `1,002.5`, `AMRAP`, or a dash where the Set has none.
    let value: String
    /// As VoiceOver reads the pair: `267.5 pounds`, `No RPE`.
    let spoken: String
    /// True where the Set has no such value, which draws its dash muted.
    let isMissing: Bool

    static let missingValue = "—"
}

extension LockScreenStat {
    fileprivate init(label: String, value: String, spoken: String) {
        self.init(label: label, value: value, spoken: spoken, isMissing: false)
    }

    fileprivate init(missing label: String, spoken: String) {
        self.init(label: label, value: Self.missingValue, spoken: spoken, isMissing: true)
    }

    static func row(weight: Weight?, prescription: Prescription, repsCell: String) -> [LockScreenStat] {
        [Self.weight(weight), reps(prescription.reps, cell: repsCell), rpe(prescription.load.rpeTarget)]
    }

    private static func weight(_ weight: Weight?) -> LockScreenStat {
        switch weight {
        case .pounds(let pounds):
            LockScreenStat(label: "lbs", value: grouped(Weight.pounds(pounds).label), spoken: "\(Weight.pounds(pounds).label) pounds")
        case .bodyweight:
            LockScreenStat(label: "", value: Weight.bodyweight.label, spoken: "Bodyweight")
        case nil:
            LockScreenStat(missing: "lbs", spoken: "No weight")
        }
    }

    private static func reps(_ reps: PrescribedReps, cell: String) -> LockScreenStat {
        switch reps {
        case .target(let target): counted(target)
        case .timed(let duration): timed(duration)
        case .uninterpreted: written(cell)
        }
    }

    private static func counted(_ target: ClosedRange<Int>) -> LockScreenStat {
        let (low, high) = (target.lowerBound, target.upperBound)
        guard low != high else {
            return LockScreenStat(label: "reps", value: "\(low)", spoken: low == 1 ? "1 Rep" : "\(low) Reps")
        }
        return LockScreenStat(label: "reps", value: "\(low)-\(high)", spoken: "\(low) to \(high) Reps")
    }

    /// Reps the app does not read as a count, such as `AMRAP`, in the coach's words.
    private static func written(_ cell: String) -> LockScreenStat {
        let text = cell.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        guard !text.isEmpty else { return LockScreenStat(missing: "reps", spoken: "No Reps") }
        return LockScreenStat(label: "reps", value: text, spoken: "\(text) Reps")
    }

    /// A Timed Set counts time where another Set counts Reps: `40` over `sec`, `25` or `1:30` over `min`.
    private static func timed(_ duration: EffortDuration) -> LockScreenStat {
        let seconds = duration.seconds
        if seconds < 60 {
            return LockScreenStat(label: "sec", value: "\(seconds)", spoken: seconds == 1 ? "1 second" : "\(seconds) seconds")
        }
        let minutes = seconds / 60
        let spokenMinutes = minutes == 1 ? "1 minute" : "\(minutes) minutes"
        if seconds.isMultiple(of: 60) {
            return LockScreenStat(label: "min", value: "\(minutes)", spoken: spokenMinutes)
        }
        let rest = seconds % 60
        return LockScreenStat(
            label: "min",
            value: "\(minutes):" + (rest < 10 ? "0\(rest)" : "\(rest)"),
            spoken: "\(spokenMinutes) \(rest) seconds"
        )
    }

    private static func rpe(_ rpe: RPE?) -> LockScreenStat {
        guard let rpe else { return LockScreenStat(missing: "RPE", spoken: "No RPE") }
        return LockScreenStat(label: "RPE", value: rpe.label, spoken: "RPE \(rpe.label)")
    }

    /// `1002.5` as `1,002.5`. The Set Log keeps the bare digits; only the card groups them.
    private static func grouped(_ number: String) -> String {
        let parts = number.split(separator: ".", maxSplits: 1, omittingEmptySubsequences: false)
        var whole = String(parts[0])
        var index = whole.count - 3
        while index > 0 {
            whole.insert(",", at: whole.index(whole.startIndex, offsetBy: index))
            index -= 3
        }
        return parts.count > 1 ? "\(whole).\(parts[1])" : whole
    }
}
