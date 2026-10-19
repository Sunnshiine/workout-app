import ArgumentParser
import Foundation
import WorkoutTracker

struct DictationsCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "dictations",
        abstract: "Read Dictation Records as a phone's journal keeps them.",
        subcommands: [Summary.self, Replay.self]
    )

    /// The records to read, and the labels an export wrote beside them.
    struct Journal: ParsableArguments {
        @Argument(help: "A records-YYYY-MM.jsonl file, or the Dictation Records directory that holds them.")
        var records: String

        @Option(help: "The labels.json an export from Settings writes beside its records.")
        var labels: String?

        var recordsURL: URL { URL(fileURLWithPath: records) }
        var labelsURL: URL? { labels.map { URL(fileURLWithPath: $0) } }
    }

    struct Summary: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "What the Dictation Records in a journal file, or a directory of them, add up to."
        )

        @OptionGroup var journal: Journal

        @MainActor
        func run() async throws {
            try await Output.run { try WorkoutApplication.dictationSummary(reading: journal.recordsURL, labels: journal.labelsURL) }
        }
    }

    struct Replay: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "Score recorded presses under every merge rule, by Speech Model version."
        )

        @OptionGroup var journal: Journal

        @MainActor
        func run() async throws {
            try await Output.run { try WorkoutApplication.dictationReplay(reading: journal.recordsURL, labels: journal.labelsURL) }
        }
    }
}
