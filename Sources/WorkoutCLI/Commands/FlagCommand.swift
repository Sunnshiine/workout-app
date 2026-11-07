import ArgumentParser
import WorkoutTracker

extension SetFlagKind: ExpressibleByArgument {}

struct FlagCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "flag",
        abstract: "Raise a Set Flag through WorkoutStore.flag. Enqueues the Cell Note write; run `flush` to send it."
    )

    @OptionGroup var homeOptions: HomeOptions

    @Argument(help: "A Set address such as w1d1.e0.s0.")
    var address: String

    @Argument(help: "pain, technique, swapped, or other.")
    var kind: SetFlagKind

    @Argument(help: "The words the coach reads. Required for other.")
    var text: String?

    @MainActor
    func run() async throws {
        let home = homeOptions.resolved
        try await Output.run {
            guard let parsed = SetAddress(address) else { throw ApplicationError.invalidAddress(address) }
            guard let flag = SetFlag(kind: kind, text: text) else { throw ApplicationError.invalidSetFlag(kind) }
            return try home.open().flag(parsed, as: flag)
        }
    }
}
