#if os(macOS)
    import Foundation
    import Testing

    private let replayLabels = #"""
        {"labels":[{"record":"6F1C2D0E-0000-4000-8000-000000000001","setLog":"185x5@8","state":"logged"},
        {"record":"6F1C2D0E-0000-4000-8000-000000000005","setLog":"135x5@8","state":"logged"},
        {"record":"6F1C2D0E-0000-4000-8000-000000000002","state":"pending"}],"schema":1}
        """#

    @Test func aJournalReplaysUnderEveryRuleAsTheGoldenReplayWithAndWithoutLabels() throws {
        let home = try temporaryHome()
        defer { try? FileManager.default.removeItem(at: home) }
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
        let journal = home.appendingPathComponent("records-2026-10.jsonl")
        try Data(DictationRecordFixtures.lines.joined(separator: "\n").utf8).write(to: journal)
        let labels = home.appendingPathComponent("labels.json")
        try Data(replayLabels.utf8).write(to: labels)
        let cli = CLI(home: home, binary: try workoutBinary())

        let unlabelled = try cli.run("dictations", "replay", journal.path)
        let labelled = try cli.run("dictations", "replay", journal.path, "--labels", labels.path)

        #expect(unlabelled.status == 0)
        #expect(String(bytes: unlabelled.stdout, encoding: .utf8) == goldenUnlabelledReplay)
        #expect(labelled.status == 0)
        #expect(String(bytes: labelled.stdout, encoding: .utf8) == goldenLabelledReplay)
        let summary = try cli.run("dictations", "summary", journal.path, "--labels", labels.path)
        #expect(
            try summary.json["scored"] as? [String: Int] == ["CORRECT": 1, "WRONG": 1, "NOWRITE": 0, "unscored": 2]
        )
        let missing = try cli.run("dictations", "replay", journal.path, "--labels", home.appendingPathComponent("none.json").path)
        #expect(missing.status == 3)
    }

    /// Four decided presses, all read with one Speech Model version and decided by `lead`.
    private let goldenUnlabelledReplay = """
        {
          "cancelled" : 1,
          "caveats" : [
            "No labels were given, so this counts where the rules disagree, not which rule is right.",
            "Each rule's outcome is the one recorded at the press, not one today's parser would decide."
          ],
          "presses" : 5,
          "unreadableLines" : 0,
          "versions" : [
            {
              "decided" : 4,
              "decidedBy" : {
                "lead" : 4
              },
              "rules" : {
                "gate" : {
                  "differsFromDecided" : 2,
                  "outcomes" : {
                    "filled" : 2,
                    "logged" : 2
                  }
                },
                "lead" : {
                  "differsFromDecided" : 0,
                  "outcomes" : {
                    "logged" : 3,
                    "rejected" : 1
                  }
                },
                "liveOnly" : {
                  "differsFromDecided" : 2,
                  "outcomes" : {
                    "logged" : 4
                  }
                },
                "recordingOnly" : {
                  "differsFromDecided" : 1,
                  "outcomes" : {
                    "logged" : 2,
                    "rejected" : 2
                  }
                }
              },
              "version" : {
                "model" : "openai_whisper-small.en",
                "modelRevision" : "0f63a7800b00dd0226abd051b906c246e1907482",
                "options" : "t0.nots.wc0.fb5",
                "prompt" : "p1",
                "tokenizerRevision" : "e8727524f962ee844a7319d92be39ac1bd25655a"
              }
            }
          ]
        }

        """

    /// Lead writes press 5 WRONG, gate holds it back as a fill (NOWRITE), and liveOnly writes it CORRECT.
    private let goldenLabelledReplay = """
        {
          "cancelled" : 1,
          "caveats" : [
            "Only a press whose outcome wrote a Set has a label, so the rule that decided a press never scores NOWRITE.",
            "Another rule's write on a press nothing wrote is unscored.",
            "A correction is a lower bound on wrong writes. An athlete who never notices a wrong write never corrects it.",
            "A Set the athlete cleared and left Pending is unscored.",
            "Each rule's outcome is the one recorded at the press, not one today's parser would decide."
          ],
          "presses" : 5,
          "unreadableLines" : 0,
          "versions" : [
            {
              "decided" : 4,
              "decidedBy" : {
                "lead" : 4
              },
              "labelled" : 3,
              "rules" : {
                "gate" : {
                  "differsFromDecided" : 2,
                  "outcomes" : {
                    "filled" : 2,
                    "logged" : 2
                  },
                  "scored" : {
                    "CORRECT" : 1,
                    "NOWRITE" : 1,
                    "WRONG" : 0,
                    "unscored" : 2
                  }
                },
                "lead" : {
                  "differsFromDecided" : 0,
                  "outcomes" : {
                    "logged" : 3,
                    "rejected" : 1
                  },
                  "scored" : {
                    "CORRECT" : 1,
                    "NOWRITE" : 0,
                    "WRONG" : 1,
                    "unscored" : 2
                  }
                },
                "liveOnly" : {
                  "differsFromDecided" : 2,
                  "outcomes" : {
                    "logged" : 4
                  },
                  "scored" : {
                    "CORRECT" : 2,
                    "NOWRITE" : 0,
                    "WRONG" : 0,
                    "unscored" : 2
                  }
                },
                "recordingOnly" : {
                  "differsFromDecided" : 1,
                  "outcomes" : {
                    "logged" : 2,
                    "rejected" : 2
                  },
                  "scored" : {
                    "CORRECT" : 1,
                    "NOWRITE" : 0,
                    "WRONG" : 1,
                    "unscored" : 2
                  }
                }
              },
              "version" : {
                "model" : "openai_whisper-small.en",
                "modelRevision" : "0f63a7800b00dd0226abd051b906c246e1907482",
                "options" : "t0.nots.wc0.fb5",
                "prompt" : "p1",
                "tokenizerRevision" : "e8727524f962ee844a7319d92be39ac1bd25655a"
              }
            }
          ]
        }

        """
#endif
