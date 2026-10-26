import ArgumentParser

@main
struct Workout: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "workout",
        abstract: "Drive the WorkoutTracker application headlessly against a local workbook.",
        discussion: """
            Every command opens the application over a home directory (manifest.json, store.sqlite,
            workbook.json, settings.json), performs one gesture, and prints its result as JSON on
            stdout. A gesture whose state lives in memory makes all its facade calls in one process
            (move-on, make-current). Errors are JSON on stderr, after the report when the command
            printed one first.
            Exit codes: 0 ok, 1 domain error, 3 environment error, 4 conflict, 64 usage, 69 no on-device
            speech-to-text.
            """,
        subcommands: [
            InitCommand.self, StatusCommand.self, SessionCommand.self, LogCommand.self,
            SkipCommand.self, MoveOnCommand.self, MakeCurrentCommand.self, DeleteLogCommand.self, SayCommand.self,
            HearCommand.self, FlushCommand.self, SheetCommand.self, SyncCommand.self, DictationsCommand.self
        ]
    )
}
