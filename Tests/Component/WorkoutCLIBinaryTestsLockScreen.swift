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

        /// The card names the Exercise, the weight the stage holds, and the coach's words, and the
        /// Set logs once the athlete has chosen both Reps and RPE.
        @Test func aPressLandsInTheSheetAndTheCardMovesToTheNextSet() throws {
            let (home, cli) = try scenario("full-block")
            defer { try? FileManager.default.removeItem(at: home) }

            let offered = try cli.run("lock-screen")
            #expect(try offered.json["set"] as? String == "w1d1.e0.s0")
            #expect(try offered.json["exercise"] as? String == "Back Squat")
            #expect(try offered.json["prescribedReps"] as? String == "5")
            #expect(try offered.json["prescribedLoad"] as? String == "RPE6")
            #expect(try offered.json["cadence"] == nil)
            #expect(try offered.json["coachNote"] as? String == "Brace hard off the floor, controlled descent.")
            let weight = try #require(try offered.json["weight"] as? String)
            let offer = try #require(try offered.json["offer"] as? [String: Any])
            #expect(offer["repChoices"] as? [Int] == [3, 4, 5, 6, 7])
            #expect(offer["prescribedReps"] as? [Int] == [5])
            #expect((offer["rpeChoices"] as? [String])?.count == 5)
            #expect(offer["prescribedRPE"] as? String == "6")

            let press = try cli.run("rpe-chip", try #require(offer["setIdentity"] as? String), "6", "7")
            #expect(press.status == 0)
            #expect(try press.json["outcome"] as? String == "logged")
            #expect(try press.json["setLog"] as? String == "\(weight)x6@7")
            #expect(try press.json["pendingWriteCount"] as? Int == 1)

            #expect(try cli.run("flush").json["written"] as? Int == 1)
            #expect(try cli.run("sheet", "--cell", "K18").json["value"] as? String == "\(weight)x6@7")
            #expect(try cli.run("lock-screen").json["set"] as? String == "w1d1.e0.s1")
        }

        /// The same chips twice are a chalky double tap, and any other chips on that Set are a stale press.
        @Test func aSecondPressNeverWritesAgain() throws {
            let (home, cli) = try scenario("full-block")
            defer { try? FileManager.default.removeItem(at: home) }
            let identity = try identity(from: cli)
            _ = try cli.run("rpe-chip", identity, "5", "7")

            let again = try cli.run("rpe-chip", identity, "5", "7")
            #expect(again.status == 0)
            #expect(try again.json["outcome"] as? String == "sameSetLog")
            #expect(try again.json["pendingWriteCount"] as? Int == 1)

            for (reps, rpe) in [("5", "8"), ("6", "7")] {
                let other = try cli.run("rpe-chip", identity, reps, rpe)
                #expect(other.status != 0)
                #expect(try other.errorJSON["code"] as? String == "rpe_chip_refused")
                #expect(try other.json["pendingWriteCount"] as? Int == 1)
                #expect(try #require(try other.json["reason"] as? String).hasSuffix("holds 237.5×5 @7"))
            }
        }

        @Test func aPressFromAnotherSessionWritesNothingAndSaysWhy() throws {
            let (home, cli) = try scenario("full-block")
            defer { try? FileManager.default.removeItem(at: home) }
            let identity = try identity(from: cli)
            _ = try cli.run("make-current", "w1d2")

            let press = try cli.run("rpe-chip", identity, "5", "7")

            #expect(press.status != 0)
            #expect(try press.json["outcome"] as? String == "notLogged")
            #expect(try press.json["reason"] as? String == "The Session changed. Open to log")
            #expect(try press.json["pendingWriteCount"] as? Int == 0)
        }

        /// The athlete chooses the Reps, so an AMRAP logs from the Lock Screen with no Rep the card
        /// ticks.
        @Test func anAMRAPOffersRepsChipsWithNoTick() throws {
            let (home, cli) = try scenario("worst-case")
            defer { try? FileManager.default.removeItem(at: home) }

            let offered = try cli.run("lock-screen")

            #expect(try offered.json["prescribedReps"] as? String == "AMRAP")
            let offer = try #require(try offered.json["offer"] as? [String: Any])
            #expect(offer["repChoices"] as? [Int] == [3, 4, 5, 6, 7])
            #expect(offer["prescribedReps"] as? [Int] == [])
        }

        /// An Exercise that opens on a hold offers the Start the stage's card has, in the mic's place.
        @Test func anExerciseThatOpensOnAHoldOffersItsStart() throws {
            let (home, cli) = try scenario("full-block")
            defer { try? FileManager.default.removeItem(at: home) }
            for set in 0..<3 {
                _ = try cli.run("log", "w1d1.e0.s\(set)", "235x5@7")
            }

            let offered = try cli.run("lock-screen")

            #expect(try offered.json["set"] as? String == "w1d1.e1.s0")
            #expect(try offered.json["exercise"] as? String == "BB RDL")
            #expect(try offered.json["cadence"] as? String == "2-3:1:0")
            #expect(try offered.json["coachNote"] as? String == "Start w/ 10 sec hold, proceed to rep range.")
            #expect(try offered.json["start"] as? String == "10 s hold")
        }
    }
#endif
