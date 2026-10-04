import Foundation

/// The outcome of a Load Suggestion. Only `estimate` carries a Load Basis, so the coach's arithmetic
/// cannot claim one and an estimate cannot lack one.
enum LoadSuggestion: Equatable, Sendable {
    /// A Drop from the previous Set, or a %1RM of the Training Max.
    case weight(Double)
    case bodyweight
    /// Read through the RPE Table from the athlete's own Set Log.
    case estimate(Double, basis: LoadBasis)
    case noSuggestion
}

/// CONTEXT.md *Load Basis*. Only a usable Set Log builds one: pounds above zero, with reps and RPE
/// the RPE Table covers.
struct LoadBasis: Equatable, Sendable {
    enum Origin: Equatable, Sendable {
        /// A Set of the same Exercise earlier in the Set's own Session, by 0-based Set index.
        case today(setIndex: Int)
        /// A Set Log of the Exercise's most recent Exercise History entry outside the Set's own Session.
        case history(SessionCoordinate)
    }

    let setLog: SetLog
    let origin: Origin
    private let pounds: Double
    private let point: RPEChartPoint

    init?(setLog: SetLog, origin: Origin) {
        guard case .pounds(let pounds) = setLog.weight, pounds > 0,
            let point = RPEChartPoint(reps: setLog.reps, rpe: setLog.rpe)
        else { return nil }
        self.setLog = setLog
        self.origin = origin
        self.pounds = pounds
        self.point = point
    }

    /// CONTEXT.md *Estimated Single*: a step inside the estimate, never shown, stored, or encoded.
    fileprivate var estimatedSingle: Double { pounds / point.share }
}

enum LoadSuggestionEngine {
    private static let plateIncrement = 2.5

    /// CONTEXT.md *Load Suggestion*, the coach's explicit numbers first. The first arm that answers
    /// wins, so `BW` pre-fills BW even when a `percentOneRM` value is also present.
    private static let precedence: [@Sendable (LoadSuggestionInputs) -> LoadSuggestion?] = [
        bodyweight, drop, percentOneRM, rpeTable
    ]

    /// The question the Set card and the `workout` CLI ask. A Set that holds a structured Set Log
    /// shows that log, so it consults nothing.
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

    /// Never reads the Training Max: the estimate is the athlete's own Set Log, not the coach's number.
    private static func rpeTable(_ inputs: LoadSuggestionInputs) -> LoadSuggestion? {
        guard
            let target = RPEChartPoint(prescribedReps: inputs.prescribedReps, prescribedLoad: inputs.prescribedLoad),
            let basis = todayBasis(inputs) ?? inputs.lastPerformed.flatMap(historyBasis)
        else { return nil }
        return .estimate(roundToNearestPlateIncrement(basis.estimatedSingle * target.share), basis: basis)
    }

    /// The nearest earlier Set by index whose Set Log is usable. A nearer unusable Set (BW, past the
    /// table) is passed over, as Drop passes over BW, so "the previous Set" means one thing.
    private static func todayBasis(_ inputs: LoadSuggestionInputs) -> LoadBasis? {
        inputs.earlierSets
            .sorted { $0.index > $1.index }
            .lazy
            .compactMap { LoadBasis(setLog: $0.setLog, origin: .today(setIndex: $0.index)) }
            .first
    }

    /// The entry's highest-RPE usable Set Log, a tie going to the later Set. RPE is rated most
    /// accurately near failure, and on a top Set with back-offs this picks the top Set rather than
    /// a fatigued back-off. A Legacy Log is never a basis: by the Header Notes Role it always holds a
    /// token that is neither a Set Log nor `skip`, so every token must be one of those two.
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

    /// The nearest earlier Set's logged weight in pounds. A bodyweight Set carries no weight, so the
    /// scan passes over it to the next one back.
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
