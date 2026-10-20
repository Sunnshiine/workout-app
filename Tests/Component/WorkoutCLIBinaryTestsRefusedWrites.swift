#if os(macOS)
    import Foundation
    import Testing

    @Test func aConflictedWriteStaysVisibleAndKeepsFlushAndSyncOnExitFour() throws {
        let home = try temporaryHome()
        defer { try? FileManager.default.removeItem(at: home) }
        let cli = CLI(home: home, binary: try workoutBinary())
        _ = try cli.run("init")
        _ = try cli.run("log", "w1d1.e0.s0", "185x5@8")

        let workbookURL = home.appendingPathComponent("workbook.json")
        var workbook = try #require(try JSONSerialization.jsonObject(with: Data(contentsOf: workbookURL)) as? [String: Any])
        var tabs = try #require(workbook["tabs"] as? [String: Any])
        var block = try #require(tabs["Block 27"] as? [String: Any])
        var cells = try #require(block["cells"] as? [String: String])
        cells["K15"] = "200x5@8"
        block["cells"] = cells
        tabs["Block 27"] = block
        workbook["tabs"] = tabs
        try JSONSerialization.data(withJSONObject: workbook).write(to: workbookURL)

        let first = try cli.run("flush")
        #expect(first.status == 4)
        #expect(try first.errorJSON["code"] as? String == "write_conflict")
        #expect(try first.json["written"] as? Int == 0)
        #expect(((try first.json["conflictedWrites"] as? [String]) ?? []).first?.hasPrefix("Back Squat:") == true)

        let second = try cli.run("flush")
        #expect(second.status == 4)
        #expect(try second.json["attempted"] as? Int == 0)
        #expect(try second.json["remainingPendingWrites"] as? Int == 1)
        #expect(((try second.json["conflictedWrites"] as? [String]) ?? []).count == 1)

        let sync = try cli.run("sync")
        #expect(sync.status == 4)
        #expect(try sync.errorJSON["code"] as? String == "sync_conflict")
        #expect(try sync.json["pendingWriteCount"] as? Int == 1)
    }

    /// A sync names each refused write once on stderr, though the report carries a refusal both as
    /// a conflicted write and as the outcome's message (#979). Two Sets refused for the same reason
    /// stay two lines. The refusal is #768's: a second `Day 1` header in Week 1 names the Day as
    /// repeated, not as missing.
    @Test func aSyncNamesEachRefusedWriteOnce() throws {
        let home = try temporaryHome()
        defer { try? FileManager.default.removeItem(at: home) }
        let cli = CLI(home: home, binary: try workoutBinary())
        _ = try cli.run("init")
        _ = try cli.run("log", "w1d1.e0.s0", "185x5@8")
        _ = try cli.run("log", "w1d1.e0.s1", "185x5@8")
        try editBlockCells(in: home) { $0["S12"] = "Day 1" }

        let sync = try cli.run("sync")
        let refusal = "Back Squat: Day 1 has more than one header in the sheet"
        #expect(sync.status == 4)
        #expect(try sync.errorJSON["code"] as? String == "sync_conflict")
        #expect(try sync.errorJSON["message"] as? String == "\(refusal)\n\(refusal)")
        #expect(try sync.json["conflictedWrites"] as? [String] == [refusal, refusal])
    }

    /// A write refused by an earlier sync stays conflicted, so a sync that refuses another names
    /// both on stderr, once each, though its outcome carries only the new refusal.
    @Test func aSyncNamesAnEarlierRefusalAlongsideItsOwn() throws {
        let home = try temporaryHome()
        defer { try? FileManager.default.removeItem(at: home) }
        let cli = CLI(home: home, binary: try workoutBinary())
        _ = try cli.run("init")
        _ = try cli.run("log", "w1d1.e0.s0", "185x5@8")
        _ = try cli.run("flush")
        _ = try cli.run("sync")
        _ = try cli.run("log", "w1d1.e0.s0", "205x3@9")
        try editBlockCells(in: home) { $0["K15"] = "coach edited" }
        let earlier = try cli.run("sync")
        #expect(try (earlier.json["conflictedWrites"] as? [String])?.count == 1)
        let earlierRefusal = try #require(try earlier.errorJSON["message"] as? String)

        _ = try cli.run("log", "w1d1.e0.s1", "185x5@8")
        try editBlockCells(in: home) { $0["S12"] = "Day 1" }
        let sync = try cli.run("sync")
        let newRefusal = "Back Squat: Day 1 has more than one header in the sheet"
        let outcome = try #require(try sync.json["syncOutcome"] as? [String: Any])
        #expect(sync.status == 4)
        #expect(outcome["messages"] as? [String] == [newRefusal])
        #expect(try sync.errorJSON["message"] as? String == "\(earlierRefusal)\n\(newRefusal)")
    }

    /// The reason `syncOutcome` exists. Both halves exit 4 and both leave the athlete something to
    /// do, and the only thing telling them apart is `status`.
    @Test func aParseWarningAndARefusedWriteReachTheWireUnderDifferentStatuses() throws {
        let warningHome = try temporaryHome()
        defer { try? FileManager.default.removeItem(at: warningHome) }
        let warningCLI = CLI(home: warningHome, binary: try workoutBinary())
        _ = try warningCLI.run("init")
        let dayHeader = try Regex(#"^Day \d+$"#)
        try editBlockCells(in: warningHome) { cells in
            for key in cells.filter({ (try? dayHeader.wholeMatch(in: $0.value)) != nil }).keys {
                cells[key] = nil
            }
        }

        let warned = try warningCLI.run("sync")
        let warnedOutcome = try #require(try warned.json["syncOutcome"] as? [String: Any])
        #expect(warned.status == 4)
        #expect(warnedOutcome["status"] as? String == "parseWarnings")
        let warnings = try #require(warnedOutcome["messages"] as? [String])
        #expect(warnings.isEmpty == false)
        #expect(try warned.errorJSON["message"] as? String == warnings.joined(separator: "\n"))

        let refusedHome = try temporaryHome()
        defer { try? FileManager.default.removeItem(at: refusedHome) }
        let refusedCLI = CLI(home: refusedHome, binary: try workoutBinary())
        _ = try refusedCLI.run("init")
        _ = try refusedCLI.run("log", "w1d1.e0.s0", "185x5@8")
        _ = try refusedCLI.run("flush")
        _ = try refusedCLI.run("sync")
        _ = try refusedCLI.run("log", "w1d1.e0.s0", "205x3@9")
        try editBlockCells(in: refusedHome) { cells in cells["K15"] = "coach edited" }

        let refused = try refusedCLI.run("sync")
        let refusedOutcome = try #require(try refused.json["syncOutcome"] as? [String: Any])
        #expect(refused.status == 4)
        #expect(refusedOutcome["status"] as? String == "writesRefused")
    }
#endif
