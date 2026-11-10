import Foundation

/// What the Lock Screen card offers for the Set it shows.
enum LoggablePressContent: Equatable, Sendable {
    /// Reps Chips, then RPE Chips. The RPE tap logs the weight the stage holds at the Reps and the
    /// RPE the athlete tapped.
    case ready(LockScreenOffer)
    /// No chips, only the app.
    case needsApp
}

/// The chips one Set offers on the Lock Screen, and how far the athlete has got through them. No
/// value is chosen ahead of the athlete, because a Set Log's Reps and RPE are theirs to report.
struct LockScreenOffer: Equatable, Sendable {
    /// Every value a Reps Chip can log, as the card's Reps rail offers them.
    static let repsRange = 1...100
    private static let chipCount = 5

    let repChoices: [Int]
    /// The choices inside the Prescribed Reps, which carry the rail's tick.
    let prescribedReps: [Int]
    let rpeChoices: [String]
    /// The coach's RPE, which carries the tick. Nil unless the Load cell names one point.
    let prescribedRPE: String?
    /// A `LoggableSetIdentity.storageValue`, which each press hands back.
    let setIdentity: String
    /// The Reps the athlete tapped, which turn the row to RPE. Nil until they tap one.
    var chosenReps: Int?  // default: a fresh offer has no Reps tapped, so none is chosen ahead of the athlete

    /// Consecutive values around `center`, held inside `repsRange` at its ends.
    static func repChoices(around center: Int) -> [Int] {
        let first = min(max(center - chipCount / 2, repsRange.lowerBound), repsRange.upperBound - chipCount + 1)
        return Array(first..<first + chipCount)
    }
}

extension LoggablePressContent {
    /// `session` is the Session the Lock Screen follows, which an Open Exercise's Set is not in.
    /// `draft` is what the Set's card shows. The chips centre where the card's rails do.
    @MainActor
    init(
        for position: SessionSetPosition,
        following session: Session,
        showing draft: SetLogDraft,
        history: LastPerformedLookupSnapshot
    ) {
        guard position.exercise.session === session, !position.set.isTimedSet,
            let identity = LoggableSetIdentity(position, showing: draft)
        else {
            self = .needsApp
            return
        }
        self = .ready(LockScreenOffer(position, showing: draft, history: history, identity: identity))
    }
}

extension LockScreenOffer {
    /// True for a Reps Chip's value, or nil for the chip that turns the row back.
    static func admits(_ reps: Int?) -> Bool {
        reps.map(repsRange.contains) ?? true
    }

    @MainActor
    fileprivate init(
        _ position: SessionSetPosition,
        showing draft: SetLogDraft,
        history: LastPerformedLookupSnapshot,
        identity: LoggableSetIdentity
    ) {
        let prescription = position.set.prescription
        let repChoices = Self.repChoices(around: Self.repsCenter(showing: draft, prescribed: prescription.reps.target))
        self.init(
            repChoices: repChoices,
            prescribedReps: prescription.reps.target.map { reps in repChoices.filter(reps.contains) } ?? [],
            rpeChoices: RPE.chips(around: position.exercise.rpeCenter(showing: draft, history: history)).map(\.label),
            prescribedRPE: prescription.load.rpeTarget?.label,
            setIdentity: identity.storageValue
        )
    }

    private static func repsCenter(showing draft: SetLogDraft, prescribed: ClosedRange<Int>?) -> Int {
        draft.reps ?? prescribed?.lowerBound ?? RepsScalePresentation.defaultSelection
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
    private static let coachNoteLimit = 120

    /// The Coach Note as the Lock Screen card shows it: one line of words, cut so a long note cannot
    /// take the Live Activity's 4 KB. Nil with no words in the note.
    var lockScreenCoachNote: String? {
        let words = coachNote?.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        guard let words, !words.isEmpty else { return nil }
        return String(words.prefix(Self.coachNoteLimit))
    }

    /// Where the RPE rail centres: the card's RPE, else what the athlete last reported.
    @MainActor
    fileprivate func rpeCenter(showing draft: SetLogDraft, history: LastPerformedLookupSnapshot) -> RPE {
        draft.rpe ?? lastPerformedRPE(in: history) ?? RPEScalePresentation.defaultCenter
    }

    /// The index tracks the Session in progress, and every rest follows one of its Sets, so without
    /// this the chips would centre on today's Sets.
    @MainActor
    private func lastPerformedRPE(in history: LastPerformedLookupSnapshot) -> RPE? {
        let past = session?.placement.coordinate.map(history.excluding(session:)) ?? history
        return past.lookup(for: exerciseName)?.occurrence.setLogs?.last?.rpe
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

/// Which Set a chip logs and the weight the card showed for it, so a press finds the Set again after
/// a reload and writes the weight the athlete read. The Reps and the RPE come with the press.
struct LoggableSetIdentity: Equatable, Sendable {
    let session: SessionCoordinate
    let setID: ActiveSetID
    let weight: Weight

    func setLog(reps: Int, rpe: RPE) -> SetLog {
        SetLog(weight: weight, reps: reps, rpe: rpe)
    }

    var storageValue: String {
        [session.storageValue, "\(setID.exerciseOrder)", "\(setID.setIndex)", weight.label].joined(separator: Self.separator)
    }

    init(session: SessionCoordinate, setID: ActiveSetID, weight: Weight) {
        self.session = session
        self.setID = setID
        self.weight = weight
    }

    init?(storageValue: String) {
        let fields = storageValue.components(separatedBy: Self.separator)
        guard fields.count == 4,
            let session = SessionCoordinate(storageValue: fields[0]),
            let exerciseOrder = Int(fields[1]),
            let setIndex = Int(fields[2]),
            let weight = Weight(text: fields[3])
        else { return nil }
        self.init(session: session, setID: ActiveSetID(exerciseOrder: exerciseOrder, setIndex: setIndex), weight: weight)
    }

    /// Nil unless the card holds the weight, the one value the Lock Screen cannot choose.
    @MainActor
    fileprivate init?(_ position: SessionSetPosition, showing draft: SetLogDraft) {
        guard let session = position.exercise.session?.placement.coordinate, let weight = draft.weight else { return nil }
        self.init(session: session, setID: position.setID, weight: weight)
    }

    /// A Sheet tab's name holds no line break.
    private static let separator = "\n"
}

/// The Start the Lock Screen card offers in the mic's place for a Set with a timed effort. It opens
/// the app, where the stage's card counts the effort as a tap on its own control does, because a
/// countdown's voice and timer cannot be trusted with the app behind (ADR-0023).
struct LockScreenStart: Equatable, Sendable {
    let effort: TimedEffort
    let request: AppEntryRequest

    /// Nil for a Set with no timed effort, or one that is no longer Pending.
    @MainActor
    init?(_ position: SessionSetPosition) {
        guard position.set.isPending, let effort = position.set.timedEffort,
            let session = position.exercise.session?.placement.coordinate
        else { return nil }
        self.effort = effort
        request = .startTimedEffort(CountdownRun.Owner(session: session, set: position.setID))
    }
}

extension Weight {
    /// What the card prints after the weight: `185 lbs`, and `BW` alone.
    var unitLabel: String {
        switch self {
        case .bodyweight: ""
        case .pounds: "lbs"
        }
    }
}
