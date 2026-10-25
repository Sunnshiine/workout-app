import ArgumentParser
import WorkoutTracker

struct SayCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "say",
        abstract: "Log or skip a Set from what the athlete said. Enqueues the Sheet write(s); run `flush` to send them."
    )

    @OptionGroup var homeOptions: HomeOptions

    @Argument(help: "A Set address such as w1d1.e0.s0.")
    var address: String

    @Argument(help: "The transcript, such as \"185 for 5 at 8\", \"at 9\", \"same again\", or \"skip\".")
    var transcript: String

    @MainActor
    func run() async throws {
        let home = homeOptions.resolved
        try await Output.run {
            guard let parsed = SetAddress(address) else { throw ApplicationError.invalidAddress(address) }
            return try home.open().say(transcript, at: parsed)
        } verdict: { report in
            guard let rejection = report.rejection else { return }
            throw ApplicationError.spokenSetRejected(report.heard, reason: rejection.reason)
        }
    }
}
