import Foundation

/// What the Lock Screen card offers for the Set it shows.
enum LoggablePressContent: Equatable, Sendable {
    /// One tap on an RPE Chip logs `weight` for `reps` at that RPE. `setIdentity` is a
    /// `LoggableSetIdentity.storageValue`, which the press hands back.
    case ready(weight: String, reps: Int, rpeChoices: [String], prescribedRPE: String?, setIdentity: String)
    /// No RPE Chips, only the mic and the app.
    case needsApp
}

extension LoggablePressContent {
    /// `session` is the Session the Lock Screen follows, which an Open Exercise's Set is not in.
    @MainActor
    init(
        for position: SessionSetPosition,
        following session: Session,
        shownBy focus: ActiveSetFocusManager,
        history: LastPerformedLookupSnapshot
    ) {
        let set = position.set
        let draft = SpokenSetContext(for: set, shownBy: focus, history: history).draft
        guard position.exercise.session === session, !set.isTimedSet, let identity = LoggableSetIdentity(position, showing: draft) else {
            self = .needsApp
            return
        }
        let center = draft.rpe ?? position.exercise.lastPerformedRPE(in: history) ?? RPEScalePresentation.defaultCenter
        let rpeChoices = RPE.chips(around: center)
        self = .ready(
            weight: identity.weight.label,
            reps: identity.reps,
            rpeChoices: rpeChoices.map(\.label),
            prescribedRPE: set.prescription.load.rpeTarget?.label,
            setIdentity: identity.storageValue
        )
    }
}

extension ExerciseSet {
    @MainActor
    fileprivate var isTimedSet: Bool {
        guard case .timed = prescription.reps else { return false }
        return true
    }
}

extension Exercise {
    /// The index tracks the Session in progress, and every rest follows one of its Sets, so without
    /// this the card would read today's Sets back as last time.
    @MainActor
    private func pastSessions(in history: LastPerformedLookupSnapshot) -> LastPerformedLookupSnapshot {
        session?.placement.coordinate.map(history.excluding(session:)) ?? history
    }

    @MainActor
    fileprivate func lastPerformedRPE(in history: LastPerformedLookupSnapshot) -> RPE? {
        pastSessions(in: history).lookup(for: exerciseName)?.occurrence.setLogs?.last?.rpe
    }

    /// The Exercise's Last Performed on the Lock Screen card's one line, longest first; the card draws
    /// the first that fits. Empty when it has none. A long Legacy Log must not take the Live
    /// Activity's 4 KB.
    @MainActor
    func lastPerformedLines(in history: LastPerformedLookupSnapshot) -> [String] {
        let presentation = LastPerformedCardPresentation(exercise: self, lookup: pastSessions(in: history))
        return (presentation?.lines ?? []).map { String($0.prefix(Self.lastPerformedLineLimit)) }
    }

    private static let lastPerformedLineLimit = 120
}

extension LastPerformedCardPresentation {
    private static let longestCut = 3

    /// `Block 26 · W4 D3 — 245×5 @6, 255×5 @7`, naming a differently spelled match as the card does. The
    /// Session Address gives way first, then the name, then Set Logs from the end, each whole: half a
    /// number reads as another number.
    fileprivate var lines: [String] {
        let named = matchedName.map { "\(resultText) as “\($0)”" } ?? resultText
        let setLogs = resultText.components(separatedBy: ", ")
        let kept = (1...Self.longestCut).reversed().filter { $0 < setLogs.count }
        return ["\(sourceText) — \(named)", named] + (matchedName == nil ? [] : [resultText])
            + kept.map { (setLogs.prefix($0) + ["…"]).joined(separator: ", ") }
    }
}

extension RPE {
    private static let chipCount = 5

    /// The RPE Chips: consecutive points around `center`, held inside the Table at its ends.
    static func chips(around center: RPE) -> [RPE] {
        let points = RPE.allCases
        let middle = points.firstIndex(of: center) ?? 0
        let first = Swift.min(Swift.max(middle - chipCount / 2, 0), points.count - chipCount)
        return Array(points[first..<first + chipCount])
    }
}

/// Which Set an RPE Chip logs and what the card showed for it, so a press finds the Set again after
/// a reload and writes the values the athlete read.
struct LoggableSetIdentity: Equatable, Sendable {
    let session: SessionCoordinate
    let setID: ActiveSetID
    let weight: Weight
    let reps: Int

    func setLog(at rpe: RPE) -> SetLog {
        SetLog(weight: weight, reps: reps, rpe: rpe)
    }

    var storageValue: String {
        [session.storageValue, "\(setID.exerciseOrder)", "\(setID.setIndex)", weight.label, "\(reps)"]
            .joined(separator: Self.separator)
    }

    init(session: SessionCoordinate, setID: ActiveSetID, weight: Weight, reps: Int) {
        self.session = session
        self.setID = setID
        self.weight = weight
        self.reps = reps
    }

    init?(storageValue: String) {
        let fields = storageValue.components(separatedBy: Self.separator)
        guard fields.count == 5,
            let session = SessionCoordinate(storageValue: fields[0]),
            let setID = Self.setID(exerciseOrder: fields[1], setIndex: fields[2]),
            let weight = Weight(text: fields[3]),
            let reps = Int(fields[4])
        else { return nil }
        self.init(session: session, setID: setID, weight: weight, reps: reps)
    }

    private static func setID(exerciseOrder: String, setIndex: String) -> ActiveSetID? {
        guard let exerciseOrder = Int(exerciseOrder), let setIndex = Int(setIndex) else { return nil }
        return ActiveSetID(exerciseOrder: exerciseOrder, setIndex: setIndex)
    }

    /// Nil unless the draft holds what a Set Log needs ahead of the athlete's RPE.
    @MainActor
    fileprivate init?(_ position: SessionSetPosition, showing draft: SetLogDraft) {
        guard let session = position.exercise.session?.placement.coordinate, let weight = draft.weight, let reps = draft.reps else {
            return nil
        }
        self.init(session: session, setID: position.setID, weight: weight, reps: reps)
    }

    /// A Sheet tab's name holds no line break.
    private static let separator = "\n"
}
