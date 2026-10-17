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

    func overridden(by other: SetLogDraft) -> SetLogDraft {
        SetLogDraft(weight: other.weight ?? weight, reps: other.reps ?? reps, rpe: other.rpe ?? rpe)
    }

    var missingFields: Set<Field> {
        Set([weight == nil ? .weight : nil, reps == nil ? .reps : nil, rpe == nil ? Field.rpe : nil].compactMap { $0 })
    }
}

extension SetLogDraft {
    /// What the Active Set Card pre-fills before the athlete touches it: a Logged Set's own Set
    /// Log, otherwise the Load Suggestion's weight and the reps and RPE the prescription names when
    /// it names one value.
    @MainActor
    init(prefilling set: ExerciseSet, suggestion: LoadSuggestion) {
        if let setLog = set.setLog {
            self.init(weight: setLog.weight, reps: setLog.reps, rpe: setLog.rpe)
        } else {
            self.init(weight: suggestion.weight, reps: Int(set.prescribedReps), rpe: RPE(prescribedLoad: set.prescribedLoad))
        }
    }
}
