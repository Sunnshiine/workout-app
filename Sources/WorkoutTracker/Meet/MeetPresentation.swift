import Foundation

extension MeetDate {
    /// What the Block grid's foot says of a Meet: `Meet in 29 days`, `Meet today`, or only `Meet`
    /// once the day has passed.
    func entryLabel(from now: Date, in calendar: Calendar) -> String {
        let days = daysUntil(from: now, in: calendar)
        switch days {
        case 0: return "Meet today"
        case 1: return "Meet tomorrow"
        case 2...: return "Meet in \(days) days"
        default: return "Meet"
        }
    }
}

extension MeetCue {
    /// The pace is the athlete's estimate, so it never reads as a timer.
    fileprivate static func estimate(_ seconds: Int) -> String {
        seconds < 60 ? "under a minute" : "about \(Int((Double(seconds) / 60).rounded(.up))) min"
    }

    fileprivate static func attempts(_ count: Int) -> String {
        count == 1 ? "1 attempt" : "\(count) attempts"
    }
}

struct MeetOnDeckFace: Equatable {
    /// Which Attempt all this leads to: `Squat opener`.
    let place: String
    let caption: String
    let numeral: String
    let pounds: String
    let detail: String
    let isOnThePlatform: Bool
    let attemptsOutNumeral: String
    let attemptsOutLabel: String
    /// The Main Lift just finished and the interval's rule, on the opener of the next one.
    let intervalNote: String?
    /// `Change opener, 1 left`, when the rule allows the Attempt on deck a change.
    let changeLabel: String?
    let accessibilitySummary: String

    init(_ deck: AttemptOnDeck, rules: FederationRules) {
        let place = "\(deck.lift.meetName) \(deck.ordinal.name.lowercased())"
        self.place = place
        attemptsOutNumeral = "\(deck.attemptsOut)"
        attemptsOutLabel = deck.attemptsOut == 1 ? "attempt out" : "attempts out"
        intervalNote = deck.liftFinished.map { finished in
            let interval = rules.interval.value
            return "\(finished.meetName) is done. \(interval.oneFlightMinutes) minutes until \(deck.lift.meetName) with one flight, "
                + "\(interval.moreFlightsMinutes) with more."
        }
        changeLabel = deck.allowance.changesLeft.map { "Change \(deck.ordinal.name.lowercased()), \($0) left" }
        let reading = Reading.of(deck.cue, ordinal: deck.ordinal, place: place)
        caption = reading.caption
        numeral = reading.weight.numeral
        pounds = reading.weight.poundsLabel
        detail = reading.detail
        isOnThePlatform = reading.isOnThePlatform
        accessibilitySummary = reading.spoken
    }

    private struct Reading {
        let caption: String
        let weight: Kilograms
        let detail: String
        let isOnThePlatform: Bool
        let spoken: String

        static func of(_ cue: MeetCue, ordinal: AttemptOrdinal, place: String) -> Reading {
            switch cue {
            case .warmUp(let step, let attemptsUntil, let secondsUntil):
                warmUp(step, attemptsUntil: attemptsUntil, secondsUntil: secondsUntil)
            case .attempt(let weight, let attemptsOut, let secondsUntil):
                attempt(weight, ordinal: ordinal, attemptsOut: attemptsOut, secondsUntil: secondsUntil)
            case .platform(let weight):
                Reading(
                    caption: "On the platform",
                    weight: weight,
                    detail: place,
                    isOnThePlatform: true,
                    spoken: "On the platform, \(place), \(weight.spoken)"
                )
            }
        }

        private static func warmUp(_ step: WarmupRoomStep, attemptsUntil: Int, secondsUntil: Int) -> Reading {
            let isNow = attemptsUntil == 0
            let caption = isNow ? "Warm up now" : "Warm up next"
            let line = "\(step.repsLabel) at \(step.attemptsOut) out"
            let detail = isNow ? line : "\(line), in \(MeetCue.attempts(attemptsUntil)), \(MeetCue.estimate(secondsUntil))"
            return Reading(
                caption: caption,
                weight: step.kilograms,
                detail: detail,
                isOnThePlatform: false,
                spoken: "\(caption), \(step.kilograms.spoken), \(detail)"
            )
        }

        private static func attempt(_ weight: Kilograms, ordinal: AttemptOrdinal, attemptsOut: Int, secondsUntil: Int) -> Reading {
            let caption = ordinal == .opener ? "Opener" : "\(ordinal.name) attempt"
            let detail = "\(MeetCue.attempts(attemptsOut)) out, \(MeetCue.estimate(secondsUntil))"
            return Reading(
                caption: caption,
                weight: weight,
                detail: detail,
                isOnThePlatform: false,
                spoken: "\(caption), \(weight.spoken), \(detail)"
            )
        }
    }
}

extension AttemptChangeAllowance {
    fileprivate var changesLeft: Int? {
        guard case .changesLeft(let left, _) = self, left > 0 else { return nil }
        return left
    }
}

extension WarmupRoomStep {
    var repsLabel: String { reps == 1 ? "1 rep" : "\(reps) reps" }

    /// `60 kilograms, 5 reps, at 18 attempts out`, as VoiceOver reads a row of the plan.
    var spoken: String {
        let out = attemptsOut == 1 ? "1 attempt out" : "\(attemptsOut) attempts out"
        return "\(kilograms.spoken), \(repsLabel), at \(out)"
    }
}

extension Kilograms {
    /// `180 kilograms`, as VoiceOver should read it.
    var spoken: String { "\(numeral) kilograms" }
}

struct AttemptWindowFace: Equatable {
    enum Stage: Equatable {
        case open
        case closing
        case expired
    }

    let stage: Stage
    /// `Good lift, 180 kg`, what the window follows from.
    let markLine: String
    let caption: String
    let numeral: String
    /// `Second attempt`, what the weight under the clock is for.
    let attemptLabel: String
    /// The table's rule, so the view can hold its room before it shows.
    let rule: String
    let showsRule: Bool
    /// The share of the minute left, stepping once a second.
    let remaining: Double
    let accessibilityValue: String

    init(_ window: OpenAttemptWindow, windowSeconds: Int) {
        let mark = window.result == .good ? "Good lift" : "No lift"
        markLine = "\(mark), \(window.marked.label)"
        attemptLabel = "\(window.ordinal.name) attempt"
        let rule = "No card means \(window.tableEntry.label)"
        self.rule = rule
        switch window.reading {
        case .open(let left):
            stage = .open
            caption = "Time to submit"
            numeral = Self.numeral(left)
            showsRule = false
            remaining = Double(left) / Double(windowSeconds)
            accessibilityValue = "\(Self.seconds(left)) left to submit your \(attemptLabel.lowercased())"
        case .closing(let left):
            stage = .closing
            caption = "Time to submit"
            numeral = Self.numeral(left)
            showsRule = true
            remaining = Double(left) / Double(windowSeconds)
            accessibilityValue = "\(Self.seconds(left)) left. \(rule)"
        case .expired:
            stage = .expired
            caption = "Time"
            numeral = "0"
            showsRule = true
            remaining = 0
            accessibilityValue = "Time. \(rule)"
        }
    }

    private static func numeral(_ seconds: Int) -> String {
        seconds < 60 ? "\(seconds)" : "\(seconds / 60):" + String(format: "%02d", seconds % 60)
    }

    private static func seconds(_ count: Int) -> String {
        count == 1 ? "1 second" : "\(count) seconds"
    }
}

/// An Attempt's number stays what the coach called until the athlete moves it.
struct MeetWeightEntry: Equatable {
    var text: String
    let rules: FederationRules

    init(_ kilograms: Kilograms?, rules: FederationRules) {
        text = kilograms?.numeral ?? ""
        self.rules = rules
    }

    var kilograms: Kilograms? { Kilograms(parsing: text) }

    var pounds: String { kilograms?.poundsLabel ?? " " }

    mutating func stepUp() {
        set((kilograms ?? WarmupRoomPlanFill.bar) + rules.barMultiple.value)
    }

    mutating func stepDown() {
        set((kilograms ?? WarmupRoomPlanFill.bar).subtracting(rules.barMultiple.value, floor: WarmupRoomPlanFill.bar))
    }

    private mutating func set(_ kilograms: Kilograms) {
        text = kilograms.numeral
    }

    /// Whether this entry can go in. The rules decide only what no bar can load. A rule about the
    /// last attempt reads as a note, because the table owns that call and the app records it.
    func canSave(after previous: (kilograms: Kilograms, result: AttemptResult)?) -> Bool {
        guard let kilograms else { return false }
        return rules.verdict(on: kilograms, after: previous) != .notLoadable
    }

    func note(after previous: (kilograms: Kilograms, result: AttemptResult)?) -> MeetWeightNote? {
        guard let kilograms else {
            return text.trimmed.isEmpty ? nil : .refused("Enter a weight in kilograms.")
        }
        return note(on: rules.verdict(on: kilograms, after: previous))
    }

    private func note(on verdict: AttemptWeightVerdict) -> MeetWeightNote? {
        switch verdict {
        case .legal:
            nil
        case .recordAttemptOnly:
            .rule("Only a record attempt can take this weight.")
        case .belowPrevious(let last):
            .rule("The rule asks for more than this after \(last.label).")
        case .notLoadable:
            .refused("No bar loads this. It takes multiples of \(rules.recordMultiple.value.label).")
        }
    }
}

enum MeetWeightNote: Equatable {
    /// A rule the table applies. The athlete may still record it.
    case rule(String)
    case refused(String)
}

extension AttemptState {
    var spoken: String {
        switch self {
        case .planned: "planned"
        case .submitted: "submitted"
        case .good: "good lift"
        case .noLift: "no lift"
        }
    }
}
