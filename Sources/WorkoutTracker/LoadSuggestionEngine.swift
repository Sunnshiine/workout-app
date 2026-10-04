import Foundation

enum LoadSuggestion: Equatable, Sendable {
    case weight(Double)
    case bodyweight
    case estimate(Double, basis: LoadBasis)
    case noSuggestion
}

struct LoadBasis: Equatable, Sendable {
    enum Origin: Equatable, Sendable {
        case today(setIndex: Int)
        case history(SessionCoordinate)
    }

    let setLog: SetLog
    let origin: Origin
    private let pounds: Double
    private let point: RPETablePoint

    init?(setLog: SetLog, origin: Origin) {
        guard case .pounds(let pounds) = setLog.weight, pounds > 0,
            let point = RPETablePoint(reps: setLog.reps, rpe: setLog.rpe)
        else { return nil }
        self.setLog = setLog
        self.origin = origin
        self.pounds = pounds
        self.point = point
    }

    fileprivate var estimatedSingle: Double { pounds / point.share }
}

enum LoadSuggestionEngine {
    private static let plateIncrement = 2.5

    private static let precedence: [@Sendable (LoadSuggestionInputs) -> LoadSuggestion?] = [
        bodyweight, drop, percentOneRM, rpeTable
    ]

    @MainActor
    static func suggest(for set: ExerciseSet, history: LastPerformedLookupSnapshot) -> LoadSuggestion {
        guard set.setLog == nil else { return .noSuggestion }
        return suggest(LoadSuggestionInputs(set: set, history: history))
    }

    static func suggest(_ inputs: LoadSuggestionInputs) -> LoadSuggestion {
        precedence.lazy.compactMap { $0(inputs) }.first ?? .noSuggestion
    }

    private static func bodyweight(_ inputs: LoadSuggestionInputs) -> LoadSuggestion? {
        Weight(text: inputs.prescribedLoad.trimmingCharacters(in: .whitespacesAndNewlines)) == .bodyweight
            ? .bodyweight : nil
    }

    private static func drop(_ inputs: LoadSuggestionInputs) -> LoadSuggestion? {
        guard let dropPercent = dropPercent(from: inputs.prescribedLoad), let previous = previousSetPounds(inputs)
        else { return nil }
        return .weight(roundToNearestPlateIncrement(previous * (1 - dropPercent / 100)))
    }

    private static func percentOneRM(_ inputs: LoadSuggestionInputs) -> LoadSuggestion? {
        guard let percent = percentOneRMValue(from: inputs.percentOneRM), let trainingMax = inputs.trainingMax
        else { return nil }
        return .weight(roundToNearestPlateIncrement(trainingMax * percent / 100))
    }

    private static func rpeTable(_ inputs: LoadSuggestionInputs) -> LoadSuggestion? {
        guard
            let target = RPETablePoint(prescribedReps: inputs.prescribedReps, prescribedLoad: inputs.prescribedLoad),
            let basis = todayBasis(inputs) ?? inputs.lastPerformed.flatMap(historyBasis)
        else { return nil }
        return .estimate(roundToNearestPlateIncrement(basis.estimatedSingle * target.share), basis: basis)
    }

    private static func todayBasis(_ inputs: LoadSuggestionInputs) -> LoadBasis? {
        inputs.earlierSets
            .sorted { $0.index > $1.index }
            .lazy
            .compactMap { LoadBasis(setLog: $0.setLog, origin: .today(setIndex: $0.index)) }
            .first
    }

    private static func historyBasis(_ entry: LastPerformedOccurrence) -> LoadBasis? {
        let tokens = splitSheetNotesList(entry.resultText)
        guard tokens.allSatisfy(SetLogToken.isSetLogListValue),
            let session = SessionCoordinate(storageValue: entry.source)
        else { return nil }
        return
            tokens
            .compactMap { SetLog(formatted: $0).flatMap { LoadBasis(setLog: $0, origin: .history(session)) } }
            .enumerated()
            .max { ($0.element.setLog.rpe.rawValue, $0.offset) < ($1.element.setLog.rpe.rawValue, $1.offset) }?
            .element
    }

    private static func previousSetPounds(_ inputs: LoadSuggestionInputs) -> Double? {
        inputs.earlierSets
            .sorted { $0.index > $1.index }
            .lazy
            .compactMap { earlier -> Double? in
                guard case .pounds(let pounds) = earlier.setLog.weight else { return nil }
                return pounds
            }
            .first
    }

    private static func dropPercent(from prescribedLoad: String) -> Double? {
        let trimmed = prescribedLoad.trimmingCharacters(in: .whitespacesAndNewlines)
        guard
            trimmed.range(
                of: #"^Drop\s+([0-9]+(?:\.[0-9]+)?)%$"#,
                options: [.regularExpression, .caseInsensitive]
            ) != nil
        else {
            return nil
        }

        let percentText =
            trimmed
            .replacing(/^Drop\s+/.ignoresCase(), with: "")
            .replacing("%", with: "")
        return Double(percentText)
    }

    /// The `%1RM` prescription is stored structured as a `%`-suffixed string
    /// (e.g. `"75%"`, `ExerciseSet.percentOneRM`); parse it to a number once here.
    private static func percentOneRMValue(from percentOneRM: String?) -> Double? {
        guard let percentOneRM else { return nil }
        let trimmed = percentOneRM.trimmingCharacters(in: .whitespacesAndNewlines)
        let numberText = trimmed.hasSuffix("%") ? String(trimmed.dropLast()) : trimmed
        return Double(numberText)
    }

    private static func roundToNearestPlateIncrement(_ weight: Double) -> Double {
        (weight / plateIncrement).rounded() * plateIncrement
    }
}
