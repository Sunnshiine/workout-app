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
    let dictationRecords: DictationJournal.Storage
    let sheetsClient: any SheetsClient
    let defaults: AppDefaults
    let now: @MainActor () -> Date
    let seed: (@MainActor (ModelContext) throws -> Void)?

    #if OFFLINE_SHEET
        /// An application whose Sheet is `workbook` and whose store and settings vanish with the process.
        public static func inMemory(
            workbook: LocalWorkbook,
            now: @escaping @MainActor () -> Date = Date.init
        ) -> AppEnvironment {
            AppEnvironment(
                storage: .inMemory,
                dictationRecords: .inMemory,
                sheetsClient: LocalWorkbookSheetsClient(workbook: workbook),
                defaults: .inMemory(),
                now: now,
                seed: nil
            )
        }

        /// An application that keeps its store in `home/store.sqlite`, its settings in
        /// `home/settings.json`, its Dictation Records in `home/dictation-records`, and its Sheet in
        /// `workbookFile`, writing the workbook back after every successful Sheet update.
        public static func directory(
            _ home: URL,
            workbookFile: URL,
            now: @escaping @MainActor () -> Date = Date.init
        ) throws -> AppEnvironment {
            AppEnvironment(
                storage: .file(home.appendingPathComponent("store.sqlite")),
                dictationRecords: .directory(home.appending(path: "dictation-records")),
                sheetsClient: LocalWorkbookSheetsClient(workbook: try LocalWorkbook.load(from: workbookFile), persistTo: workbookFile),
                defaults: try .file(home.appendingPathComponent("settings.json")),
                now: now,
                seed: nil
            )
        }
    #endif

    static let deviceDictationRecords = URL.applicationSupportDirectory.appending(path: "Dictation Records")

    static func device() -> AppEnvironment {
        AppEnvironment(
            storage: .deviceDefault,
            dictationRecords: .directory(Self.deviceDictationRecords),
            sheetsClient: GoogleSheetsClient(),
            defaults: .device(),
            now: Date.init,
            seed: nil
        )
    }

    #if DEBUG
        static func uiTestFixture(launch: UITestLaunch) -> AppEnvironment {
            AppEnvironment(
                storage: .inMemory,
                // On disk, so a fixture press's record can be read from the Simulator's container.
                dictationRecords: .directory(Self.deviceDictationRecords),
                sheetsClient: UITestFixture.makeSheetsClient(launch: launch),
                defaults: .inMemory(),
                now: Date.init,
                seed: { try UITestFixture.seed(into: $0, launch: launch) }
            )
        }
    #endif
}
