import Foundation

enum LoadSuggestion: Equatable, Sendable {
    case prescribedWeight(Double)
    case bodyweight
    case estimate(Double, basis: LoadBasis)
    case noSuggestion

    /// The weight the Active Set Card pre-fills from this suggestion.
    var weight: Weight? {
        switch self {
        case .prescribedWeight(let pounds), .estimate(let pounds, _): .pounds(pounds)
        case .bodyweight: .bodyweight
        case .noSuggestion: nil
        }
    }
}

struct LoadBasis: Equatable, Sendable {
    enum Origin: Equatable, Sendable {
        case today(setIndex: Int)
        case history(SessionCoordinate, matchedName: String?)
    }

    let setLog: SetLog
    let origin: Origin
    fileprivate let estimatedSingle: Double

    init?(setLog: SetLog, origin: Origin) {
        guard case .pounds(let pounds) = setLog.weight, pounds > 0,
            let share = RPETable.share(reps: setLog.reps, rpe: setLog.rpe)
        else { return nil }
        self.setLog = setLog
        self.origin = origin
        self.estimatedSingle = pounds / share
    }
}

enum LoadSuggestionEngine {
    private static let plateIncrement = 2.5

    @MainActor
    static func suggest(for set: ExerciseSet, history: LastPerformedLookupSnapshot) -> LoadSuggestion {
        guard set.setLog == nil else { return .noSuggestion }
        return suggest(LoadSuggestionInputs(set: set, history: history))
    }

    static func suggest(_ inputs: LoadSuggestionInputs) -> LoadSuggestion {
        bodyweight(inputs) ?? drop(inputs) ?? percentOneRM(inputs) ?? rpeTable(inputs) ?? .noSuggestion
    }

    private static func bodyweight(_ inputs: LoadSuggestionInputs) -> LoadSuggestion? {
        inputs.prescription.load == .bodyweight ? .bodyweight : nil
    }

    private static func drop(_ inputs: LoadSuggestionInputs) -> LoadSuggestion? {
        guard case .drop(let dropPercent) = inputs.prescription.load, let previous = previousSetPounds(inputs)
        else { return nil }
        return .prescribedWeight(roundToNearestPlateIncrement(previous * (1 - dropPercent / 100)))
    }

    private static func percentOneRM(_ inputs: LoadSuggestionInputs) -> LoadSuggestion? {
        guard let percent = inputs.prescription.percentOneRM, let trainingMax = inputs.trainingMax
        else { return nil }
        return .prescribedWeight(roundToNearestPlateIncrement(trainingMax * percent / 100))
    }

    private static func rpeTable(_ inputs: LoadSuggestionInputs) -> LoadSuggestion? {
        guard let reps = inputs.prescription.reps.target, let rpe = inputs.prescription.load.rpeTarget,
            let targetShare = RPETable.share(reps: reps, rpe: rpe),
            let basis = todayBasis(inputs) ?? inputs.lastPerformed.flatMap(historyBasis)
        else { return nil }
        return .estimate(roundToNearestPlateIncrement(basis.estimatedSingle * targetShare), basis: basis)
    }

    private static func todayBasis(_ inputs: LoadSuggestionInputs) -> LoadBasis? {
        inputs.earlierSets
            .lazy
            .compactMap { LoadBasis(setLog: $0.setLog, origin: .today(setIndex: $0.index)) }
            .first
    }

    private static func historyBasis(_ entry: LastPerformedLookupEntry) -> LoadBasis? {
        guard let setLogs = entry.occurrence.setLogs, let session = SessionCoordinate(storageValue: entry.occurrence.source)
        else { return nil }
        return
            setLogs
            .compactMap { LoadBasis(setLog: $0, origin: .history(session, matchedName: entry.matchedName)) }
            .enumerated()
            .max { ($0.element.setLog.rpe.rawValue, $0.offset) < ($1.element.setLog.rpe.rawValue, $1.offset) }?
            .element
    }

    private static func previousSetPounds(_ inputs: LoadSuggestionInputs) -> Double? {
        inputs.earlierSets
            .lazy
            .compactMap { earlier -> Double? in
                guard case .pounds(let pounds) = earlier.setLog.weight else { return nil }
                return pounds
            }
            .first
    }

    private static func roundToNearestPlateIncrement(_ weight: Double) -> Double {
        (weight / plateIncrement).rounded() * plateIncrement
    }
}
