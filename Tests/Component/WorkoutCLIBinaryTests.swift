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
            var environment = [
                "WORKOUT_HOME": home.path,
                "WORKOUT_NOW": now,
                "PATH": "/usr/bin:/bin",
                "HOME": ProcessInfo.processInfo.environment["HOME"] ?? NSHomeDirectory()
            ]
            // Under `swift test --enable-code-coverage` the child is instrumented too. Point its
            // profile next to the test runner's so SwiftPM merges it and the CLI counts as covered.
            if let profile = ProcessInfo.processInfo.environment["LLVM_PROFILE_FILE"] {
                environment["LLVM_PROFILE_FILE"] =
                    URL(fileURLWithPath: profile)
                    .deletingLastPathComponent().appendingPathComponent("workout-cli-%p.profraw").path
            }
            process.environment = environment
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

    private func editBlockCells(in home: URL, _ transform: (inout [String: String]) -> Void) throws {
        let workbookURL = home.appendingPathComponent("workbook.json")
        var workbook = try #require(try JSONSerialization.jsonObject(with: Data(contentsOf: workbookURL)) as? [String: Any])
        var tabs = try #require(workbook["tabs"] as? [String: Any])
        var block = try #require(tabs["Block 27"] as? [String: Any])
        var cells = try #require(block["cells"] as? [String: String])
        transform(&cells)
        block["cells"] = cells
        tabs["Block 27"] = block
        workbook["tabs"] = tabs
        try JSONSerialization.data(withJSONObject: workbook).write(to: workbookURL)
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
        #expect((try sync.json["syncOutcome"] as? [String: Any])?["status"] as? String == "clear")

        let synced = try cli.run("session", "w1d1")
        let exercises = try #require(try synced.json["exercises"] as? [[String: Any]])
        let sets = try #require(exercises[0]["sets"] as? [[String: Any]])
        #expect(sets[0]["state"] as? String == "logged")
        #expect(sets[0]["setLog"] as? String == "185x5@8")
        #expect(sets[1]["state"] as? String == "pending")
    }

    @Test func aSpokenSetLandsLikeALoggedOneAndARejectedOneExitsOne() throws {
        let home = try temporaryHome()
        defer { try? FileManager.default.removeItem(at: home) }
        let cli = CLI(home: home, binary: try workoutBinary())
        _ = try cli.run("init", "--scenario", "fresh-block")

        let missingWeight = try cli.run("say", "w1d1.e0.s0", "RPE 9")
        #expect(missingWeight.status == 0)
        #expect(missingWeight.stderr.isEmpty)
        #expect(try missingWeight.json["outcome"] as? String == "missingValues")
        #expect(try missingWeight.json["missing"] as? [String] == ["weight"])
        #expect(try missingWeight.json["pendingWriteCount"] as? Int == 0)

        let logged = try cli.run("say", "w1d1.e0.s0", "185 for 5 at 8")
        #expect(logged.status == 0)
        #expect(try logged.json["heard"] as? String == "185 for 5 at 8")
        #expect(try logged.json["outcome"] as? String == "logged")
        #expect(try logged.json["setLog"] as? String == "185x5@8")
        #expect(try logged.json["pendingWriteCount"] as? Int == 1)
        #expect((try logged.json["set"] as? [String: Any])?["state"] as? String == "logged")

        let rejected = try cli.run("say", "w1d1.e0.s1", "100 kilos for 5")
        #expect(rejected.status == 1)
        #expect(try rejected.json["outcome"] as? String == "rejected")
        #expect((try rejected.json["rejection"] as? [String: Any])?["reason"] as? String == "kilograms")
        #expect(try rejected.errorJSON["code"] as? String == "spoken_set_rejected")

        let skipped = try cli.run("say", "w1d1.e0.s1", "skip")
        #expect(skipped.status == 0)
        #expect(try skipped.json["outcome"] as? String == "skipped")

        #expect(try cli.run("flush").status == 0)
        #expect(try cli.run("sheet", "--cell", "K15").json["value"] as? String == "185x5@8, skip")
    }

    @available(macOS 26, *)
    @Test func aRecordingThatIsNotAudioExitsOneBeforeAnythingListens() throws {
        let home = try temporaryHome()
        defer { try? FileManager.default.removeItem(at: home) }
        let cli = CLI(home: home, binary: try workoutBinary())
        _ = try cli.run("init")
        let missing = home.appendingPathComponent("no-such-set.aiff").path

        let run = try cli.run("hear", "w1d1.e0.s0", missing)

        #expect(run.status == 1)
        #expect(run.stdout.isEmpty)
        #expect(try run.errorJSON["code"] as? String == "unreadable_recording")
        #expect(try cli.run("status").json["pendingWriteCount"] as? Int == 0)
    }

    /// Runs Apple's speech model on a Mac that has its en-US assets, so CI, which may not, skips it.
    @available(macOS 26, *)
    @Test(.enabled(if: ProcessInfo.processInfo.environment["WORKOUT_REAL_SPEECH"] == "1"))
    func aSpokenRecordingLandsInTheSheetThroughTheMicsSpeechModel() throws {
        let home = try temporaryHome()
        defer { try? FileManager.default.removeItem(at: home) }
        let cli = CLI(home: home, binary: try workoutBinary())
        _ = try cli.run("init", "--scenario", "fresh-block")
        let recording = home.appendingPathComponent("set.aiff")
        let say = try Process.run(URL(fileURLWithPath: "/usr/bin/say"), arguments: ["-o", recording.path, "185 for 5 at 8"])
        say.waitUntilExit()

        let heard = try cli.run("hear", "w1d1.e0.s0", recording.path)

        #expect(heard.status == 0)
        let candidates = try #require(try heard.json["candidates"] as? [String])
        #expect(candidates.first == (try heard.json["heard"] as? String))
        #expect(try heard.json["setLog"] as? String == "185x5@8")
        #expect(try cli.run("flush").status == 0)
        #expect(try cli.run("sheet", "--cell", "K15").json["value"] as? String == "185x5@8")
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

    @Test func aMovedHomeKeepsItsSpreadsheetSelection() throws {
        let parent = try temporaryHome()
        defer { try? FileManager.default.removeItem(at: parent) }
        let original = parent.appendingPathComponent("original")
        let moved = parent.appendingPathComponent("moved")
        let binary = try workoutBinary()
        _ = try CLI(home: original, binary: binary).run("init")

        try FileManager.default.moveItem(at: original, to: moved)
        let status = try CLI(home: moved, binary: binary).run("status")
        let spreadsheetId = try status.json["spreadsheetId"] as? String

        #expect(status.status == 0)
        #expect(spreadsheetId == "FIXTURE")
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
        #expect(((warnedOutcome["messages"] as? [String]) ?? []).isEmpty == false)

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
    @Test func aJournalSummarizesAsTheGoldenSummaryAndAMissingOneExitsThree() throws {
        let home = try temporaryHome()
        let journal = home.appendingPathComponent("Dictation Records")
        defer { try? FileManager.default.removeItem(at: home) }
        try FileManager.default.createDirectory(at: journal, withIntermediateDirectories: true)
        let cutOff = #"{"schema":1,"id":"6F1C2D0E"#
        let lines = DictationRecordFixtures.lines + [cutOff]
        try Data(lines.joined(separator: "\n").utf8).write(to: journal.appendingPathComponent("records-2026-10.jsonl"))
        let cli = CLI(home: home, binary: try workoutBinary())

        let summary = try cli.run("dictations", "summary", journal.path)

        #expect(summary.status == 0)
        #expect(String(bytes: summary.stdout, encoding: .utf8) == goldenDictationSummary)
        let missing = try cli.run("dictations", "summary", home.appendingPathComponent("nowhere.jsonl").path)
        #expect(missing.status == 3)
    }

    private let goldenDictationSummary = """
        {
          "agreement" : {
            "agreed" : 1,
            "disagreed" : 1,
            "liveFills" : 1,
            "liveOnly" : 1
          },
          "byRule" : {
            "gate" : {
              "filled" : 2,
              "logged" : 2
            },
            "lead" : {
              "logged" : 3,
              "rejected" : 1
            },
            "liveOnly" : {
              "logged" : 4
            },
            "recordingOnly" : {
              "logged" : 2,
              "rejected" : 2
            }
          },
          "caveats" : [
            "No press is labelled yet, so nothing here says whether a write was right.",
            "Agreement compares the engines only where both read the press. A press with no Recording Transcript is liveOnly.",
            "promptEcho compares the Recording Transcript with the Live Transcript, not with what the athlete said."
          ],
          "ends" : {
            "cancelled" : 1,
            "released" : 3,
            "silence" : 1
          },
          "footprintMB" : {
            "max" : 470,
            "p50" : 420,
            "p90" : 470,
            "p99" : 470
          },
          "guardrail" : {
            "implausible" : {
              "live" : {
                "reps" : 0,
                "rpe" : 0,
                "weight" : 0
              },
              "recording" : {
                "reps" : 0,
                "rpe" : 0,
                "weight" : 1
              }
            }
          },
          "hazards" : {
            "promptEcho" : 1
          },
          "latency" : {
            "missedTarget" : 2,
            "targetMs" : 500,
            "waitCause" : {
              "decisionDeadline" : 1,
              "recordingTranscript" : 1
            },
            "waitMs" : {
              "max" : 1500,
              "p50" : 264,
              "p90" : 1500,
              "p99" : 1500
            },
            "withinTarget" : 2
          },
          "longestMainThreadStallMs" : {
            "max" : 38,
            "p50" : 9,
            "p90" : 38,
            "p99" : 38
          },
          "outcomes" : {
            "logged" : 3,
            "rejected" : 1
          },
          "presses" : 5,
          "recording" : {
            "decodeMs" : {
              "max" : 262,
              "p50" : 262,
              "p90" : 262,
              "p99" : 262
            },
            "missing" : {
              "late" : 1
            },
            "read" : 3
          },
          "surfaces" : {
            "card" : 4,
            "headless" : 1
          },
          "unreadableLines" : 1
        }

        """
#endif
