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
    /// Holds every Form Clip's movie and record. A directory in every environment, because a movie
    /// is a file: an in-memory application's lives in a throwaway one.
    let formClips: URL
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
        /// faults after its boot sync, and keeps its Dictation Records and Form Clips on disk, so a
        /// fixture press's record and a picked clip can be read from the Simulator's container.
        static func inMemory(
            sheets: any SheetsClient,
            dictationRecords: DictationJournal.Storage = .inMemory,
            formClips: URL = URL.temporaryDirectory.appending(path: "Form Clips \(UUID().uuidString)"),
            now: @escaping @MainActor () -> Date = Date.init
        ) -> AppEnvironment {
            AppEnvironment(
                storage: .inMemory,
                dictationRecords: dictationRecords,
                formClips: formClips,
                sheetsClient: sheets,
                defaults: .inMemory(),
                now: now
            )
        }

        /// An application that keeps its store in `home/store.sqlite`, its settings in
        /// `home/settings.json`, its Dictation Records in `home/dictation-records`, and its Form
        /// Clips in `home/form-clips`. Its Sheet is
        /// `workbookFile`, read on every call and rewritten after every successful update.
        public static func directory(
            _ home: URL,
            workbookFile: URL,
            now: @escaping @MainActor () -> Date = Date.init
        ) throws -> AppEnvironment {
            AppEnvironment(
                storage: .file(home.appendingPathComponent("store.sqlite")),
                dictationRecords: .directory(home.appending(path: "dictation-records")),
                formClips: home.appending(path: "form-clips"),
                sheetsClient: try LocalWorkbookSheetsClient(file: workbookFile),
                defaults: try .file(home.appendingPathComponent("settings.json")),
                now: now
            )
        }
    #endif

    static let deviceDictationRecords = URL.applicationSupportDirectory.appending(path: "Dictation Records")
    static let deviceFormClips = URL.applicationSupportDirectory.appending(path: "Form Clips")

    static func device() -> AppEnvironment {
        AppEnvironment(
            storage: .deviceDefault,
            dictationRecords: .directory(Self.deviceDictationRecords),
            formClips: Self.deviceFormClips,
            sheetsClient: GoogleSheetsClient(),
            defaults: .device(),
            now: Date.init
        )
    }
}
