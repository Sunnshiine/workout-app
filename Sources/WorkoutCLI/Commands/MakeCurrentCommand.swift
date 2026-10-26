import ArgumentParser
import WorkoutTracker

struct MakeCurrentCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "make-current",
        abstract: "View a Session, then make it current through WorkoutStore.makeViewedSessionCurrent, in one process."
    )

    @OptionGroup var homeOptions: HomeOptions

    @Argument(help: "A Session address such as w2d1.")
    var address: String

    @MainActor
    func run() async throws {
        let home = homeOptions.resolved
        try await Output.run {
            guard let parsed = SessionAddress(address) else { throw ApplicationError.invalidAddress(address) }
            let app = try home.open()
            try app.view(parsed)
            return try app.makeCurrent()
        }
    }
}
