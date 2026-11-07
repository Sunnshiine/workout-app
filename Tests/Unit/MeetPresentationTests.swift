import Foundation
import Testing

@testable import WorkoutTracker

private func kilos(_ whole: Int) -> Kilograms { Kilograms(whole: whole) }

@MainActor
private func deck(of meet: Meet, at now: Date) throws -> AttemptOnDeck {
    guard case .onDeck(let deck) = meet.stage(at: now) else {
        throw MeetRefusal.noAttemptOnDeck
    }
    return deck
}

private let noon = Date(timeIntervalSince1970: 1_796_558_400)

@MainActor
private func squatMeet() throws -> Meet {
    var meet = Meet(date: try #require(MeetDate("2026-12-05")), federation: .ipf)
    meet.liftersInFlight = 10
    meet.editLift(.squat) { edit in
        edit.enter(kilos(180), at: .opener)
        edit.enter(kilos(190), at: .second)
        edit.setWarmupRoomPlan([
            WarmupRoomStep(kilograms: kilos(60), reps: 5, attemptsOut: 18),
            WarmupRoomStep(kilograms: kilos(150), reps: 1, attemptsOut: 6)
        ])
    }
    return meet
}

@Suite("The Platform's reading while the day waits")
@MainActor
struct MeetOnDeckFaceTests {
    @Test func aStepDueNowSaysSoWithItsRepsAndCount() throws {
        var meet = try squatMeet()
        try meet.setAttemptsOut(18)
        let face = MeetOnDeckFace(try deck(of: meet, at: noon), rules: meet.rules)
        #expect(face.caption == "Warm up now")
        #expect(face.numeral == "60")
        #expect(face.pounds == "132.3 lb")
        #expect(face.instruction == "5 reps")
        #expect(face.detail == nil)
        #expect(!face.isOnThePlatform)
        #expect(face.attemptsOutNumeral == "18")
    }

    @Test func theNextStepSaysHowFarOffItIsInAttemptsAndMinutes() throws {
        var meet = try squatMeet()
        try meet.setAttemptsOut(9)
        let face = MeetOnDeckFace(try deck(of: meet, at: noon), rules: meet.rules)
        #expect(face.caption == "Warm up next")
        #expect(face.numeral == "150")
        #expect(face.instruction == "1 rep")
        #expect(face.detail == "in 3 Attempts, about 3 min")
    }

    @Test func oneAttemptOutReadsInTheSingular() throws {
        var meet = try squatMeet()
        try meet.setAttemptsOut(1)
        let face = MeetOnDeckFace(try deck(of: meet, at: noon), rules: meet.rules)
        #expect(face.caption == "Opener")
        #expect(face.instruction == nil)
        #expect(face.detail == "about 1 min")
        #expect(face.attemptsOutLabel == "Attempt Out")
    }

    @Test func aPaceUnderAMinuteDoesNotClaimAMinute() throws {
        var meet = try squatMeet()
        meet.secondsPerAttempt = 45
        try meet.setAttemptsOut(1)
        let face = MeetOnDeckFace(try deck(of: meet, at: noon), rules: meet.rules)
        #expect(face.detail == "under a minute")
    }

    @Test func atZeroItNamesThePlatformAndTheAttempt() throws {
        var meet = try squatMeet()
        try meet.setAttemptsOut(0)
        let face = MeetOnDeckFace(try deck(of: meet, at: noon), rules: meet.rules)
        #expect(face.caption == "On the platform")
        #expect(face.numeral == "180")
        #expect(face.instruction == "Squat opener")
        #expect(face.detail == nil)
        #expect(face.isOnThePlatform)
    }

    @Test func anOpenerNotYetChangedOffersItsOneChange() throws {
        let meet = try squatMeet()
        let face = MeetOnDeckFace(try deck(of: meet, at: noon), rules: meet.rules)
        #expect(face.changeLabel == "Change opener, 1 left")
    }

    @Test func atZeroTheOpenerIsPastChanging() throws {
        var meet = try squatMeet()
        try meet.setAttemptsOut(0)
        let face = MeetOnDeckFace(try deck(of: meet, at: noon), rules: meet.rules)
        #expect(face.changeLabel == nil)
    }

    @Test func aSubmittedSecondOffersNoChange() throws {
        var meet = try squatMeet()
        try meet.setAttemptsOut(0)
        try meet.mark(.good, at: noon)
        try meet.submitNext(kilos(190), at: noon)
        let face = MeetOnDeckFace(try deck(of: meet, at: noon), rules: meet.rules)
        #expect(face.changeLabel == nil)
        #expect(face.caption == "Second Attempt")
    }

    @Test func theNextLiftsOpenerCarriesTheIntervalRule() throws {
        var meet = try squatMeet()
        meet.editLift(.bench) { $0.enter(kilos(110), at: .opener) }
        try meet.setAttemptsOut(0)
        try meet.mark(.good, at: noon)
        try meet.pass()
        let face = MeetOnDeckFace(try deck(of: meet, at: noon), rules: meet.rules)
        #expect(face.intervalNote == "20 minutes between lifts with one Flight, 10 with more.")
    }

    @Test func thePlatformDropsTheIntervalOnceTheAthleteIsOnIt() throws {
        var meet = try squatMeet()
        meet.editLift(.bench) { $0.enter(kilos(110), at: .opener) }
        try meet.setAttemptsOut(0)
        try meet.mark(.good, at: noon)
        try meet.pass()
        try meet.setAttemptsOut(0)
        let face = MeetOnDeckFace(try deck(of: meet, at: noon), rules: meet.rules)
        #expect(face.isOnThePlatform)
        #expect(face.intervalNote == nil)
    }
}

@Suite("The Platform's reading while an Attempt Window runs")
@MainActor
struct AttemptWindowFaceTests {
    private func face(secondsAfterMark: TimeInterval, result: AttemptResult = .good) throws -> AttemptWindowFace {
        var meet = try squatMeet()
        try meet.setAttemptsOut(0)
        try meet.mark(result, at: noon)
        guard case .window(let open) = meet.stage(at: noon.addingTimeInterval(secondsAfterMark)) else {
            throw MeetRefusal.noWindowOpen
        }
        return AttemptWindowFace(open)
    }

    @Test func theFullMinuteReadsAsAClockAndHoldsTheRuleBack() throws {
        let face = try face(secondsAfterMark: 0)
        #expect(face.stage == .open)
        #expect(face.numeral == "1:00")
        #expect(face.markLine == "Good lift, 180 kg")
        #expect(face.attemptLabel == "Second Attempt")
        #expect(!face.showsRule)
    }

    @Test func theLastFifteenSecondsShowTheTablesRule() throws {
        let open = try face(secondsAfterMark: 44)
        #expect(open.stage == .open)
        #expect(open.numeral == "0:16")
        let closing = try face(secondsAfterMark: 45)
        #expect(closing.stage == .closing)
        #expect(closing.numeral == "0:15")
        #expect(closing.showsRule)
        #expect(closing.rule == "No card means 182.5 kg")
    }

    @Test func expiryKeepsTheRuleAndTheClocksWidth() throws {
        let face = try face(secondsAfterMark: 60)
        #expect(face.stage == .expired)
        #expect(face.caption == "Time's up")
        #expect(face.numeral == "0:00")
        #expect(face.rule == "No card means 182.5 kg")
    }

    @Test func aMissKeepsTheSameWeightInTheRule() throws {
        let face = try face(secondsAfterMark: 50, result: .noLift)
        #expect(face.markLine == "No lift, 180 kg")
        #expect(face.rule == "No card means 180 kg")
    }

    @Test func oneSecondLeftIsSingularForVoiceOver() throws {
        #expect(try face(secondsAfterMark: 59).accessibilityValue == "1 second left. No card means 182.5 kg")
    }
}

@Suite("A weight being entered")
struct MeetWeightEntryTests {
    @Test func theSteppersMoveByTheBarsMultipleAndStopAtTheBar() throws {
        var entry = MeetWeightEntry(called: Kilograms(whole: 180), after: nil, rules: .ipf)
        entry.stepUp()
        #expect(entry.text == "182.5")
        #expect(entry.pounds == "402.3 lb")
        var low = MeetWeightEntry(called: Kilograms(hundredths: 2100), after: nil, rules: .ipf)
        low.stepDown()
        #expect(low.text == "20")
        low.stepDown()
        #expect(low.text == "20")
    }

    @Test func anEmptyEntryStepsFromTheBar() {
        var entry = MeetWeightEntry(called: nil, after: nil, rules: .ipf)
        #expect(entry.kilograms == nil)
        #expect(entry.note(after: nil) == nil)
        entry.stepUp()
        #expect(entry.text == "22.5")
    }

    @Test func anAttemptNobodyCalledStaysBlankAndCannotGoInUntilTheAthleteMovesIt() {
        var entry = MeetWeightEntry(called: nil, after: Kilograms(whole: 180), rules: .ipf)
        #expect(entry.text.isEmpty)
        #expect(!entry.canSave(after: (Kilograms(whole: 180), .good)))
        entry.stepUp()
        #expect(entry.text == "182.5")
        #expect(entry.canSave(after: (Kilograms(whole: 180), .good)))
    }

    @Test func textThatIsNotAWeightIsRefusedInPlainWords() {
        var entry = MeetWeightEntry(called: nil, after: nil, rules: .ipf)
        entry.text = "abc"
        #expect(!entry.canSave(after: nil))
        #expect(entry.note(after: nil) == .refused("Enter a weight in kilograms."))
    }

    @Test func aWeightNoBarLoadsCannotGoIn() {
        var entry = MeetWeightEntry(called: nil, after: nil, rules: .ipf)
        entry.text = "180.3"
        #expect(!entry.canSave(after: nil))
        #expect(entry.note(after: nil) == .refused("No bar loads this. It takes multiples of 0.5 kg."))
    }

    @Test func aRecordMultipleAndABackwardsWeightAreNotedAndStillRecorded() {
        var entry = MeetWeightEntry(called: nil, after: nil, rules: .ipf)
        entry.text = "180.5"
        #expect(entry.canSave(after: nil))
        #expect(entry.note(after: nil) == .rule("Only a record Attempt can take this weight."))
        entry.text = "170"
        let previous = (kilograms: Kilograms(whole: 180), result: AttemptResult.good)
        #expect(entry.canSave(after: previous))
        #expect(entry.note(after: previous) == .rule("The rule asks for more than this after 180 kg."))
    }
}

@Suite("What the Block grid's foot says of a Meet")
struct MeetEntryLabelTests {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Chicago") ?? .gmt
        return calendar
    }

    private func at(_ iso: String) throws -> Date {
        try #require(ISO8601DateFormatter().date(from: iso))
    }

    @Test func itCountsLocalCalendarDaysAcrossMidnight() throws {
        let date = try #require(MeetDate("2026-12-05"))
        #expect(date.entryLabel(from: try at("2026-12-05T05:59:00Z"), in: calendar) == "Meet tomorrow")
        #expect(date.entryLabel(from: try at("2026-12-05T06:00:00Z"), in: calendar) == "Meet today")
        #expect(date.entryLabel(from: try at("2026-12-06T05:59:00Z"), in: calendar) == "Meet today")
        #expect(date.entryLabel(from: try at("2026-12-06T06:00:00Z"), in: calendar) == "Meet")
        #expect(date.entryLabel(from: try at("2026-11-07T18:00:00Z"), in: calendar) == "Meet in 28 days")
    }
}

@Suite("What VoiceOver reads of the Plan")
struct MeetSpokenTests {
    @Test(
        "A mark reads as its word",
        arguments: [
            (AttemptState.planned, "planned"), (.submitted, "submitted"), (.good, "good lift"), (.noLift, "no lift")
        ]
    )
    func aMarkReadsAsItsWord(state: AttemptState, word: String) {
        #expect(state.spoken == word)
    }

    @Test func aStepReadsItsWeightRepsAndCountInTheSingularWhereItIsOne() {
        let many = WarmupRoomStep(kilograms: Kilograms(hundredths: 7250), reps: 3, attemptsOut: 12)
        #expect(many.spoken == "72.5 kilograms, 3 reps, at 12 Attempts Out")
        let one = WarmupRoomStep(kilograms: Kilograms(whole: 150), reps: 1, attemptsOut: 1)
        #expect(one.spoken == "150 kilograms, 1 rep, at 1 Attempt Out")
    }

    @Test func aLegalWeightHasNothingToSayUnderIt() {
        #expect(MeetWeightEntry(called: Kilograms(whole: 190), after: nil, rules: .ipf).note(after: (Kilograms(whole: 180), .good)) == nil)
    }
}
