import Foundation

/// A change to the Plan, as the CLI's flags spell it. Every field left nil keeps what the Meet has.
public struct MeetPlanEdit: Sendable {
    let date: String?
    let federation: String?
    let attempts: [String: String]
    let rackHeights: [String: String]
    let warmupRoomPlans: [String: String]
    let fillsWarmupRoomPlans: Bool
    let liftersInFlight: Int?
    let secondsPerAttempt: Int?

    /// `attempts` and `warmupRoomPlans` map a Main Lift's name to `180,190,197.5` and to
    /// `60x5@18,100x3@15`, where each step is kilograms, reps, and Attempts Out.
    public init(
        date: String?,
        federation: String?,
        attempts: [String: String],
        rackHeights: [String: String],
        warmupRoomPlans: [String: String],
        fillsWarmupRoomPlans: Bool,
        liftersInFlight: Int?,
        secondsPerAttempt: Int?
    ) {
        self.date = date
        self.federation = federation
        self.attempts = attempts
        self.rackHeights = rackHeights
        self.warmupRoomPlans = warmupRoomPlans
        self.fillsWarmupRoomPlans = fillsWarmupRoomPlans
        self.liftersInFlight = liftersInFlight
        self.secondsPerAttempt = secondsPerAttempt
    }

    var isEmpty: Bool {
        [date, federation].allSatisfy { $0 == nil } && [attempts, rackHeights, warmupRoomPlans].allSatisfy(\.isEmpty)
            && [liftersInFlight, secondsPerAttempt].allSatisfy { $0 == nil } && !fillsWarmupRoomPlans
    }

    /// Bad text is refused here, so the Meet only ever holds parsed values.
    func applied(to existing: Meet?) throws(ApplicationError) -> Meet {
        var meet = if let existing { existing } else { try newMeet() }
        try applyDay(to: &meet)
        for lift in MainLift.allCases {
            try applyLift(lift, to: &meet)
        }
        return meet
    }

    private func applyDay(to meet: inout Meet) throws(ApplicationError) {
        if let date { meet.date = try parseDate(date) }
        if let federation { meet.federation = try parseFederation(federation) }
        if let liftersInFlight { meet.liftersInFlight = try parsePositive(liftersInFlight, named: "--lifters") }
        if let secondsPerAttempt { meet.secondsPerAttempt = try parsePositive(secondsPerAttempt, named: "--seconds-per-attempt") }
    }

    private func applyLift(_ lift: MainLift, to meet: inout Meet) throws(ApplicationError) {
        if let text = attempts[lift.rawValue] {
            let weights = try parseAttempts(text)
            meet.editLift(lift) { $0.replaceUnmarkedAttempts(with: weights) }
        }
        if let text = rackHeights[lift.rawValue] {
            meet.editLift(lift) { $0.rackHeights = text.trimmed }
        }
        if let text = warmupRoomPlans[lift.rawValue] {
            let steps = try parseSteps(text)
            meet.editLift(lift) { $0.setWarmupRoomPlan(steps) }
        }
        if fillsWarmupRoomPlans {
            let barMultiple = meet.rules.barMultiple.value
            meet.editLift(lift) { $0.fillEmptyWarmupRoomPlan(barMultiple: barMultiple) }
        }
    }

    private func newMeet() throws(ApplicationError) -> Meet {
        guard let date, let federation else {
            throw ApplicationError.invalidMeetPlan("A new Meet needs --date and --federation.")
        }
        return Meet(date: try parseDate(date), federation: try parseFederation(federation))
    }

    private func parseDate(_ text: String) throws(ApplicationError) -> MeetDate {
        guard let date = MeetDate(text) else {
            throw ApplicationError.invalidMeetPlan("\"\(text)\" is not a calendar day. Use 2026-12-05.")
        }
        return date
    }

    private func parseFederation(_ text: String) throws(ApplicationError) -> Federation {
        guard let federation = Federation(rawValue: text.trimmed.lowercased()) else {
            let names = Federation.allCases.map(\.rawValue).joined(separator: ", ")
            throw ApplicationError.invalidMeetPlan("\"\(text)\" is not a federation. Use one of \(names).")
        }
        return federation
    }

    private func parsePositive(_ value: Int, named name: String) throws(ApplicationError) -> Int {
        guard value > 0 else { throw ApplicationError.invalidMeetPlan("\(name) must be above 0.") }
        return value
    }

    private func parseAttempts(_ text: String) throws(ApplicationError) -> [Kilograms] {
        let parts = text.split(separator: ",").map(String.init)
        guard parts.count <= AttemptOrdinal.allCases.count else {
            throw ApplicationError.invalidMeetPlan("\"\(text)\" names more than three Attempts.")
        }
        var weights: [Kilograms] = []
        for part in parts {
            guard let weight = Kilograms(parsing: part) else {
                throw ApplicationError.invalidMeetPlan("\"\(part)\" is not a weight in kilograms.")
            }
            weights.append(weight)
        }
        return weights
    }

    private func parseSteps(_ text: String) throws(ApplicationError) -> [WarmupRoomStep] {
        var steps: [WarmupRoomStep] = []
        for part in text.split(separator: ",") {
            guard let step = WarmupRoomStep(parsing: String(part)) else {
                throw ApplicationError.invalidMeetPlan("\"\(part)\" is not a warm-up step. Use 60x5@18: kilograms, reps, Attempts Out.")
            }
            steps.append(step)
        }
        return steps
    }
}

extension WarmupRoomStep {
    /// Reads `60x5@18`, whose Attempts Out must be above zero, because zero is the platform.
    fileprivate init?(parsing text: String) {
        guard
            let match = text.wholeMatch(of: /([^x@]+)x([1-9]\d{0,2})@([1-9]\d{0,2})/.asciiOnlyDigits()),
            let weight = Kilograms(parsing: String(match.1)), let reps = Int(match.2), let attemptsOut = Int(match.3)
        else { return nil }
        self.init(kilograms: weight, reps: reps, attemptsOut: attemptsOut)
    }
}

extension MeetLift {
    /// Marked Attempts happened, so an edit starts after them, and its first weights stand for them.
    fileprivate mutating func replaceUnmarkedAttempts(with weights: [Kilograms]) {
        clear(from: AttemptOrdinal(rawValue: markedCount) ?? .third)
        for (index, weight) in weights.enumerated() where index >= markedCount {
            enter(weight, at: AttemptOrdinal(rawValue: index) ?? .third)
        }
    }

    fileprivate mutating func fillEmptyWarmupRoomPlan(barMultiple: Kilograms) {
        guard warmupRoomPlan.isEmpty, let opener = attempts.first else { return }
        setWarmupRoomPlan(WarmupRoomPlanFill.evenSteps(toOpener: opener.kilograms, barMultiple: barMultiple))
    }
}

/// One gesture on the day, as `workout meet tick` takes it.
public enum MeetGesture: Sendable {
    case read
    case attemptsOut(Int)
    case good
    case noLift
    /// A weight the athlete's card carried, as text the facade parses.
    case submit(String)
    /// The window closed with no card, so the table's own entry goes in.
    case acceptTableEntry
    case pass
    case undo
    /// A change to the Attempt on deck, as text the facade parses.
    case change(String)
}

/// A Meet and the day's next move, as the CLI prints it.
public struct MeetReport: Encodable, Equatable, Sendable {
    public struct AttemptLine: Encodable, Equatable, Sendable {
        public let ordinal: String
        public let kilograms: Double
        public let pounds: Double
        public let state: String
        public let changesUsed: Int
    }

    public struct WarmupLine: Encodable, Equatable, Sendable {
        public let kilograms: Double
        public let reps: Int
        public let attemptsOut: Int
    }

    public struct LiftLine: Encodable, Equatable, Sendable {
        public let lift: String
        public let rackHeights: String
        public let attempts: [AttemptLine]
        public let warmupRoomPlan: [WarmupLine]
        public let bestGoodLift: Double?
    }

    public struct RuleLine: Encodable, Equatable, Sendable {
        public let text: String
        public let rule: String
    }

    /// What the athlete does next. `stage` says which of the optional fields are present:
    /// `warmUp`, `attempt`, `platform`, `window`, `finished`, or `noAttempts`.
    public struct Next: Encodable, Equatable, Sendable {
        public let stage: String
        public var lift: String?
        public var ordinal: String?
        public var kilograms: Double?
        public var reps: Int?
        public var attemptsOut: Int?
        public var attemptsUntil: Int?
        public var secondsUntil: Int?
        public var windowState: String?
        public var secondsLeft: Int?
        public var tableEntry: Double?
        public var changesLeft: Int?
        public var rule: String?

        init(stage: String) {
            self.stage = stage
        }
    }

    public let date: String
    public let daysUntil: Int
    public let federation: String
    public let rulebook: String
    public let rules: [RuleLine]
    public let liftersInFlight: Int
    public let secondsPerAttempt: Int
    public let lifts: [LiftLine]
    public let next: Next
    public let total: Double?
    public let canUndoMark: Bool
}

extension Kilograms {
    fileprivate var wire: Double { Double(hundredths) / 100 }
    fileprivate var poundsWire: Double { Double(poundsTenths) / 10 }
}

extension MeetReport {
    init(_ meet: Meet, canUndoMark: Bool, now: Date, calendar: Calendar) {
        date = meet.date.description
        daysUntil = meet.date.daysUntil(from: now, in: calendar)
        federation = meet.federation.rawValue
        rulebook = meet.rules.rulebook
        rules = meet.rules.lines.map { RuleLine(text: $0.text, rule: $0.rule) }
        liftersInFlight = meet.liftersInFlight
        secondsPerAttempt = meet.secondsPerAttempt
        lifts = meet.lifts.map(LiftLine.init)
        next = Next(meet.stage(at: now))
        total = meet.total?.wire
        self.canUndoMark = canUndoMark
    }
}

extension MeetReport.LiftLine {
    fileprivate init(_ lift: MeetLift) {
        self.lift = lift.lift.rawValue
        rackHeights = lift.rackHeights
        attempts = zip(AttemptOrdinal.allCases, lift.attempts).map { ordinal, attempt in
            MeetReport.AttemptLine(
                ordinal: ordinal.name.lowercased(),
                kilograms: attempt.kilograms.wire,
                pounds: attempt.kilograms.poundsWire,
                state: attempt.state.rawValue,
                changesUsed: attempt.changesUsed
            )
        }
        warmupRoomPlan = lift.warmupRoomPlan.map {
            MeetReport.WarmupLine(kilograms: $0.kilograms.wire, reps: $0.reps, attemptsOut: $0.attemptsOut)
        }
        bestGoodLift = lift.bestGoodLift?.wire
    }
}

extension MeetReport.Next {
    fileprivate init(_ stage: MeetStage) {
        switch stage {
        case .noAttempts:
            self.init(stage: "noAttempts")
        case .finished:
            self.init(stage: "finished")
        case .window(let window):
            self.init(window)
        case .onDeck(let deck):
            self.init(deck)
        }
    }

    private init(_ window: OpenAttemptWindow) {
        self.init(stage: "window")
        lift = window.lift.rawValue
        ordinal = window.ordinal.name.lowercased()
        kilograms = window.planned?.wire
        tableEntry = window.tableEntry.wire
        switch window.reading {
        case .open(let left):
            windowState = "open"
            secondsLeft = left
        case .closing(let left):
            windowState = "closing"
            secondsLeft = left
        case .expired:
            windowState = "expired"
            secondsLeft = 0
        }
    }

    private init(_ deck: AttemptOnDeck) {
        switch deck.cue {
        case .warmUp(let step, let attemptsUntil, let secondsUntil):
            self.init(stage: "warmUp")
            kilograms = step.kilograms.wire
            reps = step.reps
            self.attemptsUntil = attemptsUntil
            self.secondsUntil = secondsUntil
        case .attempt(let weight, _, let secondsUntil):
            self.init(stage: "attempt")
            kilograms = weight.wire
            self.secondsUntil = secondsUntil
        case .platform(let weight):
            self.init(stage: "platform")
            kilograms = weight.wire
        }
        lift = deck.lift.rawValue
        ordinal = deck.ordinal.name.lowercased()
        attemptsOut = deck.attemptsOut
        switch deck.allowance {
        case .changesLeft(let left, let rule):
            changesLeft = max(0, left)
            self.rule = rule
        case .locked(let rule):
            changesLeft = 0
            self.rule = rule
        }
    }
}

extension ApplicationError {
    public static let noMeet = ApplicationError(
        code: "no_meet",
        message: "No Meet is planned. Run `workout meet plan --date 2026-12-05 --federation ipf`.",
        kind: .domain
    )

    static func invalidMeetPlan(_ detail: String) -> ApplicationError {
        ApplicationError(code: "invalid_meet_plan", message: detail, kind: .domain)
    }

    static func meetRefused(_ refusal: MeetRefusal) -> ApplicationError {
        switch refusal {
        case .noAttemptOnDeck:
            ApplicationError(code: "no_attempt_on_deck", message: "No Attempt is on deck to take this.", kind: .domain)
        case .noWindowOpen:
            ApplicationError(code: "no_attempt_window", message: "No Attempt Window is open.", kind: .domain)
        case .changeNotAllowed(let rule):
            ApplicationError(code: "attempt_change_refused", message: "Rule \(rule) leaves this Attempt no change.", kind: .domain)
        case .weightNotLoadable(let weight):
            ApplicationError(code: "weight_not_loadable", message: "No bar loads \(weight.label) under these rules.", kind: .domain)
        }
    }
}

extension WorkoutApplication {
    /// With an edit, changes or creates the Plan. With an empty one, reads it.
    public func meetPlan(_ edit: MeetPlanEdit) throws -> MeetReport {
        if edit.isEmpty, meet.meet == nil { throw ApplicationError.noMeet }
        if !edit.isEmpty {
            let planned = try edit.applied(to: meet.meet)
            if meet.meet == nil {
                meet.start(planned)
            } else {
                meet.edit { $0 = planned }
            }
        }
        return try meetReport()
    }

    /// Takes one gesture on the day and reports what comes next at the application's clock.
    public func meetTick(_ gesture: MeetGesture) throws -> MeetReport {
        guard meet.meet != nil else { throw ApplicationError.noMeet }
        do {
            try take(gesture)
        } catch let refusal as MeetRefusal {
            throw ApplicationError.meetRefused(refusal)
        }
        return try meetReport()
    }

    private func take(_ gesture: MeetGesture) throws {
        switch gesture {
        case .read: break
        case .attemptsOut(let count): meet.setAttemptsOut(count)
        case .good: try meet.mark(.good)
        case .noLift: try meet.mark(.noLift)
        case .submit(let text): try meet.submitNext(try meetWeight(text))
        case .acceptTableEntry: try meet.acceptTableEntry()
        case .pass: try meet.pass()
        case .undo: meet.undoMark()
        case .change(let text): try meet.changeOnDeck(to: try meetWeight(text))
        }
    }

    private func meetWeight(_ text: String) throws -> Kilograms {
        guard let weight = Kilograms(parsing: text) else {
            throw ApplicationError.invalidMeetPlan("\"\(text)\" is not a weight in kilograms.")
        }
        return weight
    }

    private func meetReport() throws -> MeetReport {
        guard let current = meet.meet else { throw ApplicationError.noMeet }
        return MeetReport(current, canUndoMark: meet.canUndoMark, now: meet.now(), calendar: .current)
    }
}
