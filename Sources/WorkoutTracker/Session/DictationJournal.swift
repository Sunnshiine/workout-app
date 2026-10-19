import Foundation
import os

private let journalLogger = Logger(subsystem: "WorkoutTracker", category: "DictationJournal")

/// Keeps every press's Dictation Record. `append` hands the record to a writer off the main actor
/// and returns at once, so a slow disk never holds up a press's outcome or the screen.
final class DictationJournal: Sendable {
    enum Storage: Sendable {
        case inMemory
        /// JSON Lines in `directory`, keeping the newest `DictationRecordFiles.capacity` records.
        case directory(URL)
    }

    private enum Entry: Sendable {
        case record(DictationRecord)
        case payload(MetricKitPayload)
        case read(CheckedContinuation<Kept, any Error>)
    }

    /// Everything a journal keeps, as one read sees it.
    struct Kept: Equatable, Sendable {
        let records: [DictationRecord]
        let payloads: [MetricKitPayload]
    }

    private let inbox: AsyncStream<Entry>.Continuation
    /// The one writer: it takes entries in the order they came, so a read sees every record
    /// appended before it.
    private let writing: Task<Void, Never>

    convenience init(storage: Storage) {
        switch storage {
        case .inMemory: self.init(store: DictationRecordMemory())
        case .directory(let url): self.init(store: DictationRecordFiles(directory: url, keeping: DictationRecordFiles.capacity))
        }
    }

    init(store: any DictationRecordStore) {
        let (entries, inbox) = AsyncStream.makeStream(of: Entry.self)
        self.inbox = inbox
        writing = Task(priority: .utility) {
            for await entry in entries {
                await Self.take(entry, into: store)
            }
        }
    }

    private static func take(_ entry: Entry, into store: any DictationRecordStore) async {
        switch entry {
        case .record(let record):
            await keeping("A Dictation Record") { try await store.append(record) }
        case .payload(let payload):
            await keeping("A MetricKit payload") { try await store.keep(payload) }
        case .read(let reading):
            do {
                reading.resume(returning: Kept(records: try await store.records(), payloads: try await store.payloads()))
            } catch {
                reading.resume(throwing: error)
            }
        }
    }

    /// A write that fails is logged and dropped, so one bad write never stops the writer.
    private static func keeping(_ what: String, _ write: () async throws -> Void) async {
        do {
            try await write()
        } catch {
            journalLogger.error("\(what, privacy: .public) was not kept: \(error, privacy: .public)")
        }
    }

    deinit {
        inbox.finish()
    }

    /// Returns at once. The record is written after every record appended before it.
    func append(_ record: DictationRecord) {
        inbox.yield(.record(record))
    }

    /// Returns at once. Keeps a payload MetricKit delivered beside the records, so an export
    /// carries the hangs and memory of the presses around it.
    func keep(_ payload: MetricKitPayload) {
        inbox.yield(.payload(payload))
    }

    /// Every record kept, once every record appended before this call is written.
    func records() async throws -> [DictationRecord] {
        try await kept().records
    }

    /// Every record and payload kept, once everything handed over before this call is written.
    func kept() async throws -> Kept {
        try await withCheckedThrowingContinuation { inbox.yield(.read($0)) }
    }
}

/// One payload as MetricKit delivered it, its JSON untouched: a day's metrics, or the diagnostics,
/// hangs among them, it gathered.
struct MetricKitPayload: Equatable, Sendable {
    enum Kind: String, Sendable {
        case metrics, diagnostics
    }

    /// Sorts payloads oldest first, as "2026-10-19T17-00-00Z-diagnostics.json". The same payload
    /// delivered twice keeps one name.
    let fileName: String
    let json: Data

    /// `endedAt` is the end of the window the payload covers.
    init(kind: Kind, endedAt: Date, json: Data) {
        fileName = "\(endedAt.formatted(.iso8601).replacingOccurrences(of: ":", with: "-"))-\(kind.rawValue).json"
        self.json = json
    }

    fileprivate init(fileName: String, json: Data) {
        self.fileName = fileName
        self.json = json
    }
}

/// Where Dictation Records are kept. Only a journal's writer calls it, one call at a time.
protocol DictationRecordStore: Sendable {
    func append(_ record: DictationRecord) async throws
    func records() async throws -> [DictationRecord]
    func keep(_ payload: MetricKitPayload) async throws
    /// Oldest first.
    func payloads() async throws -> [MetricKitPayload]
}

actor DictationRecordMemory: DictationRecordStore {
    private var kept: [DictationRecord] = []
    private var keptPayloads: [String: MetricKitPayload] = [:]

    func append(_ record: DictationRecord) {
        kept.append(record)
    }

    func records() -> [DictationRecord] {
        kept
    }

    func keep(_ payload: MetricKitPayload) {
        keptPayloads[payload.fileName] = payload
    }

    func payloads() -> [MetricKitPayload] {
        keptPayloads.sorted { $0.key < $1.key }.map(\.value)
    }
}

/// Dictation Records as JSON Lines, one file per month of presses (`records-2026-10.jsonl`), with
/// the oldest month deleted once the files hold more than `capacity` records.
actor DictationRecordFiles: DictationRecordStore {
    /// About 2 KB a record: a heavy month is under a megabyte.
    static let capacity = 20_000

    private let directory: URL
    private let capacity: Int
    /// Records in each file, counted at the first append.
    private var counts: [URL: Int]?

    init(directory: URL, keeping capacity: Int) {
        self.directory = directory
        self.capacity = capacity
    }

    func append(_ record: DictationRecord) throws {
        var counts = try counts ?? keptCounts()
        let file = directory.appending(path: "records-\(record.pressedAt.formatted(.iso8601.year().month())).jsonl")
        let line = try DictationRecord.lineEncoder().encode(record) + Data("\n".utf8)
        if let handle = try? FileHandle(forWritingTo: file) {
            defer { try? handle.close() }
            try handle.seekToEnd()
            try handle.write(contentsOf: line)
        } else {
            try line.write(to: file)
        }
        counts[file, default: 0] += 1
        while counts.values.reduce(0, +) > capacity, counts.count > 1, let oldest = counts.keys.min(by: { $0.path < $1.path }) {
            try FileManager.default.removeItem(at: oldest)
            counts[oldest] = nil
        }
        self.counts = counts
    }

    func records() throws -> [DictationRecord] {
        guard FileManager.default.fileExists(atPath: directory.path) else { return [] }
        return try DictationRecordLines(at: directory).records
    }

    /// About a month of a day's metrics and the diagnostics between them.
    static let payloadCapacity = 60

    private var payloadDirectory: URL { directory.appending(path: "MetricKit") }

    /// Keeps the newest `payloadCapacity` payloads.
    func keep(_ payload: MetricKitPayload) throws {
        if counts == nil { counts = try keptCounts() }
        try FileManager.default.createDirectory(at: payloadDirectory, withIntermediateDirectories: true)
        try payload.json.write(to: payloadDirectory.appending(path: payload.fileName))
        for stale in try payloadFiles().dropLast(Self.payloadCapacity) {
            try FileManager.default.removeItem(at: stale)
        }
    }

    func payloads() throws -> [MetricKitPayload] {
        try payloadFiles().map { MetricKitPayload(fileName: $0.lastPathComponent, json: try Data(contentsOf: $0)) }
    }

    private func payloadFiles() throws -> [URL] {
        guard FileManager.default.fileExists(atPath: payloadDirectory.path) else { return [] }
        return try FileManager.default.contentsOfDirectory(at: payloadDirectory, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "json" }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
    }

    /// Creates the directory, kept out of device backups, on the first append of a launch.
    private func keptCounts() throws -> [URL: Int] {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        var excluded = URLResourceValues()
        excluded.isExcludedFromBackup = true
        var directory = directory
        try directory.setResourceValues(excluded)
        return try Dictionary(
            uniqueKeysWithValues: DictationRecordLines.files(in: directory).map { file in
                (file, try Data(contentsOf: file).split(separator: UInt8(ascii: "\n")).count)
            }
        )
    }
}

/// What a journal file, or a directory of them, holds: every record that reads, and how many
/// lines did not, as a line cut off mid-write or a record of another schema.
struct DictationRecordLines {
    let records: [DictationRecord]
    let unreadable: Int

    init(at url: URL) throws {
        let isDirectory = try url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory ?? false
        let files = isDirectory ? try Self.files(in: url) : [url]
        let decoder = DictationRecord.lineDecoder()
        var records: [DictationRecord] = []
        var unreadable = 0
        for file in files {
            for line in try Data(contentsOf: file).split(separator: UInt8(ascii: "\n")) {
                guard let record = try? decoder.decode(DictationRecord.self, from: line) else {
                    unreadable += 1
                    continue
                }
                records.append(record)
            }
        }
        self.records = records
        self.unreadable = unreadable
    }

    /// The journal's files, oldest month first.
    static func files(in directory: URL) throws -> [URL] {
        try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
            .filter { $0.lastPathComponent.hasPrefix("records-") && $0.pathExtension == "jsonl" }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
    }
}
