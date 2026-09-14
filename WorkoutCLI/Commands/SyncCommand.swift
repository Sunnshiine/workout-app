import ArgumentParser
import WorkoutTracker

struct SyncCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "sync",
        abstract: "Flush pending writes, then re-parse the Block from the workbook through SyncCoordinator.sync."
    )

    @OptionGroup var homeOptions: HomeOptions

    @MainActor
    func run() async throws {
        let home = homeOptions.resolved
        try await Output.run {
            try await home.open().sync()
        } verdict: { report in
            var messages = report.conflictedWrites
            if case .conflict(let warnings) = report.syncState {
                messages.append(contentsOf: warnings)
            }
            guard messages.isEmpty else {
                throw CLIError.conflict(code: "sync_conflict", messages: messages)
            }
        }
    }
}
