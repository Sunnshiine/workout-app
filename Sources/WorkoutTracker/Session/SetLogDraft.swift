import Foundation

/// A Set Log's weight, reps, and RPE with any of them missing: what the Active Set Card holds
/// until the athlete completes it.
struct SetLogDraft: Equatable, Sendable {
    enum Field: String, CaseIterable, Sendable {
        case weight
        case reps
        case rpe
    }

    let weight: Weight?
    let reps: Int?
    let rpe: RPE?

    var setLog: SetLog? {
        guard let weight, let reps, let rpe else { return nil }
        return SetLog(weight: weight, reps: reps, rpe: rpe)
    }

    var missingFields: Set<Field> {
        Set([weight == nil ? .weight : nil, reps == nil ? .reps : nil, rpe == nil ? Field.rpe : nil].compactMap { $0 })
    }
}

extension SetLogDraft {
    init(_ setLog: SetLog) {
        self.init(weight: setLog.weight, reps: setLog.reps, rpe: setLog.rpe)
    }

    /// What the Active Set Card pre-fills before the athlete touches it: a Logged Set's own Set
    /// Log, otherwise the Load Suggestion's weight, the prescribed reps (a range's low end, ADR-0018),
    /// and the prescription's RPE target.
    @MainActor
    init(prefilling set: ExerciseSet, suggestion: LoadSuggestion) {
        if let setLog = set.setLog {
            self.init(setLog)
        } else {
            let prescription = set.prescription
            self.init(
                weight: suggestion.weight,
                reps: prescription.reps.target?.lowerBound,
                rpe: prescription.load.rpeTarget
            )
        }
    }
}
