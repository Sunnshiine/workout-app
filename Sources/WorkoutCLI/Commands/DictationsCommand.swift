import ArgumentParser
import Foundation
import WorkoutTracker

struct DictationsCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "dictations",
        abstract: "Read Dictation Records as a phone's journal keeps them.",
        subcommands: [Summary.self]
    )

    struct Summary: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "What the Dictation Records in a journal file, or a directory of them, add up to."
        )

        @Argument(help: "A records-YYYY-MM.jsonl file, or the Dictation Records directory that holds them.")
        var records: String

        @MainActor
        func run() async throws {
            try await Output.run { try WorkoutApplication.dictationSummary(reading: URL(fileURLWithPath: records)) }
        }
    }
}
