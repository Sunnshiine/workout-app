#if os(macOS)
    import Foundation
    import Testing

    @Suite struct WorkoutCLISessionCommandTests {
        private func freshBlock() throws -> (home: URL, cli: CLI) {
            let home = try temporaryHome()
            let cli = CLI(home: home, binary: try workoutBinary())
            _ = try cli.run("init", "--scenario", "fresh-block")
            return (home, cli)
        }

        @Test func warmupPrintsTheWalkUpToALoggedSetAndWritesNothing() throws {
            let (home, cli) = try freshBlock()
            defer { try? FileManager.default.removeItem(at: home) }
            _ = try cli.run("log", "w1d1.e0.s0", "135x5@8")
            let queued = try cli.run("status").json["pendingWriteCount"] as? Int

            let ramp = try cli.run("warmup", "w1d1.e0.s0")

            #expect(ramp.status == 0)
            #expect(try ramp.json["top"] as? String == "weight")
            #expect(try ramp.json["exercise"] as? String == "Back Squat")
            let steps = try #require(try ramp.json["steps"] as? [[String: Any]])
            let walk = steps.map { step -> [Double] in
                let load = step["load"] as? [String: Any]
                return [load?["reachable"] as? Double ?? -1, Double(step["reps"] as? Int ?? -1)]
            }
            #expect(walk == [[45, 5], [60, 5], [80, 3], [95, 2], [115, 1]])
            #expect((steps[1]["load"] as? [String: Any])?["perSide"] as? [Double] == [5, 2.5])
            #expect(try cli.run("status").json["pendingWriteCount"] as? Int == queued)
        }

        @Test func warmupLetsTheAthletePickWhereTheSetGivesNoTop() throws {
            let (home, cli) = try freshBlock()
            defer { try? FileManager.default.removeItem(at: home) }

            let ramp = try cli.run("warmup", "w1d1.e0.s0")

            #expect(ramp.status == 0)
            #expect(try ramp.json["top"] as? String == "athletePicks")
            #expect((try ramp.json["steps"] as? [Any])?.isEmpty == true)
        }

        @Test func warmupRefusesAnAddressThatIsNotASet() throws {
            let (home, cli) = try freshBlock()
            defer { try? FileManager.default.removeItem(at: home) }

            let ramp = try cli.run("warmup", "nope")

            #expect(ramp.status != 0)
            #expect(try ramp.errorJSON["code"] as? String == "invalid_address")
        }

        @Test func platesChangeWhatTheNextProcessWalksOn() throws {
            let (home, cli) = try freshBlock()
            defer { try? FileManager.default.removeItem(at: home) }
            _ = try cli.run("log", "w1d1.e0.s0", "135x5@8")

            let set = try cli.run("plates", "--bar", "35", "--plates", "45,25,10")

            #expect(set.status == 0)
            #expect(try set.json["barPounds"] as? Int == 35)
            #expect(try set.json["plates"] as? [Double] == [45, 25, 10])
            #expect(try cli.run("plates").json["bar"] as? String == "35")
            let steps = try #require(try cli.run("warmup", "w1d1.e0.s0").json["steps"] as? [[String: Any]])
            #expect(steps.first.flatMap { ($0["load"] as? [String: Any])?["reachable"] as? Double } == 35)
        }

        @Test func platesRefuseABarOrSizeTheAppDoesNotKnow() throws {
            let (home, cli) = try freshBlock()
            defer { try? FileManager.default.removeItem(at: home) }

            let bar = try cli.run("plates", "--bar", "20")
            let size = try cli.run("plates", "--plates", "45,7")

            #expect(try bar.errorJSON["code"] as? String == "invalid_bar")
            #expect(try size.errorJSON["code"] as? String == "invalid_plates")
            #expect(try cli.run("plates").json["bar"] as? String == "45")
        }

        @Test func moveOnMakesBothTapsAndASecondProcessReadsTheNextSession() throws {
            let (home, cli) = try freshBlock()
            defer { try? FileManager.default.removeItem(at: home) }

            let moveOn = try cli.run("move-on")
            #expect(moveOn.status == 0)
            #expect(try moveOn.json["returnedToBlockGrid"] as? Bool == false)
            #expect((try moveOn.json["snapshot"] as? [String: Any])?["currentSession"] as? String == "w1d2")

            let status = try cli.run("status")
            #expect(try status.json["currentSession"] as? String == "w1d2")
            #expect(try status.json["currentSessionIsOverridden"] as? Bool == false)
        }

        @Test func moveOnWithNoAvailableSessionAheadReturnsToTheBlockGrid() throws {
            let (home, cli) = try freshBlock()
            defer { try? FileManager.default.removeItem(at: home) }
            _ = try cli.run("make-current", "w2d2")

            let moveOn = try cli.run("move-on")
            #expect(moveOn.status == 0)
            #expect(try moveOn.json["returnedToBlockGrid"] as? Bool == true)
            #expect((try moveOn.json["snapshot"] as? [String: Any])?["currentSession"] as? String == "w2d2")
        }

        @Test func makeCurrentPinsTheSessionForTheNextProcess() throws {
            let (home, cli) = try freshBlock()
            defer { try? FileManager.default.removeItem(at: home) }

            let made = try cli.run("make-current", "w2d1")
            #expect(made.status == 0)
            #expect(try made.json["currentSession"] as? String == "w2d1")
            #expect(try made.json["currentSessionIsOverridden"] as? Bool == true)

            let status = try cli.run("status")
            #expect(try status.json["currentSession"] as? String == "w2d1")
            #expect(try status.json["currentSessionIsOverridden"] as? Bool == true)
        }

        @Test func makeCurrentOnTheCurrentSessionConverges() throws {
            let (home, cli) = try freshBlock()
            defer { try? FileManager.default.removeItem(at: home) }

            let made = try cli.run("make-current", "w1d1")
            #expect(made.status == 0)
            #expect(try made.json["currentSessionIsOverridden"] as? Bool == false)
        }

        @Test func makeCurrentRefusesAnUnavailableSession() throws {
            let (home, cli) = try freshBlock()
            defer { try? FileManager.default.removeItem(at: home) }

            let made = try cli.run("make-current", "w2d3")
            #expect(made.status == 1)
            #expect(try made.errorJSON["code"] as? String == "session_unavailable")
        }

        /// Without the Pending Set guard, the Clear would queue a delete expecting an empty cell the
        /// coach has since filled, and the flush would exit 4 on the conflict.
        @Test func deleteLogOnAPendingSetQueuesNothingForAStaleView() throws {
            let (home, cli) = try freshBlock()
            defer { try? FileManager.default.removeItem(at: home) }
            try editBlockCells(in: home) { $0["K15"] = "300x5@7" }

            let cleared = try cli.run("delete-log", "w1d1.e0.s0")
            #expect(cleared.status == 0)
            #expect((try cleared.json["set"] as? [String: Any])?["state"] as? String == "pending")
            #expect(try cleared.json["pendingWriteCount"] as? Int == 0)

            #expect(try cli.run("flush").status == 0)
        }

        @Test func deleteLogClearsAFlushedSetLogFromTheSheet() throws {
            let (home, cli) = try freshBlock()
            defer { try? FileManager.default.removeItem(at: home) }
            _ = try cli.run("log", "w1d1.e0.s0", "185x5@8")
            _ = try cli.run("flush")

            let cleared = try cli.run("delete-log", "w1d1.e0.s0")
            #expect(cleared.status == 0)
            #expect((try cleared.json["set"] as? [String: Any])?["state"] as? String == "pending")
            #expect(try cleared.json["pendingWriteCount"] as? Int == 1)

            #expect(try cli.run("flush").status == 0)
            #expect(try cli.run("sheet", "--cell", "K15").json["value"] as? String == "")
        }
    }
#endif
