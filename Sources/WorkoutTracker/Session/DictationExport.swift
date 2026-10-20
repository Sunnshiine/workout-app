import Foundation

/// What Settings shares of the Dictation Records: the journal's records as monthly files, a
/// `labels.json` beside them, and the MetricKit payloads in a `MetricKit` folder, zipped into one
/// archive that `workout dictations summary` and `replay` read once unzipped.
struct DictationExport: Sendable {
    static let name = "Dictation Records"

    let records: [DictationRecord]
    let labels: DictationLabels
    let payloads: [MetricKitPayload]

    /// Writes the export into `directory` as `Dictation Records/` and `Dictation Records.zip`,
    /// replacing an earlier export there, and returns the archive. Runs off the main actor, since a
    /// full journal is tens of megabytes.
    func archive(in directory: URL) async throws -> URL {
        let folder = directory.appending(path: Self.name)
        let archive = directory.appending(path: "\(Self.name).zip")
        for earlier in [folder, archive] where FileManager.default.fileExists(atPath: earlier.path) {
            try FileManager.default.removeItem(at: earlier)
        }
        try write(to: folder)
        try Self.zip(folder, to: archive)
        return archive
    }

    private func write(to folder: URL) throws {
        let metricKit = folder.appending(path: "MetricKit")
        try FileManager.default.createDirectory(at: metricKit, withIntermediateDirectories: true)
        let encoder = DictationRecord.lineEncoder()
        let months = Dictionary(grouping: records) { DictationRecordFiles.fileName(for: $0.pressedAt) }
        for (name, records) in months {
            var lines = Data()
            for record in records {
                lines.append(try encoder.encode(record))
                lines.append(UInt8(ascii: "\n"))
            }
            try lines.write(to: folder.appending(path: name))
        }
        try encoder.encode(labels).write(to: folder.appending(path: DictationLabels.fileName))
        for payload in payloads {
            try payload.json.write(to: metricKit.appending(path: payload.fileName))
        }
    }

    /// The archive Foundation makes of a folder for uploading, copied out before Foundation
    /// deletes it.
    private static func zip(_ folder: URL, to archive: URL) throws {
        var coordinationError: NSError?
        var copyError: (any Error)?
        NSFileCoordinator().coordinate(readingItemAt: folder, options: .forUploading, error: &coordinationError) { zipped in
            do {
                try FileManager.default.copyItem(at: zipped, to: archive)
            } catch {
                copyError = error
            }
        }
        if let error = coordinationError ?? copyError { throw error }
    }
}

extension WorkoutApplication {
    /// The Dictation Records, labelled from the cached Block as it stands, archived in `directory`
    /// for the share sheet. Waits for every record handed to the journal before it.
    public func exportDictations(into directory: URL) async throws -> URL {
        let kept = try await dictationJournal.kept()
        let export = DictationExport(records: kept.records, labels: labels(for: kept.records), payloads: kept.payloads)
        return try await export.archive(in: directory)
    }
}
