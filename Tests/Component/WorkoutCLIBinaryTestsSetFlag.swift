#if os(macOS)
    import Foundation
    import Testing

    @Test func aFlagFlushesToTheCellNoteAndTheCellAnswersWithBoth() throws {
        let home = try temporaryHome()
        defer { try? FileManager.default.removeItem(at: home) }
        let cli = CLI(home: home, binary: try workoutBinary())
        _ = try cli.run("init", "--scenario", "fresh-block")
        _ = try cli.run("log", "w1d1.e0.s0", "185x5@8")

        let flagged = try cli.run("flag", "w1d1.e0.s0", "pain", "left hip")
        #expect(flagged.status == 0)
        let set = try #require(try flagged.json["set"] as? [String: Any])
        let flags = try #require(set["setFlags"] as? [[String: Any]])
        #expect(flags.map { $0["standing"] as? String } == ["unsynced"])
        #expect(flags.map { $0["line"] as? String } == ["Set 1 · Pain: left hip"])

        let flush = try cli.run("flush")
        #expect(flush.status == 0)
        #expect(try flush.json["written"] as? Int == 2)

        let cell = try cli.run("sheet", "--cell", "K15")
        #expect(try cell.json["value"] as? String == "185x5@8")
        #expect(try cell.json["cellNote"] as? String == "Set 1 · Pain: left hip")
    }

    @Test func aSyncInAnotherProcessReadsTheFlagBackFromTheSheet() throws {
        let home = try temporaryHome()
        defer { try? FileManager.default.removeItem(at: home) }
        let cli = CLI(home: home, binary: try workoutBinary())
        _ = try cli.run("init", "--scenario", "fresh-block")
        _ = try cli.run("flag", "w1d1.e0.s1", "technique")
        _ = try cli.run("flush")

        #expect(try cli.run("sync").status == 0)
        let session = try cli.run("session", "w1d1")
        let exercises = try #require(try session.json["exercises"] as? [[String: Any]])
        let sets = try #require(exercises.first?["sets"] as? [[String: Any]])

        #expect(sets[0]["setFlags"] == nil)
        let flags = try #require(sets[1]["setFlags"] as? [[String: Any]])
        #expect(flags.map { $0["kind"] as? String } == ["technique"])
        #expect(flags.map { $0["standing"] as? String } == ["landed"])
    }

    @Test func otherWithNoWordsExitsOneAndQueuesNothing() throws {
        let home = try temporaryHome()
        defer { try? FileManager.default.removeItem(at: home) }
        let cli = CLI(home: home, binary: try workoutBinary())
        _ = try cli.run("init", "--scenario", "fresh-block")

        let refused = try cli.run("flag", "w1d1.e0.s0", "other")

        #expect(refused.status == 1)
        #expect(try refused.errorJSON["code"] as? String == "invalid_set_flag")
        #expect(try cli.run("flush").json["attempted"] as? Int == 0)
    }

    @Test func aFlagWithNoWritableRowKeepsFlushAndSyncOnExitFour() throws {
        let home = try temporaryHome()
        defer { try? FileManager.default.removeItem(at: home) }
        let cli = CLI(home: home, binary: try workoutBinary())
        _ = try cli.run("init", "--scenario", "fresh-block")
        _ = try cli.run("flag", "w1d1.e1.s0", "pain")
        try hideRowsBelowTheRDLsCoachNote(in: home)

        let flush = try cli.run("flush")
        #expect(flush.status == 4)
        #expect(try flush.errorJSON["code"] as? String == "write_conflict")
        #expect(try flush.json["remainingPendingWrites"] as? Int == 1)

        let sync = try cli.run("sync")
        #expect(sync.status == 4)
        #expect(try sync.errorJSON["code"] as? String == "sync_conflict")
    }

    private func hideRowsBelowTheRDLsCoachNote(in home: URL) throws {
        let workbookURL = home.appendingPathComponent("workbook.json")
        var workbook = try #require(try JSONSerialization.jsonObject(with: Data(contentsOf: workbookURL)) as? [String: Any])
        var tabs = try #require(workbook["tabs"] as? [String: Any])
        var block = try #require(tabs["Block 27"] as? [String: Any])
        block["hiddenRows"] = Dictionary(
            uniqueKeysWithValues: (20...36).map { (String($0), ["hiddenByUser": true, "hiddenByFilter": false]) }
        )
        tabs["Block 27"] = block
        workbook["tabs"] = tabs
        try JSONSerialization.data(withJSONObject: workbook).write(to: workbookURL)
    }
#endif
