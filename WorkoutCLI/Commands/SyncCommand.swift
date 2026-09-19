import ArgumentParser
import WorkoutTracker

struct SyncCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "sync",
        abstract: "Flush pending writes, then re-parse the Block from the workbook through SyncCoordinator.sync."
    )

    @OptionGroup var homeOptions: HomeOptions

    @Option(
        name: .customLong("viewing"),
        help: "Open this Session first, the way an athlete browsing the Block grid would, so the report shows whether the sync moved them."
    )
    var viewing: String?

    @MainActor
    func run() async throws {
        let home = homeOptions.resolved
        try await Output.run {
            let app = try home.open()
            if let viewing {
                guard let address = SessionAddress(viewing) else { throw ApplicationError.invalidAddress(viewing) }
                try app.view(address)
            }
            return try await app.sync()
        } verdict: { report in
            let leftForTheAthlete =
                switch report.syncOutcome.status {
                case .localWriteFailed, .writesRefused, .noBlockTab, .parseWarnings, .historyFillFailed: true
                case .clear, .sheetUnreachable, .writesQueued: false
                }
            let messages = report.conflictedWrites + report.syncOutcome.messages
            guard !leftForTheAthlete, messages.isEmpty else {
                throw CLIError.conflict(code: "sync_conflict", messages: messages)
            }
        }
    }
}
