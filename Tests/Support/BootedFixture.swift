#if DEBUG
    import Foundation
    import SwiftData
    import Testing

    @testable import WorkoutTracker

    /// A fixture application booted the way the app boots one for a launch: a fresh in-memory
    /// application over the launch's drive, then `UITestFixture.boot`.
    @MainActor
    struct BootedFixture {
        let app: WorkoutApplication
        let sheets: LocalDrive

        static func boot(_ arguments: [String]) async throws -> BootedFixture {
            let launch = UITestLaunch(arguments: arguments)
            let sheets = UITestFixture.makeSheets(launch: launch)
            let app = try WorkoutApplication(environment: .inMemory(sheets: sheets))
            try await UITestFixture.boot(app, launch: launch, sheets: sheets)
            return BootedFixture(app: app, sheets: sheets)
        }

        /// Boots `scenario` by passing the flag that selects it, or no scenario flag for the one a
        /// launch falls back to.
        static func boot(_ scenario: WorkbookScenario, plus arguments: [String] = []) async throws -> BootedFixture {
            let flag = UITestLaunch.scenarioFlags.first { $0.scenario == scenario }?.flag
            return try await boot((flag.map { [$0.argument] } ?? []) + arguments)
        }

        var context: ModelContext { app.container.mainContext }

        /// The one Block the boot left in the store.
        func block() throws -> Block {
            let blocks = try context.fetch(FetchDescriptor<Block>())
            #expect(blocks.count == 1)
            return try #require(blocks.first)
        }
    }
#endif
