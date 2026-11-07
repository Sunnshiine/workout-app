import ArgumentParser
import Foundation
import WorkoutTracker

struct ClipCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "clip",
        abstract: "Keep Form Clips on a Logged Set: add, list, trace, mark, compare, delete. None of these touch the Sheet.",
        subcommands: [Add.self, List.self, Trace.self, Mark.self, Previous.self, Delete.self, Storage.self]
    )

    struct Add: AsyncParsableCommand {
        static let configuration = CommandConfiguration(abstract: "Copy a movie in as a Form Clip of a Logged Set.")

        @OptionGroup var homeOptions: HomeOptions
        @Argument(help: "A Set address such as w1d1.e0.s0.") var address: String
        @Argument(help: "A movie file.") var movie: String

        @MainActor
        func run() async throws {
            let home = homeOptions.resolved
            try await Output.run {
                guard let parsed = SetAddress(address) else { throw ApplicationError.invalidAddress(address) }
                return try await home.open().addFormClip(copying: URL(fileURLWithPath: movie), at: parsed)
            }
        }
    }

    struct List: AsyncParsableCommand {
        static let configuration = CommandConfiguration(abstract: "Every Form Clip, newest first, or those on one Set.")

        @OptionGroup var homeOptions: HomeOptions
        @Argument(help: "A Set address such as w1d1.e0.s0.") var address: String?

        @MainActor
        func run() async throws {
            let home = homeOptions.resolved
            try await Output.run {
                let parsed = try address.map { raw in
                    guard let parsed = SetAddress(raw) else { throw ApplicationError.invalidAddress(raw) }
                    return parsed
                }
                return try home.open().formClips(at: parsed)
            }
        }
    }

    struct Trace: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "Follow a plate from a point on a frame and keep the Bar Path on the clip.",
            discussion: "x and y are shares of the displayed frame, from its top left."
        )

        @OptionGroup var homeOptions: HomeOptions
        @Argument(help: "A Form Clip id from `workout clip list`.") var id: UUID
        @Option(help: "Across the frame, 0 to 1.") var x: Double
        @Option(help: "Down the frame, 0 to 1.") var y: Double
        @Option(help: "Seconds into the movie.") var at: Double = 0

        @MainActor
        func run() async throws {
            let home = homeOptions.resolved
            try await Output.run {
                try await home.open().traceBarPath(on: id, from: BarPathStart(time: at, x: x, y: y))
            }
        }
    }

    struct Mark: AsyncParsableCommand {
        static let configuration = CommandConfiguration(abstract: "Mark where the Set starts, or clear the mark with no --at.")

        @OptionGroup var homeOptions: HomeOptions
        @Argument(help: "A Form Clip id from `workout clip list`.") var id: UUID
        @Option(help: "Seconds into the movie.") var at: Double?

        @MainActor
        func run() async throws {
            let home = homeOptions.resolved
            try await Output.run { try home.open().markStart(of: id, at: at) }
        }
    }

    struct Previous: AsyncParsableCommand {
        static let configuration = CommandConfiguration(abstract: "The clip a Compare opens beside this one, or null.")

        @OptionGroup var homeOptions: HomeOptions
        @Argument(help: "A Form Clip id from `workout clip list`.") var id: UUID

        @MainActor
        func run() async throws {
            let home = homeOptions.resolved
            try await Output.run { try home.open().previousFormClip(of: id) }
        }
    }

    struct Delete: AsyncParsableCommand {
        static let configuration = CommandConfiguration(abstract: "Delete a clip's movie and record; reports what is left.")

        @OptionGroup var homeOptions: HomeOptions
        @Argument(help: "A Form Clip id from `workout clip list`.") var id: UUID

        @MainActor
        func run() async throws {
            let home = homeOptions.resolved
            try await Output.run { try home.open().deleteFormClip(id) }
        }
    }

    struct Storage: AsyncParsableCommand {
        static let configuration = CommandConfiguration(abstract: "What Form Clips take on this device.")

        @OptionGroup var homeOptions: HomeOptions

        @MainActor
        func run() async throws {
            let home = homeOptions.resolved
            try await Output.run { try home.open().formClipStorage() }
        }
    }
}

extension UUID: @retroactive ExpressibleByArgument {
    public init?(argument: String) {
        self.init(uuidString: argument)
    }
}
