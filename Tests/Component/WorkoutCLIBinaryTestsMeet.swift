#if os(macOS)
    import Foundation
    import Testing

    private func meetCLI() throws -> (cli: CLI, home: URL) {
        let home = try temporaryHome()
        let cli = CLI(home: home, binary: try workoutBinary())
        _ = try cli.run("init")
        return (cli, home)
    }

    private func next(_ run: Run) throws -> [String: Any] {
        try #require(try run.json["next"] as? [String: Any])
    }

    @Test func aHomeWithNoMeetSaysSoAndCannotTick() throws {
        let (cli, home) = try meetCLI()
        defer { try? FileManager.default.removeItem(at: home) }

        let read = try cli.run("meet", "plan")
        #expect(read.status != 0)
        #expect(try read.errorJSON["code"] as? String == "no_meet")
        #expect(try cli.run("meet", "tick").errorJSON["code"] as? String == "no_meet")
    }

    /// Plan to platform to a window that expires, the day the feature exists for, in one home so each
    /// tick reads what the last one saved.
    @Test func theDayRunsFromThePlanThroughAnExpiredWindow() throws {
        let (cli, home) = try meetCLI()
        defer { try? FileManager.default.removeItem(at: home) }
        let lights = "2026-12-05T15:00:00Z"
        let planned = try cli.run(
            "meet",
            "plan",
            "--date",
            "2026-12-05",
            "--federation",
            "ipf",
            "--squat",
            "180,190,197.5",
            "--squat-warmups",
            "60x5@18,100x3@14",
            "--lifters",
            "10"
        )
        #expect(planned.status == 0)
        #expect(try planned.json["rulebook"] as? String == "IPF Technical Rules, effective 1 March 2026")
        #expect(try next(planned)["stage"] as? String == "warmUp")
        #expect(try next(planned)["kilograms"] as? Double == 60)

        #expect(try next(try cli.run("meet", "tick", "--attempts-out", "14"))["kilograms"] as? Double == 100)
        #expect(try next(try cli.run("meet", "tick", "--attempts-out", "0"))["stage"] as? String == "platform")

        let open = try next(try cli.run("meet", "tick", "--good", now: lights))
        #expect(open["stage"] as? String == "window")
        #expect(open["windowState"] as? String == "open")
        #expect(open["secondsLeft"] as? Int == 60)
        #expect(open["tableEntry"] as? Double == 182.5)

        let closing = try next(try cli.run("meet", "tick", now: "2026-12-05T15:00:50Z"))
        #expect(closing["windowState"] as? String == "closing")
        #expect(closing["secondsLeft"] as? Int == 10)

        let expired = try next(try cli.run("meet", "tick", now: "2026-12-05T15:01:00Z"))
        #expect(expired["windowState"] as? String == "expired")
        #expect(expired["kilograms"] as? Double == 190)

        let second = try next(try cli.run("meet", "tick", "--table-entry", now: "2026-12-05T15:01:30Z"))
        #expect(second["stage"] as? String == "attempt")
        #expect(second["ordinal"] as? String == "second")
        #expect(second["kilograms"] as? Double == 182.5)
        #expect(second["attemptsOut"] as? Int == 10)
    }

    @Test func aMeetLeavesTheCoachsSheetUntouched() throws {
        let (cli, home) = try meetCLI()
        defer { try? FileManager.default.removeItem(at: home) }
        let workbook = home.appendingPathComponent("workbook.json")
        let before = try Data(contentsOf: workbook)

        _ = try cli.run("meet", "plan", "--date", "2026-12-05", "--federation", "usapl", "--deadlift", "205,215")
        _ = try cli.run("meet", "tick", "--attempts-out", "0")
        _ = try cli.run("meet", "tick", "--no-lift")
        _ = try cli.run("meet", "tick", "--submit", "205")
        #expect(try cli.run("flush").json["attempted"] as? Int == 0)

        #expect(try Data(contentsOf: workbook) == before)
    }

    @Test func aMeetWithNoThirdDeadliftEndsWithATotalFromWhatWasCalled() throws {
        let (cli, home) = try meetCLI()
        defer { try? FileManager.default.removeItem(at: home) }
        _ = try cli.run(
            "meet",
            "plan",
            "--date",
            "2026-12-05",
            "--federation",
            "ipf",
            "--squat",
            "180",
            "--bench",
            "110",
            "--deadlift",
            "205,215"
        )
        for _ in 0..<2 {
            _ = try cli.run("meet", "tick", "--attempts-out", "0")
            _ = try cli.run("meet", "tick", "--good")
            _ = try cli.run("meet", "tick", "--pass")
        }
        _ = try cli.run("meet", "tick", "--attempts-out", "0")
        _ = try cli.run("meet", "tick", "--good")
        _ = try cli.run("meet", "tick", "--submit", "215")
        _ = try cli.run("meet", "tick", "--attempts-out", "0")
        _ = try cli.run("meet", "tick", "--good")
        let finished = try cli.run("meet", "tick", "--pass")

        #expect(try next(finished)["stage"] as? String == "finished")
        #expect(try finished.json["total"] as? Double == 505)
    }

    @Test func aChangeTheRuleDoesNotAllowIsRefusedWithItsRuleNumber() throws {
        let (cli, home) = try meetCLI()
        defer { try? FileManager.default.removeItem(at: home) }
        _ = try cli.run("meet", "plan", "--date", "2026-12-05", "--federation", "ipf", "--squat", "180,190")
        _ = try cli.run("meet", "tick", "--attempts-out", "0")
        _ = try cli.run("meet", "tick", "--good")
        _ = try cli.run("meet", "tick", "--submit", "190")

        let refused = try cli.run("meet", "tick", "--change", "192.5")
        #expect(refused.status != 0)
        #expect(try refused.errorJSON["code"] as? String == "attempt_change_refused")
    }

    /// The verifier's repro: the phone cannot see the Flight ahead, so a change at 1 Attempt Out goes
    /// in, and the report names the deadline rather than claiming the change is open.
    @Test func anOpenerChangeAtOneAttemptOutGoesInAndNamesItsDeadline() throws {
        let (cli, home) = try meetCLI()
        defer { try? FileManager.default.removeItem(at: home) }
        let deadline = "until 3 minutes before the first round, or 3 Attempts before the Flight ahead of you ends"
        _ = try cli.run("meet", "plan", "--date", "2026-12-05", "--federation", "usapl", "--squat", "180,190,197.5")
        let late = try cli.run("meet", "tick", "--attempts-out", "1")
        #expect(try next(late)["changesLeft"] as? Int == 1)
        #expect(try next(late)["changeDeadline"] as? String == deadline)

        let changed = try cli.run("meet", "tick", "--change", "182.5")
        #expect(changed.status == 0)
        let after = try next(changed)
        #expect(after["kilograms"] as? Double == 182.5)
        #expect(after["changesLeft"] as? Int == 0)
        #expect(after["changeDeadline"] as? String == deadline)
        #expect(after["rule"] as? String == "5.3.1.1")
    }

    @Test func aWeightNoBarLoadsIsRefusedAtThePlan() throws {
        let (cli, home) = try meetCLI()
        defer { try? FileManager.default.removeItem(at: home) }
        _ = try cli.run("meet", "plan", "--date", "2026-12-05", "--federation", "ipf", "--squat", "180")
        _ = try cli.run("meet", "tick", "--attempts-out", "0")
        _ = try cli.run("meet", "tick", "--good")
        #expect(try cli.run("meet", "tick", "--submit", "190.3").errorJSON["code"] as? String == "weight_not_loadable")
    }

    @Test func daysUntilCountsTheFrozenClocksDay() throws {
        let (cli, home) = try meetCLI()
        defer { try? FileManager.default.removeItem(at: home) }
        let run = try cli.run("meet", "plan", "--date", "2026-12-05", "--federation", "ipf", now: "2026-12-04T12:00:00Z")
        #expect(try run.json["daysUntil"] as? Int == 1)
    }
#endif
