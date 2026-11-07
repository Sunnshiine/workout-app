import Foundation
import Testing

@testable import WorkoutTracker

private let start = Date(timeIntervalSinceReferenceDate: 1_000)

private func meet(
    federation: Federation = .ipf,
    squat: [Int] = [180, 190, 197],
    bench: [Int] = [],
    deadlift: [Int] = []
) throws -> Meet {
    var meet = Meet(date: try #require(MeetDate("2026-12-05")), federation: federation)
    let lines: [(MainLift, [Int])] = [(.squat, squat), (.bench, bench), (.deadlift, deadlift)]
    for (lift, weights) in lines {
        meet.editLift(lift) { edit in
            for (index, weight) in weights.enumerated() {
                edit.enter(Kilograms(whole: weight), at: AttemptOrdinal(rawValue: index) ?? .third)
            }
        }
    }
    return meet
}

private func deck(_ meet: Meet, at now: Date = start) throws -> AttemptOnDeck {
    guard case .onDeck(let deck) = meet.stage(at: now) else {
        Issue.record("Expected an Attempt on deck, found \(meet.stage(at: now))")
        throw MeetRefusal.noAttemptOnDeck
    }
    return deck
}

private func window(_ meet: Meet, at now: Date = start) throws -> OpenAttemptWindow {
    guard case .window(let window) = meet.stage(at: now) else {
        Issue.record("Expected an Attempt Window, found \(meet.stage(at: now))")
        throw MeetRefusal.noWindowOpen
    }
    return window
}

@Suite("A Meet's day")
struct MeetDayTests {
    @Test("With no Attempt anywhere the day has nothing to run")
    func noAttemptsMeansNothingToRun() throws {
        #expect(try meet(squat: []).stage(at: start) == .noAttempts)
    }

    @Test("A Main Lift with no Attempt is not on the day, so a bench-only Meet opens on bench")
    func aLiftWithNoAttemptIsOffTheDay() throws {
        let bench = try deck(try meet(squat: [], bench: [100]))
        #expect(bench.lift == .bench)
        #expect(bench.liftFinished == nil)
    }

    @Test("A new lift starts at its plan's first step, or at one round of the Flight with no plan")
    func aNewLiftStartsWhereItsPlanStarts() throws {
        var day = try meet()
        #expect(try deck(day).attemptsOut == Meet.defaultLiftersInFlight)
        day.editLift(.squat) { $0.setWarmupRoomPlan([WarmupRoomStep(kilograms: Kilograms(whole: 60), reps: 5, attemptsOut: 18)]) }
        #expect(try deck(day).attemptsOut == 18)
    }

    @Test("A mark starts the next Attempt's window at that instant and counts one round of the Flight")
    func aMarkStartsTheWindow() throws {
        var day = try meet()
        day.liftersInFlight = 9
        try day.mark(.good, at: start)
        let open = try window(day)
        #expect(open.reading == .open(secondsLeft: 60))
        #expect(open.ordinal == .second)
        #expect(open.marked == Kilograms(whole: 180))
        #expect(open.planned == Kilograms(whole: 190))
        #expect(day.countedAttemptsOut == 9)
        #expect(day.lift(.squat).attempts[0].state == .good)
    }

    @Test("The window's table entry follows the mark", arguments: [(AttemptResult.good, 18250), (.noLift, 18000)])
    func theTableEntryFollowsTheMark(result: AttemptResult, hundredths: Int) throws {
        var day = try meet()
        try day.mark(result, at: start)
        #expect(try window(day).tableEntry == Kilograms(hundredths: hundredths))
    }

    @Test("A second not called yet opens the same window, with no planned number")
    func aBlankSecondStillOpensTheWindow() throws {
        var day = try meet(squat: [180])
        try day.mark(.good, at: start)
        #expect(try window(day).planned == nil)
        try day.submitNext(Kilograms(whole: 190), at: start)
        let onDeck = try deck(day)
        #expect(onDeck.ordinal == .second)
        #expect(onDeck.kilograms == Kilograms(whole: 190))
        #expect(day.lift(.squat).attempts[1].state == .submitted)
    }

    @Test("An expired window reads the truth at any later time, and the athlete's answer still closes it")
    func anExpiredWindowWaitsForAnAnswer() throws {
        var day = try meet()
        try day.mark(.good, at: start)
        let later = start.addingTimeInterval(600)
        #expect(try window(day, at: later).reading == .expired)
        try day.submitNext(try window(day, at: later).tableEntry, at: later)
        #expect(try deck(day, at: later).kilograms == Kilograms(hundredths: 18250))
        #expect(day.attemptWindow == nil)
    }

    @Test("Whichever weight goes in, the next Attempt becomes that weight, submitted")
    func eitherAnswerSubmits() throws {
        for weight in [Kilograms(hundredths: 18250), Kilograms(whole: 195)] {
            var day = try meet()
            try day.mark(.good, at: start)
            try day.submitNext(weight, at: start)
            #expect(day.lift(.squat).attempts[1] == Attempt(kilograms: weight, state: .submitted))
        }
    }

    @Test("No weight goes in that no bar can load")
    func anUnloadableWeightIsRefused() throws {
        var day = try meet()
        try day.mark(.good, at: start)
        #expect(throws: MeetRefusal.weightNotLoadable(Kilograms(hundredths: 18130))) {
            try day.submitNext(Kilograms(hundredths: 18130), at: start)
        }
        #expect(day.attemptWindow != nil)
    }

    @Test("After the third Attempt no window opens, and the next lift's opener is on deck")
    func theThirdOpensNoWindow() throws {
        var day = try meet(bench: [100, 105, 110])
        for weight in [190, 197] {
            try day.mark(.good, at: start)
            try day.submitNext(Kilograms(whole: weight), at: start)
        }
        try day.mark(.noLift, at: start)
        #expect(day.attemptWindow == nil)
        let onDeck = try deck(day)
        #expect(onDeck.lift == .bench)
        #expect(onDeck.ordinal == .opener)
        #expect(onDeck.liftFinished == .squat)
        #expect(day.countedAttemptsOut == nil)
    }

    @Test("Passing a third deadlift ends the day with no third, and the total still counts")
    func passingLeavesNoThird() throws {
        var day = try meet(squat: [], bench: [100], deadlift: [200, 210, 220])
        try day.mark(.good, at: start)
        try day.submitNext(Kilograms(whole: 105), at: start)
        try day.mark(.good, at: start)
        try day.submitNext(Kilograms(whole: 110), at: start)
        try day.mark(.good, at: start)
        try day.mark(.good, at: start)
        try day.submitNext(Kilograms(whole: 210), at: start)
        try day.mark(.good, at: start)
        #expect(try window(day).ordinal == .third)
        try day.pass()
        #expect(day.stage(at: start) == .finished)
        #expect(day.lift(.deadlift).attempts.count == 2)
        #expect(day.total == Kilograms(whole: 320))
    }

    @Test("A lift with no good lift leaves no total")
    func noGoodLiftLeavesNoTotal() throws {
        var day = try meet(squat: [180], bench: [100])
        try day.mark(.noLift, at: start)
        try day.pass()
        try day.mark(.good, at: start)
        try day.pass()
        #expect(day.stage(at: start) == .finished)
        #expect(day.total == nil)
    }

    @Test("The total is each lift's best good lift, not its last")
    func theTotalTakesTheBest() throws {
        var day = try meet(squat: [180, 190], bench: [100])
        try day.mark(.good, at: start)
        try day.submitNext(Kilograms(whole: 190), at: start)
        try day.mark(.noLift, at: start)
        try day.pass()
        try day.mark(.good, at: start)
        try day.pass()
        #expect(day.total == Kilograms(whole: 280))
    }

    @Test("Attempts Out never reads below zero, and zero is the platform")
    func attemptsOutStopsAtZero() throws {
        var day = try meet()
        day.setAttemptsOut(-3)
        #expect(try deck(day).attemptsOut == 0)
        #expect(try deck(day).cue == .platform(Kilograms(whole: 180)))
    }

    @Test("A warm-up plan applies to the opener alone")
    func aPlanAppliesToTheOpener() throws {
        var day = try meet()
        let step = WarmupRoomStep(kilograms: Kilograms(whole: 60), reps: 5, attemptsOut: 3)
        day.editLift(.squat) { $0.setWarmupRoomPlan([step]) }
        day.setAttemptsOut(5)
        #expect(try deck(day).cue == .warmUp(step, attemptsUntil: 2, secondsUntil: 120))
        try day.mark(.good, at: start)
        try day.submitNext(Kilograms(whole: 190), at: start)
        day.setAttemptsOut(5)
        #expect(try deck(day).cue == .attempt(Kilograms(whole: 190), attemptsOut: 5, secondsUntil: 300))
    }

    @Test("IPF 6.1(i): an opener takes one change, then none")
    func anOpenerTakesOneChange() throws {
        var day = try meet()
        #expect(try deck(day).allowance == .changesLeft(1, rule: "6.1(i)"))
        try day.changeOnDeck(to: Kilograms(hundredths: 18250), at: start)
        #expect(try deck(day).kilograms == Kilograms(hundredths: 18250))
        #expect(try deck(day).allowance == .changesLeft(0, rule: "6.1(i)"))
        #expect(throws: MeetRefusal.changeNotAllowed(rule: "6.1(i)")) {
            try day.changeOnDeck(to: Kilograms(whole: 185), at: start)
        }
    }

    @Test("IPF 6.1(k): a second squat is locked once it is in")
    func aSecondIsLocked() throws {
        var day = try meet()
        try day.mark(.good, at: start)
        try day.submitNext(Kilograms(whole: 190), at: start)
        #expect(try deck(day).allowance == .locked(rule: "6.1(k)"))
    }

    @Test("USAPL 5.3.17.1: a third deadlift takes two changes, and a third squat none")
    func aThirdDeadliftTakesTwoChanges() throws {
        var day = try meet(federation: .usapl, squat: [180, 190, 197], deadlift: [200, 210, 220])
        for _ in 0..<2 {
            try day.mark(.good, at: start)
            try day.submitNext(Kilograms(whole: 197), at: start)
        }
        #expect(try deck(day).allowance == .locked(rule: "5.3.17"))
        try day.mark(.good, at: start)
        for _ in 0..<2 {
            try day.mark(.good, at: start)
            try day.submitNext(Kilograms(whole: 220), at: start)
        }
        #expect(try deck(day).allowance == .changesLeft(2, rule: "5.3.17.1"))
        try day.changeOnDeck(to: Kilograms(whole: 222), at: start)
        try day.changeOnDeck(to: Kilograms(whole: 225), at: start)
        #expect(try deck(day).allowance == .changesLeft(0, rule: "5.3.17.1"))
    }

    @Test("A gesture the stage cannot take is refused and changes nothing")
    func aRefusedGestureChangesNothing() throws {
        var day = try meet()
        let before = day
        #expect(throws: MeetRefusal.noWindowOpen) { try day.submitNext(Kilograms(whole: 190), at: start) }
        #expect(throws: MeetRefusal.noWindowOpen) { try day.pass() }
        #expect(day == before)
        try day.mark(.good, at: start)
        #expect(throws: MeetRefusal.noAttemptOnDeck) { try day.mark(.good, at: start) }
    }

    @Test("A Meet survives a JSON round trip, a running window included")
    func aMeetSurvivesJSON() throws {
        var day = try meet()
        try day.mark(.good, at: start)
        let record = MeetRecord(meet: day, beforeLastGesture: try meet())
        let data = try JSONEncoder().encode(record)
        #expect(try JSONDecoder().decode(MeetRecord.self, from: data) == record)
    }
}

@Suite("Entering a Plan")
struct MeetPlanEntryTests {
    @Test("Only the next blank place takes a new Attempt, so a third never has no second")
    func onlyTheNextPlaceTakesAnAttempt() throws {
        var day = try meet(squat: [180])
        day.editLift(.squat) { $0.enter(Kilograms(whole: 200), at: .third) }
        #expect(day.lift(.squat).attempts.count == 1)
        day.editLift(.squat) { $0.enter(Kilograms(whole: 190), at: .second) }
        #expect(day.lift(.squat).attempts.count == 2)
    }

    @Test("Clearing an Attempt clears the ones after it")
    func clearingDropsWhatFollows() throws {
        var day = try meet()
        day.editLift(.squat) { $0.clear(from: .second) }
        #expect(day.lift(.squat).attempts.map(\.kilograms) == [Kilograms(whole: 180)])
    }

    @Test("A marked Attempt stays on the record")
    func aMarkedAttemptStays() throws {
        var day = try meet()
        try day.mark(.good, at: start)
        day.editLift(.squat) { $0.clear(from: .opener) }
        #expect(day.lift(.squat).attempts.count == 3)
    }

    @Test("A plan reads from the most Attempts Out to the fewest, however it was entered")
    func aPlanKeepsItsOrder() throws {
        var day = try meet()
        let low = WarmupRoomStep(kilograms: Kilograms(whole: 140), reps: 3, attemptsOut: 6)
        let high = WarmupRoomStep(kilograms: Kilograms(whole: 60), reps: 5, attemptsOut: 18)
        day.editLift(.squat) { $0.setWarmupRoomPlan([low, high]) }
        #expect(day.lift(.squat).warmupRoomPlan == [high, low])
    }
}
