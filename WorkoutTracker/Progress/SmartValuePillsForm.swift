import Foundation

struct RPEGridPresentation: Equatable, Sendable {
    let rows: [[RPEGridValue]]
    let autoCloseDelay: Duration = .milliseconds(300)

    init(prescribedRPE: Int?) {
        rows = [
            [5, 6, 7].map { RPEGridValue(value: $0, prescribedRPE: prescribedRPE) },
            [8, 9, 10].map { RPEGridValue(value: $0, prescribedRPE: prescribedRPE) }
        ]
    }
}

struct RPEGridValue: Equatable, Hashable, Identifiable, Sendable {
    let value: Int
    let isDimmed: Bool
    let showsPrescriptionBadge: Bool

    var id: Int { value }
    var halfStepLabel: String? {
        guard (6...9).contains(value) else { return nil }
        return "\(value).5"
    }

    init(value: Int, prescribedRPE: Int?) {
        self.value = value
        isDimmed = value == 5
        showsPrescriptionBadge = value == prescribedRPE
    }
}

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

    var weightIncrementOptions: [Double] {
        guard let weight = Double(weightText), weight > Theme.weightIncrementThreshold else {
            return Theme.lightWeightIncrementOptions
        }
        return Theme.heavyWeightIncrementOptions
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
        return "Log \(log.weight.label)×\(log.reps)@\(Self.rpeLabel(log.rpe))"
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
            rpeText = ""
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

    private static func loadSuggestionPrescription(for set: ExerciseSet) -> String {
        if let percentOneRM = set.percentOneRM {
            return "\(percentOneRM)1RM"
        }
        return set.prescribedLoad
    }

    private static func initialWeightText(
        for set: ExerciseSet,
        previousSetWeight: Double?,
        trainingMax: Double?
    ) -> String {
        if set.prescribedLoad.caseInsensitiveCompare("BW") == .orderedSame {
            return "BW"
        }
        return
            LoadSuggestionEngine
            .suggest(
                prescribedLoad: loadSuggestionPrescription(for: set),
                previousSetWeight: previousSetWeight,
                trainingMax: trainingMax
            )?
            .weightLabel ?? ""
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
