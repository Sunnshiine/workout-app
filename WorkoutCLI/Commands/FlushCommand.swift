import ArgumentParser
import WorkoutTracker

struct FlushCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "flush",
        abstract: "Write every pending Set Log to the workbook through SyncCoordinator.flushPending."
    )

    @OptionGroup var homeOptions: HomeOptions

    @MainActor
    func run() async throws {
        let home = homeOptions.resolved
        try await Output.run {
            try await home.open().flush()
        } verdict: { report in
            guard report.conflictedWrites.isEmpty else {
                throw CLIError.conflict(code: "write_conflict", messages: report.conflictedWrites)
            }
            switch report.syncOutcome.status {
            case .writesQueued, .sheetUnreachable:
                throw CLIError.environment(
                    "Flush stopped before every write reached the Sheet "
                        + "(\(report.remainingPendingWrites) still queued). "
                        + "Fix the workbook and run `workout flush` again."
                )
            case .clear, .localWriteFailed, .writesRefused, .noBlockTab, .parseWarnings, .historyFillFailed:
                break
            }
        }
    }
}
