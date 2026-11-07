#if os(macOS)
    import Foundation
    import Testing

    @Suite struct WorkoutCLILockScreenTests {
        private func scenario(_ name: String) throws -> (home: URL, cli: CLI) {
            let home = try temporaryHome()
            let cli = CLI(home: home, binary: try workoutBinary())
            _ = try cli.run("init", "--scenario", name)
            return (home, cli)
        }

        private func identity(from cli: CLI) throws -> String {
            let offer = try #require(try cli.run("lock-screen").json["offer"] as? [String: Any])
            return try #require(offer["setIdentity"] as? String)
        }

        @Test func aPressLandsInTheSheetAndTheCardMovesToTheNextSet() throws {
            let (home, cli) = try scenario("full-block")
            defer { try? FileManager.default.removeItem(at: home) }

            let offered = try cli.run("lock-screen")
            #expect(try offered.json["set"] as? String == "w1d1.e0.s0")
            #expect(try offered.json["exercise"] as? String == "Back Squat")
            let offer = try #require(try offered.json["offer"] as? [String: Any])
            let weight = try #require(offer["weight"] as? String)
            let reps = try #require(offer["reps"] as? Int)
            #expect((offer["rpeChoices"] as? [String])?.count == 5)

            let press = try cli.run("rpe-chip", try #require(offer["setIdentity"] as? String), "7")
            #expect(press.status == 0)
            #expect(try press.json["outcome"] as? String == "logged")
            #expect(try press.json["setLog"] as? String == "\(weight)x\(reps)@7")
            #expect(try press.json["pendingWriteCount"] as? Int == 1)

            #expect(try cli.run("flush").json["written"] as? Int == 1)
            #expect(try cli.run("sheet", "--cell", "K18").json["value"] as? String == "\(weight)x\(reps)@7")
            #expect(try cli.run("lock-screen").json["set"] as? String == "w1d1.e0.s1")
        }

        /// The same chip twice is a chalky double tap, and any other chip on that Set is a stale press.
        @Test func aSecondPressNeverWritesAgain() throws {
            let (home, cli) = try scenario("full-block")
            defer { try? FileManager.default.removeItem(at: home) }
            let identity = try identity(from: cli)
            _ = try cli.run("rpe-chip", identity, "7")

            let again = try cli.run("rpe-chip", identity, "7")
            #expect(again.status == 0)
            #expect(try again.json["outcome"] as? String == "sameSetLog")
            #expect(try again.json["pendingWriteCount"] as? Int == 1)

            let other = try cli.run("rpe-chip", identity, "8")
            #expect(other.status != 0)
            #expect(try other.errorJSON["code"] as? String == "rpe_chip_refused")
            #expect(try other.json["pendingWriteCount"] as? Int == 1)
            #expect(try #require(try other.json["reason"] as? String).hasSuffix("holds 237.5×5 @7"))
        }

        @Test func aPressFromAnotherSessionWritesNothingAndSaysWhy() throws {
            let (home, cli) = try scenario("full-block")
            defer { try? FileManager.default.removeItem(at: home) }
            let identity = try identity(from: cli)
            _ = try cli.run("make-current", "w1d2")

            let press = try cli.run("rpe-chip", identity, "7")

            #expect(press.status != 0)
            #expect(try press.json["outcome"] as? String == "notLogged")
            #expect(try press.json["reason"] as? String == "The Session changed. Unlock to log")
            #expect(try press.json["pendingWriteCount"] as? Int == 0)
        }

        /// The worst-case Session opens on an AMRAP, whose reps no card can fill in for the athlete.
        @Test func anAMRAPOffersNoChips() throws {
            let (home, cli) = try scenario("worst-case")
            defer { try? FileManager.default.removeItem(at: home) }

            let offered = try cli.run("lock-screen")

            #expect(try offered.json["set"] is String)
            #expect(try offered.json["offer"] == nil)
        }
    }
#endif
