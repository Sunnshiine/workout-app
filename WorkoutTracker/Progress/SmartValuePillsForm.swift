import Foundation

@MainActor
struct SmartValuePillsForm {
    enum Field: Hashable, Sendable {
        case weight
        case reps
        case rpe
    }

    var weightText: String
    var repsText: String
    var rpeText: String
    let prescribedRPE: Int?
    let repsPlaceholder: String?
    private var showsInvalidFields = false
    private let initialWeightText: String
    private let initialRepsText: String
    private let initialRPEText: String

    var weightDisplay: String {
        weightText.isEmpty ? "—" : weightText
    }

    var repsDisplay: String {
        repsText.isEmpty ? repsPlaceholder ?? "—" : repsText
    }

    var rpeDisplay: String {
        rpeText.isEmpty ? "—" : rpeText
    }

    var isRepsDisplayingPlaceholder: Bool {
        repsText.isEmpty && repsPlaceholder != nil
    }

    var invalidFields: Set<Field> {
        guard showsInvalidFields else { return [] }
        return currentInvalidFields
    }

    /// The single contextual step for the inline weight stepper: ±2.5 below the
    /// gym-friendly threshold, ±5 at or above it. The coarse step is retired —
    /// tap the weight to type a big jump.
    var fineWeightIncrement: Double {
        guard let weight = Double(weightText), weight > Theme.weightIncrementThreshold else {
            return Theme.lightWeightIncrementOptions.first ?? 2.5
        }
        return Theme.heavyWeightIncrementOptions.first ?? 5
    }

    /// Stepping only makes sense for a numeric weight — hidden for bodyweight and
    /// while the field is empty.
    var allowsWeightStepping: Bool {
        let trimmed = weightText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let weight = Double(trimmed) else { return false }
        return weight.isFinite
    }

    var canLog: Bool {
        makeLog() != nil
    }

    var hasChanges: Bool {
        weightText != initialWeightText || repsText != initialRepsText || rpeText != initialRPEText
    }

    var changedValidLog: SetLog? {
        guard hasChanges else { return nil }
        return makeLog()
    }

    var logButtonTitle: String {
        guard let log = makeLog() else { return incompleteLogButtonTitle }
        // The Log capsule previews the exact Set Log with the spaced typography of
        // pick input-block3-c ("Log 90 × 5 @8").
        return "Log \(log.weight.label) × \(log.reps) @\(Self.rpeLabel(log.rpe))"
    }

    init(set: ExerciseSet, previousSetWeight: Double?, trainingMax: Double?) {
        prescribedRPE = Self.prescribedRPE(from: set.prescribedLoad)
        if let setLog = set.setLog {
            weightText = setLog.weight.label
            repsText = String(setLog.reps)
            rpeText = Self.rpeLabel(setLog.rpe)
        } else {
            weightText = Self.initialWeightText(
                for: set,
                previousSetWeight: previousSetWeight,
                trainingMax: trainingMax
            )
            repsText = Self.initialRepsText(for: set.prescribedReps)
            rpeText = prescribedRPE.map(String.init) ?? ""
        }
        repsPlaceholder = repsText.isEmpty ? set.prescribedReps : nil
        initialWeightText = weightText
        initialRepsText = repsText
        initialRPEText = rpeText
    }

    mutating func adjustWeight(by increment: Double) {
        let currentWeight = Double(weightText) ?? 0
        weightText = (currentWeight + increment).weightLabel
    }

    enum WeightStep: Sendable {
        case up
        case down
    }

    /// Steps the weight by one `fineWeightIncrement` in `step`, clamped at a zero
    /// floor. Returns `true` when the step *hit the floor* — a decrement that would
    /// have gone negative, clamped to 0 — so the caller can answer with the dud
    /// rather than the detent tick. Landing exactly on 0 is a normal step, not a
    /// floor hit.
    @discardableResult
    mutating func stepWeight(_ step: WeightStep) -> Bool {
        let increment = fineWeightIncrement
        if step == .down, (Double(weightText) ?? 0) - increment < 0 {
            weightText = "0"
            return true
        }
        adjustWeight(by: step == .up ? increment : -increment)
        return false
    }

    func makeLog() -> SetLog? {
        guard
            let weight = validWeight,
            let reps = validReps,
            let rpe = validRPE
        else {
            return nil
        }
        return SetLog(weight: weight, reps: reps, rpe: rpe)
    }

    @discardableResult
    mutating func markInvalidFieldsForDisplay() -> Set<Field> {
        showsInvalidFields = true
        return invalidFields
    }

    mutating func submitLog() -> SetLog? {
        guard let log = makeLog() else {
            markInvalidFieldsForDisplay()
            return nil
        }
        return log
    }

    mutating func cancel() {
        weightText = initialWeightText
        repsText = initialRepsText
        rpeText = initialRPEText
        showsInvalidFields = false
    }

    private var currentInvalidFields: Set<Field> {
        var fields: Set<Field> = []
        if validWeight == nil {
            fields.insert(.weight)
        }
        if validReps == nil {
            fields.insert(.reps)
        }
        if validRPE == nil {
            fields.insert(.rpe)
        }
        return fields
    }

    private var incompleteLogButtonTitle: String {
        currentInvalidFields == [.rpe] ? "Choose RPE to log" : "Complete Set Log"
    }

    private var validWeight: Weight? {
        let trimmed = weightText.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.caseInsensitiveCompare("BW") == .orderedSame {
            return .bodyweight
        }
        guard let pounds = Double(trimmed), pounds.isFinite else {
            return nil
        }
        return .pounds(pounds)
    }

    private var validReps: Int? {
        let trimmed = repsText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let reps = Int(trimmed), String(reps) == trimmed else {
            return nil
        }
        return reps
    }

    private var validRPE: Double? {
        let trimmed = rpeText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let rpe = Double(trimmed), rpe >= 5, rpe <= 10 else {
            return nil
        }
        let doubled = rpe * 2
        guard doubled.rounded() == doubled else {
            return nil
        }
        return rpe
    }

    private static func initialWeightText(
        for set: ExerciseSet,
        previousSetWeight: Double?,
        trainingMax: Double?
    ) -> String {
        switch LoadSuggestionEngine.suggest(
            prescribedLoad: set.prescribedLoad,
            percentOneRM: set.percentOneRM,
            previousSetWeight: previousSetWeight,
            trainingMax: trainingMax
        ) {
        case .weight(let weight):
            return weight.weightLabel
        case .bodyweight:
            return "BW"
        case .noSuggestion:
            return ""
        }
    }

    private static func initialRepsText(for prescribedReps: String) -> String {
        Int(prescribedReps).map { String($0) } ?? ""
    }

    private static func rpeLabel(_ rpe: Double) -> String {
        rpe.rounded() == rpe ? String(Int(rpe)) : String(rpe)
    }

    private static func prescribedRPE(from prescribedLoad: String) -> Int? {
        let rpeText =
            prescribedLoad
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacing(/^RPE\s*/.ignoresCase(), with: "")
        return Int(rpeText)
    }
}

extension Double {
    fileprivate var weightLabel: String {
        rounded() == self ? String(Int(self)) : String(self)
    }
}
