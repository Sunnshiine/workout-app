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
            // A write this sync refused is both a conflicted write and the outcome's message.
            let messages = (report.conflictedWrites + report.syncOutcome.messages).reduce(into: [String]()) {
                if !$0.contains($1) { $0.append($1) }
            }
            guard !report.syncOutcome.status.leavesTheAthleteSomethingToDo, messages.isEmpty else {
                throw CLIError.conflict(code: "sync_conflict", messages: messages)
            }
        }
    }
}

extension SyncOutcomeSnapshot.Status {
    /// Which outcomes exit 4. A refused write the Sheet will never retry, a Set Log the local
    /// store lost, a spreadsheet that is not a training log, and the two footnotes on an otherwise
    /// good sync all leave the athlete a decision; the other three do not.
    fileprivate var leavesTheAthleteSomethingToDo: Bool {
        switch self {
        case .localWriteFailed, .writesRefused, .noBlockTab, .parseWarnings, .historyFillFailed: true
        case .clear, .sheetUnreachable, .writesQueued: false
        }
    }
}
