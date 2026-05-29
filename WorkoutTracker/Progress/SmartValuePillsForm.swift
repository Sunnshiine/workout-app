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

    init(value: Int, prescribedRPE: Int?) {
        self.value = value
        isDimmed = value == 5
        showsPrescriptionBadge = value == prescribedRPE
    }
}

@MainActor
struct SmartValuePillsForm {
    var weightText: String
    var repsText: String
    var rpeText: String
    let prescribedRPE: Int?
    private let initialWeightText: String
    private let initialRepsText: String
    private let initialRPEText: String

    var weightDisplay: String {
        weightText.isEmpty ? "—" : weightText
    }

    var repsDisplay: String {
        repsText.isEmpty ? "—" : repsText
    }

    var rpeDisplay: String {
        rpeText.isEmpty ? "—" : rpeText
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
        guard let log = makeLog() else { return "Log" }
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
            repsText = set.prescribedReps.caseInsensitiveCompare("AMRAP") == .orderedSame ? "" : set.prescribedReps
            rpeText = ""
        }
        initialWeightText = weightText
        initialRepsText = repsText
        initialRPEText = rpeText
    }

    mutating func adjustWeight(by increment: Double) {
        let currentWeight = Double(weightText) ?? 0
        weightText = (currentWeight + increment).weightLabel
    }

    func makeLog() -> SetLog? {
        SetLog(formatted: "\(weightText)x\(repsText)@\(rpeText)")
    }

    mutating func cancel() {
        weightText = initialWeightText
        repsText = initialRepsText
        rpeText = initialRPEText
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
