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
        count == 1 ? "1 Attempt" : "\(count) Attempts"
    }
}

struct MeetOnDeckFace: Equatable {
    /// Which Attempt all this leads to: `Squat opener`.
    let place: String
    let caption: String
    let numeral: String
    let pounds: String
    /// What to do at this weight: `5 reps`, or `Squat opener` on the platform.
    let instruction: String?
    let detail: String?
    let isOnThePlatform: Bool
    let attemptsOutNumeral: String
    let attemptsOutLabel: String
    /// The interval's rule, on the opener of the next Main Lift until the athlete reaches the platform.
    let intervalNote: String?
    /// `Change opener, 1 left`, when the rule allows the Attempt on deck a change.
    let changeLabel: String?
    let accessibilitySummary: String

    init(_ deck: AttemptOnDeck, rules: FederationRules) {
        let place = "\(deck.lift.name) \(deck.ordinal.name.lowercased())"
        self.place = place
        attemptsOutNumeral = "\(deck.attemptsOut)"
        attemptsOutLabel = deck.attemptsOut == 1 ? "Attempt Out" : "Attempts Out"
        let reading = Reading.of(deck.cue, ordinal: deck.ordinal, place: place)
        caption = reading.caption
        numeral = reading.weight.numeral
        pounds = reading.weight.poundsLabel
        instruction = reading.instruction
        detail = reading.detail
        isOnThePlatform = reading.isOnThePlatform
        accessibilitySummary = reading.spoken
        intervalNote = deck.liftFinished == nil || reading.isOnThePlatform ? nil : rules.intervalLine
        changeLabel =
            reading.isOnThePlatform ? nil : deck.allowance.changesLeft.map { "Change \(deck.ordinal.name.lowercased()), \($0) left" }
    }

    private struct Reading {
        let caption: String
        let weight: Kilograms
        let instruction: String?
        let detail: String?
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
                    instruction: place,
                    detail: nil,
                    isOnThePlatform: true,
                    spoken: "On the platform, \(place), \(weight.spoken)"
                )
            }
        }

        private static func warmUp(_ step: WarmupRoomStep, attemptsUntil: Int, secondsUntil: Int) -> Reading {
            let isNow = attemptsUntil == 0
            let caption = isNow ? "Warm up now" : "Warm up next"
            let detail = isNow ? nil : "in \(MeetCue.attempts(attemptsUntil)), \(MeetCue.estimate(secondsUntil))"
            return Reading(
                caption: caption,
                weight: step.kilograms,
                instruction: step.repsLabel,
                detail: detail,
                isOnThePlatform: false,
                spoken: "\(caption), \(step.kilograms.spoken), \(step.repsLabel)" + (detail.map { ", \($0)" } ?? "")
            )
        }

        private static func attempt(_ weight: Kilograms, ordinal: AttemptOrdinal, attemptsOut: Int, secondsUntil: Int) -> Reading {
            let caption = ordinal == .opener ? "Opener" : "\(ordinal.name) Attempt"
            let estimate = MeetCue.estimate(secondsUntil)
            return Reading(
                caption: caption,
                weight: weight,
                instruction: nil,
                detail: estimate,
                isOnThePlatform: false,
                spoken: "\(caption), \(weight.spoken), \(MeetCue.attempts(attemptsOut)) Out, \(estimate)"
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

    /// `60 kilograms, 5 reps, at 18 Attempts Out`, as VoiceOver reads a row of the plan.
    var spoken: String {
        let out = attemptsOut == 1 ? "1 Attempt Out" : "\(attemptsOut) Attempts Out"
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
    /// `Second Attempt`, what the weight under the clock is for.
    let attemptLabel: String
    /// The table's rule, so the view can hold its room before it shows.
    let rule: String
    let showsRule: Bool
    let accessibilityValue: String

    init(_ window: OpenAttemptWindow) {
        let mark = window.result == .good ? "Good lift" : "No lift"
        markLine = "\(mark), \(window.marked.label)"
        attemptLabel = "\(window.ordinal.name) Attempt"
        let rule = "No card means \(window.tableEntry.label)"
        self.rule = rule
        switch window.reading {
        case .open(let left):
            stage = .open
            caption = "Time to submit"
            numeral = Self.numeral(left)
            showsRule = false
            accessibilityValue = "\(Self.seconds(left)) left to submit your \(attemptLabel)"
        case .closing(let left):
            stage = .closing
            caption = "Time to submit"
            numeral = Self.numeral(left)
            showsRule = true
            accessibilityValue = "\(Self.seconds(left)) left. \(rule)"
        case .expired:
            stage = .expired
            caption = "Time's up"
            numeral = Self.numeral(0)
            showsRule = true
            accessibilityValue = "Time's up. \(rule)"
        }
    }

    private static func numeral(_ seconds: Int) -> String {
        "\(seconds / 60):" + String(format: "%02d", seconds % 60)
    }

    private static func seconds(_ count: Int) -> String {
        count == 1 ? "1 second" : "\(count) seconds"
    }
}

/// An Attempt's number stays what the coach called until the athlete moves it. With nothing called
/// it stays blank, because the app never picks an Attempt.
struct MeetWeightEntry: Equatable {
    var text: String
    let rules: FederationRules
    private let blankStepsFrom: Kilograms

    init(called: Kilograms?, after previous: Kilograms?, rules: FederationRules) {
        text = called?.numeral ?? ""
        blankStepsFrom = previous ?? WarmupRoomPlanFill.bar
        self.rules = rules
    }

    var kilograms: Kilograms? { Kilograms(parsing: text) }

    var pounds: String { kilograms?.poundsLabel ?? " " }

    mutating func stepUp() {
        set((kilograms ?? blankStepsFrom) + rules.barMultiple.value)
    }

    mutating func stepDown() {
        set((kilograms ?? blankStepsFrom).subtracting(rules.barMultiple.value, floor: WarmupRoomPlanFill.bar))
    }

    private mutating func set(_ kilograms: Kilograms) {
        text = kilograms.numeral
    }

    /// Whether this entry can go in. The rules decide only what no bar can load. A rule about the
    /// last Attempt reads as a note, because the table owns that call and the app records it.
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
            .rule("Only a record Attempt can take this weight.")
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
