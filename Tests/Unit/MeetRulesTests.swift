import Foundation
import Testing

@testable import WorkoutTracker

private func kilos(_ value: Int) -> Kilograms { Kilograms(hundredths: value) }

@Suite("Federation Rules, one row each from the 2026 rulebooks")
struct FederationRulesTests {
    @Test("IPF 6.1(j), USAPL 5.3.14: a card is due within one minute of the lights")
    func theSubmissionWindowIsOneMinute() {
        #expect(FederationRules.ipf.submissionWindowSeconds == .init(value: 60, rule: "6.1(j)"))
        #expect(FederationRules.usapl.submissionWindowSeconds == .init(value: 60, rule: "5.3.14"))
    }

    @Test("IPF 6.1(j), USAPL 5.3.14.2: a missed window enters 2.5 kg more after a good lift", arguments: [Federation.ipf, .usapl])
    func aMissedWindowAddsToAGoodLift(federation: Federation) {
        #expect(federation.rules.tableEntry(after: kilos(18000), result: .good) == kilos(18250))
    }

    @Test("IPF 6.1(j), USAPL 5.3.14.2: a missed window repeats the weight after a no lift", arguments: [Federation.ipf, .usapl])
    func aMissedWindowRepeatsANoLift(federation: Federation) {
        #expect(federation.rules.tableEntry(after: kilos(18000), result: .noLift) == kilos(18000))
    }

    @Test("IPF 6.1(i), USAPL 5.3.1.1: one opener change, 3 minutes before round one or 3 Attempts before the Flight ahead ends")
    func anOpenerTakesOneChange() {
        let deadline = FederationRules.OpenerDeadline(minutesBeforeFirstRound: 3, attemptsBeforePreviousFlightEnds: 3)
        #expect(FederationRules.ipf.openerChanges == .init(value: 1, rule: "6.1(i)"))
        #expect(FederationRules.usapl.openerChanges == .init(value: 1, rule: "5.3.1.1"))
        #expect(FederationRules.ipf.openerDeadline == .init(value: deadline, rule: "6.1(i)"))
        #expect(FederationRules.usapl.openerDeadline == .init(value: deadline, rule: "5.3.1.1"))
    }

    @Test("IPF 6.1(l), USAPL 5.3.17.1: a third deadlift takes two changes")
    func aThirdDeadliftTakesTwoChanges() {
        #expect(FederationRules.ipf.thirdDeadliftChanges == .init(value: 2, rule: "6.1(l)"))
        #expect(FederationRules.usapl.thirdDeadliftChanges == .init(value: 2, rule: "5.3.17.1"))
    }

    @Test("IPF 6.1(k), USAPL 5.3.17: every other second and third is locked once submitted")
    func otherAttemptsAreLocked() {
        #expect(FederationRules.ipf.lockedAttempts == "6.1(k)")
        #expect(FederationRules.usapl.lockedAttempts == "5.3.17")
    }

    @Test("IPF 6.3 item 4, USAPL 5.4.8: the bar loads in 2.5 kg")
    func theBarLoadsInTwoAndAHalf() {
        #expect(FederationRules.ipf.barMultiple == .init(value: kilos(250), rule: "6.3 item 4"))
        #expect(FederationRules.usapl.barMultiple == .init(value: kilos(250), rule: "5.4.8"))
    }

    @Test("IPF 6.3 item 4(a), USAPL 5.4.8 A: a record may take a 0.5 kg multiple, and neither rulebook has a 1.25 kg one")
    func aRecordTakesAHalfKilo() {
        #expect(FederationRules.ipf.recordMultiple == .init(value: kilos(50), rule: "6.3 item 4(a)"))
        #expect(FederationRules.usapl.recordMultiple == .init(value: kilos(50), rule: "5.4.8 A"))
        #expect(FederationRules.ipf.verdict(on: kilos(18125), after: nil) == .notLoadable)
        #expect(FederationRules.usapl.verdict(on: kilos(18125), after: nil) == .notLoadable)
    }

    @Test("IPF 6.1(n), 6.1(o), USAPL 5.3.10: 20 minutes for one Flight, 10 for more")
    func theIntervalFollowsTheFlights() {
        let interval = FederationRules.Interval(oneFlightMinutes: 20, moreFlightsMinutes: 10)
        #expect(FederationRules.ipf.interval == .init(value: interval, rule: "6.1(n), 6.1(o)"))
        #expect(FederationRules.usapl.interval == .init(value: interval, rule: "5.3.10"))
    }

    @Test(
        "A weight reads against the bar and the Attempt before it",
        arguments: [
            (18000, nil, AttemptWeightVerdict.legal),
            (18250, nil, .legal),
            (18050, nil, .recordAttemptOnly),
            (18030, nil, .notLoadable),
            (18250, 18000, .legal),
            (18000, 18000, .belowPrevious(Kilograms(hundredths: 18000))),
            (17750, 18000, .belowPrevious(Kilograms(hundredths: 18000)))
        ] as [(Int, Int?, AttemptWeightVerdict)]
    )
    func aWeightReadsAgainstAGoodLift(proposed: Int, previous: Int?, expected: AttemptWeightVerdict) {
        let after = previous.map { (kilograms: kilos($0), result: AttemptResult.good) }
        #expect(FederationRules.ipf.verdict(on: kilos(proposed), after: after) == expected)
        #expect(FederationRules.usapl.verdict(on: kilos(proposed), after: after) == expected)
    }

    @Test("USAPL 5.3.14.1: the same weight is fine after a no lift, and lower never is", arguments: [Federation.ipf, .usapl])
    func theSameWeightStandsAfterANoLift(federation: Federation) {
        let missed = (kilograms: kilos(18000), result: AttemptResult.noLift)
        #expect(federation.rules.verdict(on: kilos(18000), after: missed) == .legal)
        #expect(federation.rules.verdict(on: kilos(17750), after: missed) == .belowPrevious(kilos(18000)))
    }
}

@Suite("The rules sheet")
struct MeetRuleLinesTests {
    @Test func eachFederationGoesByItsOwnName() {
        #expect(Federation.ipf.name == "IPF")
        #expect(Federation.usapl.name == "USAPL")
    }

    @Test("Each sentence stands alone, though two can cite one rule", arguments: [Federation.ipf, .usapl])
    func eachLineIsItsOwnSentence(federation: Federation) {
        let lines = federation.rules.lines
        #expect(Set(lines.map(\.text)).count == lines.count)
        #expect(lines.allSatisfy { !$0.rule.isEmpty })
    }

    @Test func theSentencesSayWhatTheTableDoes() {
        let lines = FederationRules.ipf.lines.map(\.text)
        #expect(lines.contains("With no card the table enters 2.5 kg more after a good lift, or the same weight after a no lift."))
        #expect(lines.contains("A third deadlift takes 2 changes, until you are called to the bar."))
        #expect(
            lines.contains(
                "Each opener takes 1 change, until 3 minutes before the first round, or 3 Attempts before the Flight ahead of you ends."
            )
        )
    }
}

@Suite("Kilograms")
struct KilogramsTests {
    @Test(
        "A typed weight parses, at most to two decimals",
        arguments: [
            ("187.5", 18750), ("190", 19000), ("187,5", 18750), (" 60 ", 6000), ("182.25", 18225), ("0.5", 50)
        ]
    )
    func aTypedWeightParses(text: String, hundredths: Int) {
        #expect(Kilograms(parsing: text) == Kilograms(hundredths: hundredths))
    }

    @Test(
        "Anything else is not a weight",
        arguments: ["", "0", "-5", "abc", "1.2.3", "187.555", "187.5kg", "١٨٠", "12345", "92233720368547758"]
    )
    func anythingElseIsNotAWeight(text: String) {
        #expect(Kilograms(parsing: text) == nil)
    }

    @Test(
        "Pounds print to the tenth, and a 2.5 kg jump never rounds away",
        arguments: [
            (13000, "286.6 lb"),  // USAPL 5.3.14.2's own example
            (18000, "396.8 lb"),
            (18250, "402.3 lb"),
            (2000, "44.1 lb"),
            (18050, "397.9 lb"),
            (10000, "220.5 lb"),
            (45360, "1000 lb")
        ]
    )
    func poundsPrintToTheTenth(hundredths: Int, pounds: String) {
        #expect(Kilograms(hundredths: hundredths).poundsLabel == pounds)
    }

    @Test("A numeral shows no trailing zero", arguments: [(19000, "190"), (18750, "187.5"), (18225, "182.25"), (18205, "182.05")])
    func aNumeralShowsNoTrailingZero(hundredths: Int, numeral: String) {
        #expect(Kilograms(hundredths: hundredths).numeral == numeral)
    }

    @Test("A stepper walking down stops at its floor")
    func aStepperStopsAtItsFloor() {
        #expect(kilos(2100).subtracting(kilos(250), floor: kilos(2000)) == kilos(2000))
        #expect(kilos(5000).subtracting(kilos(250), floor: kilos(2000)) == kilos(4750))
    }

    @Test("A weight survives a JSON round trip exactly")
    func aWeightSurvivesJSON() throws {
        let weights = [kilos(18750), kilos(18225), kilos(50)]
        let data = try JSONEncoder().encode(weights)
        #expect(try JSONDecoder().decode([Kilograms].self, from: data) == weights)
        #expect(String(bytes: data, encoding: .utf8) == "[187.5,182.25,0.5]")
    }
}

@Suite("A Meet's date is a calendar day")
struct MeetDateTests {
    private static let meet = MeetDate(year: 2026, month: 12, day: 5)

    private func calendar(_ zone: String) throws -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(identifier: zone))
        return calendar
    }

    private func instant(_ iso: String) throws -> Date {
        try #require(ISO8601DateFormatter().date(from: iso))
    }

    @Test("A minute before midnight is still tomorrow, and a minute after is today")
    func midnightMovesTheCountByOne() throws {
        let date = try #require(Self.meet)
        let chicago = try calendar("America/Chicago")
        #expect(date.countdownLabel(from: try instant("2026-12-05T05:59:00Z"), in: chicago) == "Tomorrow")
        #expect(date.countdownLabel(from: try instant("2026-12-05T06:01:00Z"), in: chicago) == "Today")
    }

    @Test("The same instant reads as the local day where the phone is")
    func theLocalDayDecides() throws {
        let date = try #require(Self.meet)
        let now = try instant("2026-12-04T23:30:00Z")
        #expect(date.daysUntil(from: now, in: try calendar("America/Chicago")) == 1)
        #expect(date.daysUntil(from: now, in: try calendar("Asia/Tokyo")) == 0)
    }

    @Test("A daylight saving change does not lose a day")
    func daylightSavingKeepsTheCount() throws {
        let date = try #require(MeetDate(year: 2026, month: 11, day: 2))
        #expect(date.daysUntil(from: try instant("2026-10-31T17:00:00Z"), in: try calendar("America/Chicago")) == 2)
    }

    @Test(
        "The label counts in days from the phone's today",
        arguments: [
            ("2026-11-06T18:00:00Z", "In 29 days"),
            ("2026-12-06T18:00:00Z", "Yesterday"),
            ("2026-12-08T18:00:00Z", "3 days ago")
        ]
    )
    func theLabelCountsDays(now: String, label: String) throws {
        let date = try #require(Self.meet)
        #expect(date.countdownLabel(from: try instant(now), in: try calendar("America/Chicago")) == label)
    }

    @Test("Only a real day parses", arguments: ["2026-02-30", "2026-13-01", "soon", "2026-12", ""])
    func onlyARealDayParses(text: String) {
        #expect(MeetDate(text) == nil)
    }

    @Test("A date survives JSON as its calendar string")
    func aDateSurvivesJSON() throws {
        let date = try #require(Self.meet)
        let data = try JSONEncoder().encode([date])
        #expect(String(bytes: data, encoding: .utf8) == "[\"2026-12-05\"]")
        #expect(try JSONDecoder().decode([MeetDate].self, from: data) == [date])
    }
}
