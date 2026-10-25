#if os(macOS)
    import Foundation
    import Testing

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

/// Press 1 stood, press 5's 62x11@9 was corrected to 135x5@8, press 2's Set was cleared, and
/// press 4 wrote nothing, so it has no label.
#endif
