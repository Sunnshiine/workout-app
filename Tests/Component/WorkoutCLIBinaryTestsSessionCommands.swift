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
