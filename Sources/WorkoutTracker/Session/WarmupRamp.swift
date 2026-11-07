import Foundation

/// One weight and rep count on a Warm-up Ramp. Never a Set: it is not logged, not counted, and never
/// written to the Sheet.
struct WarmupStep: Equatable, Sendable {
    let load: PlateLoad
    let reps: Int
}

enum WarmupRamp {
    /// One row per jump from the empty Bar. The sixth jump lands on the Set itself, which is the
    /// coach's and not a Warm-up Step.
    private static let repsPerJump = [5, 5, 3, 2, 1]

    /// Take the Bar off the top, divide by 5, and add that per jump, each rounded down to what the
    /// inventory can load. A jump that rounds onto an earlier one, or onto the top, drops out, and the
    /// earlier step keeps its reps. Bodyweight and a top the Bar cannot make have no ramp.
    static func make(top: Weight, inventory: PlateInventory) -> [WarmupStep] {
        guard case .pounds(let pounds) = top, let topLoad = PlateLoad(weighing: pounds, on: inventory) else { return [] }
        let bar = inventory.bar.quarterPounds
        let climb = Int((pounds * 4).rounded(.down)) - bar
        var steps: [WarmupStep] = []
        for (jump, reps) in repsPerJump.enumerated() {
            let asked = Double(bar + climb * jump / repsPerJump.count) / 4
            guard let load = PlateLoad(weighing: asked, on: inventory), load.reachable < topLoad.reachable,
                load.reachable != steps.last?.load.reachable
            else { continue }
            steps.append(WarmupStep(load: load, reps: reps))
        }
        return steps
    }
}

/// What a Set gives a Warm-up Ramp to walk up to.
enum WarmupTop: Equatable, Sendable {
    /// The weight the Active Set Card pre-fills: the Set's own Set Log, otherwise its Load Suggestion.
    case weight(Double)
    /// No weight to start from: the Prescribed Load is not one and there is no history, or the
    /// pre-fill is past anything a Bar holds. The athlete picks.
    case athletePicks
    case bodyweight
    case timedSet
}

@MainActor
extension WarmupTop {
    init(for set: ExerciseSet, history: LastPerformedLookupSnapshot) {
        if case .timedSet = set.timedEffort {
            self = .timedSet
            return
        }
        let suggestion = LoadSuggestionEngine.suggest(for: set, history: history)
        switch SetLogDraft(prefilling: set, suggestion: suggestion).weight {
        case .bodyweight: self = .bodyweight
        case .pounds(let pounds) where pounds <= PlateLoad.heaviestPounds: self = .weight(pounds)
        case .pounds, nil: self = .athletePicks
        }
    }
}
