import Foundation
import SwiftData

/// Where an application's state lives. Values only; nothing about what to do with them.
public struct AppEnvironment {
    enum Storage {
        case inMemory
        case deviceDefault
        case file(URL)
    }

    let storage: Storage
    let sheetsClient: any SheetsClient
    let defaults: UserDefaults
    let now: @MainActor () -> Date
    let seed: (@MainActor (ModelContext) throws -> Void)?

    #if OFFLINE_SHEET
        /// An application whose Sheet is `workbook` and whose store vanishes with the process. The
        /// defaults suite is wiped on creation but, like every `UserDefaults` suite, persists as a plist.
        public static func inMemory(
            workbook: LocalWorkbook,
            defaults: UserDefaults = ephemeralDefaults(),
            now: @escaping @MainActor () -> Date = Date.init
        ) -> AppEnvironment {
            AppEnvironment(
                storage: .inMemory,
                sheetsClient: LocalWorkbookSheetsClient(workbook: workbook),
                defaults: defaults,
                now: now,
                seed: nil
            )
        }

        /// An application that keeps its store in `home/store.sqlite` and its Sheet in `workbookFile`,
        /// writing the workbook back after every successful Sheet update.
        public static func directory(
            _ home: URL,
            workbookFile: URL,
            defaults: UserDefaults,
            now: @escaping @MainActor () -> Date = Date.init
        ) throws -> AppEnvironment {
            AppEnvironment(
                storage: .file(home.appendingPathComponent("store.sqlite")),
                sheetsClient: LocalWorkbookSheetsClient(workbook: try LocalWorkbook.load(from: workbookFile), persistTo: workbookFile),
                defaults: defaults,
                now: now,
                seed: nil
            )
        }

        /// A throwaway defaults suite, wiped on creation, so two in-memory applications never share a key.
        public static func ephemeralDefaults() -> UserDefaults {
            let suiteName = "WorkoutTracker.ephemeral.\(UUID().uuidString)"
            let defaults = UserDefaults(suiteName: suiteName) ?? .standard
            defaults.removePersistentDomain(forName: suiteName)
            return defaults
        }
    #endif

    static func device() -> AppEnvironment {
        AppEnvironment(
            storage: .deviceDefault,
            sheetsClient: GoogleSheetsClient(),
            defaults: .standard,
            now: Date.init,
            seed: nil
        )
    }

    #if DEBUG
        static func uiTestFixture() -> AppEnvironment {
            AppEnvironment(
                storage: .inMemory,
                sheetsClient: UITestFixture.makeSheetsClient(),
                defaults: UITestFixture.makeDefaults(),
                now: Date.init,
                seed: { try UITestFixture.seed(into: $0, launch: UITestFixture.launch) }
            )
        }
    #endif
}
