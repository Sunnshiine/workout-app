import Foundation

enum Federation: String, Codable, CaseIterable, Sendable {
    case ipf
    case usapl

    var name: String {
        switch self {
        case .ipf: "IPF"
        case .usapl: "USAPL"
        }
    }

    var rules: FederationRules {
        switch self {
        case .ipf: .ipf
        case .usapl: .usapl
        }
    }
}

enum AttemptResult: String, Codable, Sendable {
    case good
    case noLift
}

/// The app reports this and never suggests another number.
enum AttemptWeightVerdict: Equatable, Sendable {
    case legal
    /// Off the bar's multiple, but a record Attempt may take it.
    case recordAttemptOnly
    /// The rule asks for more than this weight, given the Attempt before it.
    case belowPrevious(Kilograms)
    /// No loading makes this weight under these rules.
    case notLoadable
}

/// Every value keeps its rule number, so a reader can open the rulebook at the line it came from.
struct FederationRules: Equatable, Sendable {
    struct Cited<Value: Equatable & Sendable>: Equatable, Sendable {
        let value: Value
        let rule: String
    }

    struct OpenerDeadline: Equatable, Sendable {
        /// The first Flight may change an opener until this long before the first round.
        let minutesBeforeFirstRound: Int
        /// A later Flight may change one until this many Attempts before the Flight ahead ends.
        let attemptsBeforePreviousFlightEnds: Int
    }

    struct Interval: Equatable, Sendable {
        let oneFlightMinutes: Int
        let moreFlightsMinutes: Int
    }

    let rulebook: String
    let submissionWindowSeconds: Cited<Int>
    /// What the table adds after a good lift when no card arrives. After a no lift it enters the
    /// same weight, so that case needs no value.
    let missedWindowIncrease: Cited<Kilograms>
    let openerChanges: Cited<Int>
    let openerDeadline: Cited<OpenerDeadline>
    let lockedAttempts: String
    let thirdDeadliftChanges: Cited<Int>
    let barMultiple: Cited<Kilograms>
    let recordMultiple: Cited<Kilograms>
    let neverBelowPrevious: String
    let interval: Cited<Interval>

    static let ipf = FederationRules(
        rulebook: "IPF Technical Rules, effective 1 March 2026",
        submissionWindowSeconds: Cited(value: 60, rule: "6.1(j)"),
        missedWindowIncrease: Cited(value: Kilograms(hundredths: 250), rule: "6.1(j)"),
        openerChanges: Cited(value: 1, rule: "6.1(i)"),
        openerDeadline: Cited(value: OpenerDeadline(minutesBeforeFirstRound: 3, attemptsBeforePreviousFlightEnds: 3), rule: "6.1(i)"),
        lockedAttempts: "6.1(k)",
        thirdDeadliftChanges: Cited(value: 2, rule: "6.1(l)"),
        barMultiple: Cited(value: Kilograms(hundredths: 250), rule: "6.3 item 4"),
        recordMultiple: Cited(value: Kilograms(hundredths: 50), rule: "6.3 item 4(a)"),
        neverBelowPrevious: "6.3 item 4",
        interval: Cited(value: Interval(oneFlightMinutes: 20, moreFlightsMinutes: 10), rule: "6.1(n), 6.1(o)")
    )

    static let usapl = FederationRules(
        rulebook: "USAPL Rulebook v2026.2, in effect 1 January 2026",
        submissionWindowSeconds: Cited(value: 60, rule: "5.3.14"),
        missedWindowIncrease: Cited(value: Kilograms(hundredths: 250), rule: "5.3.14.2"),
        openerChanges: Cited(value: 1, rule: "5.3.1.1"),
        openerDeadline: Cited(value: OpenerDeadline(minutesBeforeFirstRound: 3, attemptsBeforePreviousFlightEnds: 3), rule: "5.3.1.1"),
        lockedAttempts: "5.3.17",
        thirdDeadliftChanges: Cited(value: 2, rule: "5.3.17.1"),
        barMultiple: Cited(value: Kilograms(hundredths: 250), rule: "5.4.8"),
        recordMultiple: Cited(value: Kilograms(hundredths: 50), rule: "5.4.8 A"),
        neverBelowPrevious: "5.3.14.1",
        interval: Cited(value: Interval(oneFlightMinutes: 20, moreFlightsMinutes: 10), rule: "5.3.10")
    )

    var lines: [(text: String, rule: String)] {
        [
            (
                "A card for your next Attempt is due within \(submissionWindowSeconds.value / 60) minute of the lights.",
                submissionWindowSeconds.rule
            ),
            (
                "With no card the table enters \(missedWindowIncrease.value.label) more after a good lift, "
                    + "or the same weight after a no lift.",
                missedWindowIncrease.rule
            ),
            (
                "Each opener takes \(openerChanges.value) change, \(ChangeDeadline.opener(openerDeadline.value).phrase).",
                openerDeadline.rule
            ),
            (
                "A third deadlift takes \(thirdDeadliftChanges.value) changes, \(ChangeDeadline.called.phrase).",
                thirdDeadliftChanges.rule
            ),
            ("No other second or third can change once it is in.", lockedAttempts),
            (
                "The bar loads in \(barMultiple.value.label). A record Attempt may take \(recordMultiple.value.label).",
                barMultiple.rule
            ),
            ("Never lower than your last Attempt.", neverBelowPrevious),
            (intervalLine, interval.rule)
        ]
    }

    var intervalLine: String {
        "\(interval.value.oneFlightMinutes) minutes between lifts with one Flight, \(interval.value.moreFlightsMinutes) with more."
    }

    /// What the table enters when the Attempt Window closes with no card.
    func tableEntry(after kilograms: Kilograms, result: AttemptResult) -> Kilograms {
        switch result {
        case .good: kilograms + missedWindowIncrease.value
        case .noLift: kilograms
        }
    }

    func verdict(on proposed: Kilograms, after previous: (kilograms: Kilograms, result: AttemptResult)?) -> AttemptWeightVerdict {
        guard proposed.isMultiple(of: recordMultiple.value) else { return .notLoadable }
        if let previous {
            let isBelow = previous.result == .good ? proposed <= previous.kilograms : proposed < previous.kilograms
            if isBelow { return .belowPrevious(previous.kilograms) }
        }
        return proposed.isMultiple(of: barMultiple.value) ? .legal : .recordAttemptOnly
    }
}
