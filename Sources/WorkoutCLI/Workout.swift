import ArgumentParser

@main
struct Workout: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "workout",
        abstract: "Drive the WorkoutTracker application headlessly against a local workbook.",
        discussion: """
            Every command opens the application over a home directory (manifest.json, store.sqlite,
            workbook.json, settings.json), performs one facade call, and prints its result as JSON on
            stdout. Errors are JSON on stderr with nothing on stdout. Exit codes: 0 ok, 1 domain error,
            3 environment error, 4 conflict, 64 usage.
            """,
        subcommands: [
            InitCommand.self, StatusCommand.self, SessionCommand.self, LogCommand.self,
            SkipCommand.self, FlushCommand.self, SheetCommand.self, SyncCommand.self
        ]
    )
}
