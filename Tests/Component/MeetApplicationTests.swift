import Foundation
import Testing

@testable import WorkoutTracker

@MainActor
private func application() throws -> WorkoutApplication {
    try WorkoutApplication(
        environment: .inMemory(
            workbook: WorkbookScenario.freshBlock.workbook(),
            now: { Date(timeIntervalSince1970: 1_780_000_000) }
        )
    )
}

private func edit(
    date: String? = nil,
    federation: String? = nil,
    attempts: [String: String] = [:],
    rackHeights: [String: String] = [:],
    warmups: [String: String] = [:],
    fills: Bool = false,
    lifters: Int? = nil,
    seconds: Int? = nil
) -> MeetPlanEdit {
    MeetPlanEdit(
        date: date,
        federation: federation,
        attempts: attempts,
        rackHeights: rackHeights,
        warmupRoomPlans: warmups,
        fillsWarmupRoomPlans: fills,
        liftersInFlight: lifters,
        secondsPerAttempt: seconds
    )
}

@MainActor
private func errorCode(_ body: () throws -> MeetReport) -> String? {
    do {
        _ = try body()
        return nil
    } catch {
        return (error as? ApplicationError)?.code
    }
}

@MainActor
private func plannedApplication() throws -> WorkoutApplication {
    let app = try application()
    _ = try app.meetPlan(edit(date: "2026-12-05", federation: "ipf", attempts: ["squat": "180,190"]))
    return app
}

@Suite("Meet through the facade")
@MainActor
struct MeetApplicationTests {
    @Test func aPhoneWithNoMeetReadsAndTicksNothing() throws {
        let app = try application()
        #expect(errorCode { try app.meetPlan(edit()) } == "no_meet")
        #expect(errorCode { try app.meetTick(.read) } == "no_meet")
    }

    @Test(
        "A new Meet needs both a date and a federation",
        arguments: [edit(date: "2026-12-05"), edit(federation: "ipf"), edit(attempts: ["squat": "180"])]
    )
    func aNewMeetNeedsItsDayAndRules(_ partial: MeetPlanEdit) throws {
        let app = try application()
        #expect(errorCode { try app.meetPlan(partial) } == "invalid_meet_plan")
        #expect(errorCode { try app.meetPlan(edit()) } == "no_meet")
    }

    @Test(
        "Bad text is refused and leaves the Plan as it was",
        arguments: [
            edit(date: "the fifth"),
            edit(date: "2026-02-30"),
            edit(federation: "wrpf"),
            edit(attempts: ["squat": "180,190,197.5,205"]),
            edit(attempts: ["squat": "heavy"]),
            edit(warmups: ["squat": "60x5"]),
            edit(warmups: ["squat": "60x5@0"]),
            edit(lifters: 0),
            edit(seconds: 0)
        ]
    )
    func badTextIsRefused(_ bad: MeetPlanEdit) throws {
        let app = try plannedApplication()
        let before = try app.meetPlan(edit())
        #expect(errorCode { try app.meetPlan(bad) } == "invalid_meet_plan")
        #expect(try app.meetPlan(edit()) == before)
    }

    @Test func anEditReachesTheMeetAlreadyPlanned() throws {
        let app = try plannedApplication()
        let report = try app.meetPlan(
            edit(
                date: "2026-12-06",
                federation: "usapl",
                rackHeights: ["squat": "  14, racks in "],
                warmups: ["bench": "60x5@15,90x1@6"],
                lifters: 12,
                seconds: 45
            )
        )
        #expect(report.date == "2026-12-06")
        #expect(report.federation == "usapl")
        #expect(report.liftersInFlight == 12)
        #expect(report.secondsPerAttempt == 45)
        let squat = try #require(report.lifts.first { $0.lift == "squat" })
        #expect(squat.rackHeights == "14, racks in")
        #expect(squat.attempts.map(\.kilograms) == [180, 190])
        let bench = try #require(report.lifts.first { $0.lift == "bench" })
        #expect(bench.warmupRoomPlan.map(\.attemptsOut) == [15, 6])
    }

    @Test func fillingStartsOnlyALiftWithAnOpenerAndNoTable() throws {
        let app = try plannedApplication()
        _ = try app.meetPlan(edit(attempts: ["deadlift": "205"], warmups: ["deadlift": "100x3@9"]))
        let report = try app.meetPlan(edit(fills: true))
        let tables = Dictionary(uniqueKeysWithValues: report.lifts.map { ($0.lift, $0.warmupRoomPlan.count) })
        #expect(try #require(tables["squat"]) > 1)
        #expect(tables["bench"] == 0)
        #expect(tables["deadlift"] == 1)
    }

    @Test func anEditLeavesAMarkedAttemptAloneAndReplacesWhatFollows() throws {
        let app = try plannedApplication()
        _ = try app.meetTick(.attemptsOut(0))
        _ = try app.meetTick(.good)
        let report = try app.meetPlan(edit(attempts: ["squat": "150,195,205"]))
        let squat = try #require(report.lifts.first { $0.lift == "squat" })
        #expect(squat.attempts.map(\.kilograms) == [180, 195, 205])
        #expect(squat.attempts.map(\.state) == ["good", "planned", "planned"])
    }

    @Test func aGestureTheDayCannotTakeIsRefusedByName() throws {
        let app = try plannedApplication()
        #expect(errorCode { try app.meetTick(.pass) } == "no_attempt_window")
        #expect(errorCode { try app.meetTick(.submit("190")) } == "no_attempt_window")
        #expect(errorCode { try app.meetTick(.change("not a weight")) } == "invalid_meet_plan")

        _ = try app.meetTick(.attemptsOut(0))
        _ = try app.meetTick(.good)
        #expect(errorCode { try app.meetTick(.good) } == "no_attempt_on_deck")
        #expect(errorCode { try app.meetTick(.change("185")) } == "no_attempt_on_deck")
    }

    @Test func aChangeTheRulesLockIsRefusedWithItsRule() throws {
        let app = try plannedApplication()
        _ = try app.meetTick(.attemptsOut(0))
        _ = try app.meetTick(.good)
        _ = try app.meetTick(.submit("190"))
        #expect(errorCode { try app.meetTick(.change("192.5")) } == "attempt_change_refused")
    }
}

@Suite("The Meet Day fixture")
struct MeetDayFixtureTests {
    @Test func theDayHoldsEveryAttemptAndATableForEachLift() throws {
        let meet = try #require(MeetDayFixture.meet())
        for lift in meet.lifts {
            #expect(lift.attempts.count == 3)
            #expect(!lift.warmupRoomPlan.isEmpty)
        }
    }

    @Test func theWorstCaseEndsOnADeadliftOpenerWithNoTable() throws {
        let meet = try #require(MeetDayFixture.worstCase())
        let deadlift = meet.lift(.deadlift)
        #expect(deadlift.attempts.count == 1)
        #expect(deadlift.warmupRoomPlan.isEmpty)
        #expect(meet.lift(.squat).rackHeights.count > 60)
    }
}
