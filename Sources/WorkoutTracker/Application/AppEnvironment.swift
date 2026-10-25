import Foundation

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

    #if OFFLINE_SHEET
        /// An application whose Sheet is `workbook` and whose store and settings vanish with the process.
        public static func inMemory(
            workbook: LocalWorkbook,
            now: @escaping @MainActor () -> Date = Date.init
        ) -> AppEnvironment {
            .inMemory(sheets: LocalWorkbookSheetsClient(workbook: workbook), now: now)
        }

        /// An application whose spreadsheets are `sheets` and whose store and settings vanish with
        /// the process. The UI fixture passes a `LocalDrive` it keeps, so it can arm the drive's
        /// faults after its boot sync, and keeps its Dictation Records on disk, so a fixture press's
        /// record can be read from the Simulator's container.
        static func inMemory(
            sheets: any SheetsClient,
            dictationRecords: DictationJournal.Storage = .inMemory,
            now: @escaping @MainActor () -> Date = Date.init
        ) -> AppEnvironment {
            AppEnvironment(
                storage: .inMemory,
                dictationRecords: dictationRecords,
                sheetsClient: sheets,
                defaults: .inMemory(),
                now: now
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
                now: now
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
            now: Date.init
        )
    }
}
