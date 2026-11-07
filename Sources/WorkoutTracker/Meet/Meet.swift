import Foundation

enum AttemptOrdinal: Int, CaseIterable, Codable, Sendable {
    case opener
    case second
    case third

    var name: String {
        switch self {
        case .opener: "Opener"
        case .second: "Second"
        case .third: "Third"
        }
    }
}

enum AttemptState: String, Codable, Sendable {
    case planned
    case submitted
    case good
    case noLift

    var result: AttemptResult? {
        switch self {
        case .planned, .submitted: nil
        case .good: .good
        case .noLift: .noLift
        }
    }
}

struct Attempt: Hashable, Codable, Sendable {
    var kilograms: Kilograms
    var state: AttemptState
    /// Changes spent on the day. A correction on the Plan is not one, because no card moved.
    var changesUsed: Int

    init(kilograms: Kilograms, state: AttemptState) {
        self.kilograms = kilograms
        self.state = state
        changesUsed = 0
    }

    var isMarked: Bool { state.result != nil }
}

struct MeetLift: Hashable, Codable, Sendable {
    let lift: MainLift
    /// In order, with nothing after the last one called. Empty keeps this lift off the day.
    private(set) var attempts: [Attempt]
    var rackHeights: String
    /// Kept in the order the athlete reads it, from the most Attempts Out to the fewest.
    private(set) var warmupRoomPlan: [WarmupRoomStep]

    init(lift: MainLift, attempts: [Attempt], rackHeights: String, warmupRoomPlan: [WarmupRoomStep]) {
        self.lift = lift
        self.attempts = attempts
        self.rackHeights = rackHeights
        self.warmupRoomPlan = Self.ordered(warmupRoomPlan)
    }

    static func empty(_ lift: MainLift) -> MeetLift {
        MeetLift(lift: lift, attempts: [], rackHeights: "", warmupRoomPlan: [])
    }

    var markedCount: Int { attempts.count(where: \.isMarked) }
    var lastMarked: Attempt? { attempts.last(where: \.isMarked) }
    var bestGoodLift: Kilograms? { attempts.filter { $0.state == .good }.map(\.kilograms).max() }

    /// Only the next blank place can take a new one, so a third never exists without a second.
    mutating func enter(_ kilograms: Kilograms, at ordinal: AttemptOrdinal) {
        if attempts.indices.contains(ordinal.rawValue) {
            attempts[ordinal.rawValue].kilograms = kilograms
        } else if ordinal.rawValue == attempts.count {
            attempts.append(Attempt(kilograms: kilograms, state: .planned))
        }
    }

    /// Takes an unmarked Attempt off the Plan, and any after it, which would have nothing before them.
    mutating func clear(from ordinal: AttemptOrdinal) {
        guard attempts.indices.contains(ordinal.rawValue), !attempts[ordinal.rawValue].isMarked else { return }
        attempts.removeSubrange(ordinal.rawValue...)
    }

    mutating func setWarmupRoomPlan(_ steps: [WarmupRoomStep]) {
        warmupRoomPlan = Self.ordered(steps)
    }

    fileprivate mutating func markNext(_ result: AttemptResult) {
        guard let index = attempts.firstIndex(where: { !$0.isMarked }) else { return }
        attempts[index].state = result == .good ? .good : .noLift
    }

    fileprivate mutating func submitNext(_ kilograms: Kilograms) {
        if let index = attempts.firstIndex(where: { !$0.isMarked }) {
            attempts[index].kilograms = kilograms
            attempts[index].state = .submitted
        } else {
            attempts.append(Attempt(kilograms: kilograms, state: .submitted))
        }
    }

    fileprivate mutating func changeNext(to kilograms: Kilograms) {
        guard let index = attempts.firstIndex(where: { !$0.isMarked }) else { return }
        attempts[index].kilograms = kilograms
        attempts[index].changesUsed += 1
    }

    fileprivate mutating func dropUnmarkedAttempts() {
        attempts.removeAll { !$0.isMarked }
    }

    private static func ordered(_ steps: [WarmupRoomStep]) -> [WarmupRoomStep] {
        steps.sorted { $0.attemptsOut > $1.attemptsOut }
    }
}

enum AttemptChangeAllowance: Equatable, Sendable {
    case changesLeft(Int, rule: String)
    case locked(rule: String)

    var canChange: Bool {
        if case .changesLeft(let left, _) = self { return left > 0 }
        return false
    }
}

struct AttemptOnDeck: Equatable, Sendable {
    let lift: MainLift
    let ordinal: AttemptOrdinal
    let kilograms: Kilograms
    let attemptsOut: Int
    let cue: MeetCue
    let allowance: AttemptChangeAllowance
    /// The Main Lift the athlete just finished, when this is the opener of the next one.
    let liftFinished: MainLift?
}

struct OpenAttemptWindow: Equatable, Sendable {
    let lift: MainLift
    let marked: Kilograms
    let result: AttemptResult
    let ordinal: AttemptOrdinal
    /// The coach's number for the next Attempt, or nil when it is not called yet.
    let planned: Kilograms?
    let tableEntry: Kilograms
    let reading: AttemptWindow.Reading
}

/// Every value here derives from the Attempts, Attempts Out, and the window, so a relaunch reads
/// the same day.
enum MeetStage: Equatable, Sendable {
    case noAttempts
    case onDeck(AttemptOnDeck)
    case window(OpenAttemptWindow)
    case finished
}

/// The screens only offer what the stage allows, so the CLI is the one surface that meets these.
enum MeetRefusal: Error, Equatable, Sendable {
    case noAttemptOnDeck
    case noWindowOpen
    case changeNotAllowed(rule: String)
    case weightNotLoadable(Kilograms)
}

/// One Meet on this phone. It never reaches the Sheet.
struct Meet: Hashable, Codable, Sendable {
    var date: MeetDate
    var federation: Federation
    var liftersInFlight: Int
    var secondsPerAttempt: Int
    /// Squat, bench, deadlift, always all three in platform order.
    private(set) var lifts: [MeetLift]
    /// The athlete's count, or nil when a new lift starts where its Warm-up Room Plan does.
    private(set) var countedAttemptsOut: Int?
    private(set) var attemptWindow: AttemptWindow?

    static let defaultLiftersInFlight = 12
    /// A round of 10 to 14 lifters takes about 10 to 15 minutes. No rulebook states a pace, so this
    /// is only where the athlete's own setting starts.
    static let defaultSecondsPerAttempt = 60

    init(date: MeetDate, federation: Federation) {
        self.date = date
        self.federation = federation
        liftersInFlight = Self.defaultLiftersInFlight
        secondsPerAttempt = Self.defaultSecondsPerAttempt
        lifts = MainLift.allCases.map(MeetLift.empty)
    }

    var rules: FederationRules { federation.rules }

    func lift(_ lift: MainLift) -> MeetLift {
        lifts.first { $0.lift == lift } ?? .empty(lift)
    }

    mutating func editLift(_ lift: MainLift, _ edit: (inout MeetLift) -> Void) {
        guard let index = lifts.firstIndex(where: { $0.lift == lift }) else { return }
        edit(&lifts[index])
    }

    // MARK: - The day

    func stage(at now: Date) -> MeetStage {
        if let window = attemptWindow, let open = open(window, at: now) {
            return .window(open)
        }
        guard let index = lifts.firstIndex(where: { $0.attempts.contains { !$0.isMarked } }) else {
            return lifts.contains { !$0.attempts.isEmpty } ? .finished : .noAttempts
        }
        return .onDeck(onDeck(liftAt: index))
    }

    private func onDeck(liftAt index: Int) -> AttemptOnDeck {
        let lift = lifts[index]
        let ordinal = AttemptOrdinal(rawValue: lift.markedCount) ?? .third
        let attempt = lift.attempts[ordinal.rawValue]
        let warmups = ordinal == .opener ? lift.warmupRoomPlan : []
        let attemptsOut = countedAttemptsOut ?? warmups.first?.attemptsOut ?? liftersInFlight
        return AttemptOnDeck(
            lift: lift.lift,
            ordinal: ordinal,
            kilograms: attempt.kilograms,
            attemptsOut: attemptsOut,
            cue: MeetClock.cue(
                attemptsOut: attemptsOut,
                secondsPerAttempt: secondsPerAttempt,
                warmups: warmups,
                attempt: attempt.kilograms
            ),
            allowance: allowance(for: attempt, of: lift.lift, at: ordinal),
            liftFinished: ordinal == .opener ? lifts[..<index].last { !$0.attempts.isEmpty }?.lift : nil
        )
    }

    private func allowance(for attempt: Attempt, of lift: MainLift, at ordinal: AttemptOrdinal) -> AttemptChangeAllowance {
        switch (ordinal, lift) {
        case (.opener, _):
            .changesLeft(rules.openerChanges.value - attempt.changesUsed, rule: rules.openerChanges.rule)
        case (.third, .deadlift):
            .changesLeft(rules.thirdDeadliftChanges.value - attempt.changesUsed, rule: rules.thirdDeadliftChanges.rule)
        default:
            .locked(rule: rules.lockedAttempts)
        }
    }

    private func open(_ window: AttemptWindow, at now: Date) -> OpenAttemptWindow? {
        let lift = lift(window.lift)
        guard let marked = lift.lastMarked, let result = marked.state.result else { return nil }
        guard let ordinal = AttemptOrdinal(rawValue: lift.markedCount) else { return nil }
        return OpenAttemptWindow(
            lift: window.lift,
            marked: marked.kilograms,
            result: result,
            ordinal: ordinal,
            planned: lift.attempts.first { !$0.isMarked }?.kilograms,
            tableEntry: rules.tableEntry(after: marked.kilograms, result: result),
            reading: window.reading(at: now)
        )
    }

    // MARK: - Gestures

    mutating func setAttemptsOut(_ count: Int) {
        countedAttemptsOut = max(0, count)
    }

    /// The lights landed. The mark itself starts the next Attempt's window, because they are one
    /// moment on the platform. Attempts Out restarts at one round of the Flight, an estimate the
    /// stepper corrects, or at the next lift's Warm-up Room Plan after the last Attempt of a lift.
    mutating func mark(_ result: AttemptResult, at now: Date) throws(MeetRefusal) {
        guard case .onDeck(let deck) = stage(at: now) else { throw .noAttemptOnDeck }
        editLift(deck.lift) { $0.markNext(result) }
        if deck.ordinal == .third {
            countedAttemptsOut = nil
        } else {
            countedAttemptsOut = liftersInFlight
            attemptWindow = AttemptWindow(lift: deck.lift, startedAt: now, seconds: rules.submissionWindowSeconds.value)
        }
    }

    /// The next Attempt is in, whichever way it got there: the athlete's card inside the window,
    /// their card after it, or the table's own entry when the window closed with none. Each answer
    /// runs through here.
    mutating func submitNext(_ kilograms: Kilograms, at now: Date) throws(MeetRefusal) {
        guard let window = attemptWindow else { throw .noWindowOpen }
        guard rules.verdict(on: kilograms, after: nil) != .notLoadable else { throw .weightNotLoadable(kilograms) }
        editLift(window.lift) { $0.submitNext(kilograms) }
        attemptWindow = nil
    }

    mutating func pass() throws(MeetRefusal) {
        guard let window = attemptWindow else { throw .noWindowOpen }
        editLift(window.lift) { $0.dropUnmarkedAttempts() }
        attemptWindow = nil
        countedAttemptsOut = nil
    }

    mutating func changeOnDeck(to kilograms: Kilograms, at now: Date) throws(MeetRefusal) {
        guard case .onDeck(let deck) = stage(at: now) else { throw .noAttemptOnDeck }
        guard deck.allowance.canChange else { throw .changeNotAllowed(rule: rule(of: deck.allowance)) }
        guard rules.verdict(on: kilograms, after: nil) != .notLoadable else { throw .weightNotLoadable(kilograms) }
        editLift(deck.lift) { $0.changeNext(to: kilograms) }
    }

    private func rule(of allowance: AttemptChangeAllowance) -> String {
        switch allowance {
        case .changesLeft(_, let rule), .locked(let rule): rule
        }
    }

    // MARK: - The result

    /// The sum of each lift's best good lift, or nil when a lift on the day has none: a lifter with
    /// no good lift in a discipline has no total.
    var total: Kilograms? {
        let bests = lifts.filter { !$0.attempts.isEmpty }.map(\.bestGoodLift)
        guard !bests.isEmpty, !bests.contains(nil) else { return nil }
        return Kilograms(hundredths: bests.compactMap { $0?.hundredths }.reduce(0, +))
    }
}

/// Undoing restores the Meet as it stood, so a mistaken mark leaves nothing behind.
struct MeetRecord: Hashable, Codable, Sendable {
    let meet: Meet
    let beforeLastGesture: Meet?
}

/// Even steps from the empty bar up to the opener, which a Warm-up Room Plan can start from. It is
/// arithmetic, with no judgment of the athlete, and every line of it is theirs to change.
enum WarmupRoomPlanFill {
    static let bar = Kilograms(whole: 20)
    private static let reps = [5, 3, 3, 2, 1, 1]
    private static let attemptsOut = [18, 15, 12, 9, 6, 3]

    static func evenSteps(toOpener opener: Kilograms, barMultiple: Kilograms) -> [WarmupRoomStep] {
        let count = reps.count
        var steps: [WarmupRoomStep] = []
        for index in 0..<count {
            let raw = bar.hundredths + (opener.hundredths - bar.hundredths) * index / count
            let weight = Kilograms(hundredths: raw - raw % barMultiple.hundredths)
            guard weight >= bar, weight < opener, steps.last?.kilograms != weight else { continue }
            steps.append(WarmupRoomStep(kilograms: weight, reps: reps[index], attemptsOut: attemptsOut[index]))
        }
        return steps
    }
}
