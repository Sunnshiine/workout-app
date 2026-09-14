#if os(macOS)
    import Foundation
    import Testing

    private final class BundleMarker {}

    private func workoutBinary() throws -> URL {
        let candidates = [Bundle(for: BundleMarker.self).bundleURL, Bundle.main.bundleURL]
            .map { $0.deletingLastPathComponent().appendingPathComponent("workout") }
        return try #require(candidates.first { FileManager.default.isExecutableFile(atPath: $0.path) })
    }

    private struct Run {
        let status: Int32
        let stdout: Data
        let stderr: Data

        var json: [String: Any] {
            get throws { try #require(try JSONSerialization.jsonObject(with: stdout) as? [String: Any]) }
        }

        var errorJSON: [String: Any] {
            get throws {
                let envelope = try #require(try JSONSerialization.jsonObject(with: stderr) as? [String: Any])
                return try #require(envelope["error"] as? [String: Any])
            }
        }
    }

    private struct CLI {
        let home: URL
        let binary: URL

        func run(_ arguments: String..., now: String = "2026-05-28T20:26:40Z") throws -> Run {
            let process = Process()
            process.executableURL = binary
            process.arguments = arguments
            process.environment = [
                "WORKOUT_HOME": home.path,
                "WORKOUT_NOW": now,
                "PATH": "/usr/bin:/bin",
                "HOME": ProcessInfo.processInfo.environment["HOME"] ?? NSHomeDirectory()
            ]
            let stdout = Pipe()
            let stderr = Pipe()
            process.standardOutput = stdout
            process.standardError = stderr
            try process.run()
            let out = stdout.fileHandleForReading.readDataToEndOfFile()
            let err = stderr.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            return Run(status: process.terminationStatus, stdout: out, stderr: err)
        }
    }

    private func temporaryHome() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("workout-cli-\(UUID().uuidString)")
        return url
    }

    @Test func theWholeArcRunsAcrossSeparateProcesses() throws {
        let home = try temporaryHome()
        defer { try? FileManager.default.removeItem(at: home) }
        let cli = CLI(home: home, binary: try workoutBinary())

        let initRun = try cli.run("init", "--scenario", "fresh-block")
        #expect(initRun.status == 0)
        #expect(initRun.stderr.isEmpty)
        #expect(try initRun.json["spreadsheetId"] as? String == "FIXTURE")
        #expect(try initRun.json["currentSession"] as? String == "w1d1")
        #expect((try initRun.json["block"] as? [String: Any])?["tabName"] as? String == "Block 27")
        #expect(FileManager.default.fileExists(atPath: home.appendingPathComponent("manifest.json").path))
        #expect(FileManager.default.fileExists(atPath: home.appendingPathComponent("workbook.json").path))
        #expect(FileManager.default.fileExists(atPath: home.appendingPathComponent("store.sqlite").path))

        let status = try cli.run("status")
        #expect(status.status == 0)
        #expect(try status.json["pendingWriteCount"] as? Int == 0)
        #expect(((try status.json["sessions"] as? [[String: Any]]) ?? []).count == 5)

        let session = try cli.run("session")
        #expect(try session.json["id"] as? String == "w1d1")

        let log = try cli.run("log", "w1d1.e0.s0", "185x5@8")
        #expect(log.status == 0)
        #expect(try log.json["pendingWriteCount"] as? Int == 1)
        #expect((try log.json["set"] as? [String: Any])?["loggedAt"] as? String == "2026-05-28T20:26:40Z")

        let before = try cli.run("sheet", "--cell", "K15")
        #expect(try before.json["value"] as? String == "")

        let flush = try cli.run("flush")
        #expect(flush.status == 0)
        #expect(try flush.json["written"] as? Int == 1)
        #expect(try flush.json["remainingPendingWrites"] as? Int == 0)

        let after = try cli.run("sheet", "--cell", "K15")
        #expect(after.status == 0)
        #expect(try after.json["value"] as? String == "185x5@8")

        let sync = try cli.run("sync")
        #expect(sync.status == 0)
        #expect((try sync.json["syncState"] as? [String: Any])?["status"] as? String == "idle")

        let synced = try cli.run("session", "w1d1")
        let exercises = try #require(try synced.json["exercises"] as? [[String: Any]])
        let sets = try #require(exercises[0]["sets"] as? [[String: Any]])
        #expect(sets[0]["state"] as? String == "logged")
        #expect(sets[0]["setLog"] as? String == "185x5@8")
        #expect(sets[1]["state"] as? String == "pending")
    }

    @Test func aBadSetAddressExitsOneWithCandidatesOnStderrAndNothingOnStdout() throws {
        let home = try temporaryHome()
        defer { try? FileManager.default.removeItem(at: home) }
        let cli = CLI(home: home, binary: try workoutBinary())
        _ = try cli.run("init")

        let run = try cli.run("log", "w1d1.e0.s9", "185x5@8")

        #expect(run.status == 1)
        #expect(run.stdout.isEmpty)
        #expect(try run.errorJSON["code"] as? String == "unknown_set")
        #expect(try run.errorJSON["candidates"] as? [String] == ["w1d1.e0.s0", "w1d1.e0.s1", "w1d1.e0.s2"])

        let malformed = try cli.run("log", "day one", "185x5@8")
        #expect(malformed.status == 1)
        #expect(try malformed.errorJSON["code"] as? String == "invalid_address")
    }

    @Test func aMissingHomeExitsThree() throws {
        let cli = CLI(home: try temporaryHome(), binary: try workoutBinary())

        let run = try cli.run("status")

        #expect(run.status == 3)
        #expect(run.stdout.isEmpty)
        #expect(try run.errorJSON["code"] as? String == "environment")
        #expect((try run.errorJSON["message"] as? String)?.contains("workout init") == true)
    }

    @Test func initRefusesAForeignNonEmptyDirectoryAndIsIdempotentOnItsOwn() throws {
        let home = try temporaryHome()
        defer { try? FileManager.default.removeItem(at: home) }
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
        try Data("keep".utf8).write(to: home.appendingPathComponent("notes.txt"))
        let cli = CLI(home: home, binary: try workoutBinary())

        let refused = try cli.run("init")
        #expect(refused.status == 3)
        #expect(FileManager.default.fileExists(atPath: home.appendingPathComponent("notes.txt").path))

        try FileManager.default.removeItem(at: home)
        _ = try cli.run("init")
        _ = try cli.run("log", "w1d1.e0.s0", "185x5@8")
        let again = try cli.run("init")
        #expect(again.status == 0)
        let status = try cli.run("status")
        #expect(try status.json["pendingWriteCount"] as? Int == 0)
        let cell = try cli.run("sheet", "--cell", "K15")
        #expect(try cell.json["value"] as? String == "")
    }

    @Test func usageErrorsExitSixtyFour() throws {
        let cli = CLI(home: try temporaryHome(), binary: try workoutBinary())

        let run = try cli.run("log")

        #expect(run.status == 64)
        #expect(run.stdout.isEmpty)
    }

    @Test func initRefusesAFilePathAndLeavesTheFileAlone() throws {
        let parent = try temporaryHome()
        defer { try? FileManager.default.removeItem(at: parent) }
        try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true)
        let file = parent.appendingPathComponent("important.txt")
        try Data("precious".utf8).write(to: file)
        let cli = CLI(home: file, binary: try workoutBinary())

        let run = try cli.run("init")

        #expect(run.status == 3)
        #expect(try String(contentsOf: file, encoding: .utf8) == "precious")
    }

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

    @Test func aHandEditedWorkbookWithABadCellKeyIsAnEnvironmentErrorNotACrash() throws {
        let home = try temporaryHome()
        defer { try? FileManager.default.removeItem(at: home) }
        let cli = CLI(home: home, binary: try workoutBinary())
        _ = try cli.run("init")
        let workbookURL = home.appendingPathComponent("workbook.json")
        let text = try String(contentsOf: workbookURL, encoding: .utf8)
        try text.replacingOccurrences(of: "\"C12\"", with: "\"12\"").write(to: workbookURL, atomically: true, encoding: .utf8)

        let run = try cli.run("sheet", "--cell", "K15")

        #expect(run.status == 3)
        #expect(run.stdout.isEmpty)
        #expect((try run.errorJSON["message"] as? String)?.contains("A1 references") == true)
    }

    @Test func malformedCellsAndClocksAreRejectedBeforeAnyWork() throws {
        let home = try temporaryHome()
        defer { try? FileManager.default.removeItem(at: home) }
        let cli = CLI(home: home, binary: try workoutBinary())
        _ = try cli.run("init")

        let cell = try cli.run("sheet", "--cell", "K15 ")
        #expect(cell.status == 1)
        #expect(try cell.errorJSON["code"] as? String == "invalid_cell")

        let clock = try cli.run("status", now: "yesterday")
        #expect(clock.status == 3)
        #expect((try clock.errorJSON["message"] as? String)?.contains("WORKOUT_NOW") == true)
    }
#endif
