import Foundation
import Testing

@testable import WorkoutTracker

@MainActor
@Test func anAppendReturnsWhileTheDiskIsStalledAndARecordsReadWaitsForIt() async throws {
    let store = HeldDictationRecordStore()
    let journal = DictationJournal(store: store)
    let first = try DictationRecordFixtures.cancelled(1, pressedAt: "2026-10-19T17:00:00Z")
    let second = try DictationRecordFixtures.cancelled(2, pressedAt: "2026-10-19T17:01:00Z")

    journal.append(first)
    journal.append(second)
    await store.waitUntilAppending()
    let reading = Task { try await journal.records() }

    #expect(store.ranOnMainThread == false, "the journal writes off the main thread")
    #expect(store.appends == 1, "the second write waits behind the stalled first")
    store.release()
    #expect(try await reading.value.map(\.id) == [first.id, second.id])
}

@Test func anInMemoryJournalKeepsWhatItIsHandedInOrder() async throws {
    let journal = DictationJournal(storage: .inMemory)
    let records = try DictationRecordFixtures.lines.map(DictationRecordFixtures.record)

    for record in records {
        journal.append(record)
    }

    #expect(try await journal.records() == records)
}

private func temporaryDirectory() -> URL {
    FileManager.default.temporaryDirectory.appending(path: "dictation-records-\(UUID().uuidString)")
}

@Test func filesKeepAMonthEachAndDropTheOldestMonthPastTheirCapacity() async throws {
    let directory = temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let files = DictationRecordFiles(directory: directory, keeping: 2)
    let september = try DictationRecordFixtures.cancelled(1, pressedAt: "2026-09-30T23:59:00Z")
    let october = try DictationRecordFixtures.cancelled(2, pressedAt: "2026-10-01T00:01:00Z")
    let later = try DictationRecordFixtures.cancelled(3, pressedAt: "2026-10-19T17:00:00Z")

    try await files.append(september)
    try await files.append(october)
    #expect(try DictationRecordLines.files(in: directory).map(\.lastPathComponent) == ["records-2026-09.jsonl", "records-2026-10.jsonl"])
    try await files.append(later)

    #expect(try DictationRecordLines.files(in: directory).map(\.lastPathComponent) == ["records-2026-10.jsonl"])
    #expect(try await files.records() == [october, later])
    #expect(try directory.resourceValues(forKeys: [.isExcludedFromBackupKey]).isExcludedFromBackup == true)
}

@Test func filesMakeTheirDirectoryAndIgnoreFilesThatAreNotRecords() async throws {
    let parent = temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: parent) }
    let directory = parent.appending(path: "Application Support/Dictation Records")
    let files = DictationRecordFiles(directory: directory, keeping: DictationRecordFiles.capacity)
    let record = try DictationRecordFixtures.cancelled(1, pressedAt: "2026-10-19T17:00:00Z")

    try await files.append(record)
    for stray in ["export.jsonl", "records-2026-10.txt"] {
        try Data(DictationRecordFixtures.lines[0].utf8).write(to: directory.appending(path: stray))
    }

    #expect(try await files.records() == [record])
}

@Test func aLineThatDoesNotReadIsCountedAndSkipped() async throws {
    let directory = temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let files = DictationRecordFiles(directory: directory, keeping: DictationRecordFiles.capacity)
    let record = try DictationRecordFixtures.cancelled(1, pressedAt: "2026-10-19T17:00:00Z")
    try await files.append(record)
    let file = directory.appending(path: "records-2026-10.jsonl")
    let handle = try FileHandle(forWritingTo: file)
    try handle.seekToEnd()
    try handle.write(contentsOf: Data(#"{"schema":1,"id":"cut off mid-wr"#.utf8))
    try handle.close()

    let lines = try DictationRecordLines(at: file)

    #expect(lines.records == [record])
    #expect(lines.unreadable == 1)
    #expect(try DictationRecordLines(at: directory).records == [record])
}

private struct BrokenDisk: Error {}

/// A store whose disk refuses every write and read.
private actor BrokenDictationRecordStore: DictationRecordStore {
    private(set) var appends = 0

    func append(_ record: DictationRecord) throws {
        appends += 1
        throw BrokenDisk()
    }

    func records() throws -> [DictationRecord] {
        throw BrokenDisk()
    }

    func keep(_ payload: MetricKitPayload) throws {
        appends += 1
        throw BrokenDisk()
    }

    func payloads() throws -> [MetricKitPayload] {
        throw BrokenDisk()
    }
}

@Test func aWriteTheDiskRefusesIsDroppedAndTheJournalKeepsWriting() async throws {
    let store = BrokenDictationRecordStore()
    let journal = DictationJournal(store: store)

    journal.append(try DictationRecordFixtures.cancelled(1, pressedAt: "2026-10-19T17:00:00Z"))
    journal.keep(MetricKitPayload(kind: .metrics, endedAt: Date(timeIntervalSince1970: 1_780_000_000), json: Data()))
    journal.append(try DictationRecordFixtures.cancelled(2, pressedAt: "2026-10-19T17:01:00Z"))

    await #expect(throws: BrokenDisk.self) { try await journal.records() }
    #expect(await store.appends == 3)
}

private let payloadDay = Date(timeIntervalSince1970: 1_780_000_000)

private func payload(_ kind: MetricKitPayload.Kind, day: Int) -> MetricKitPayload {
    MetricKitPayload(kind: kind, endedAt: payloadDay.addingTimeInterval(Double(day) * 86_400), json: Data(#"{"day":\#(day)}"#.utf8))
}

@Test func aJournalKeepsMetricKitPayloadsBesideItsRecordsInOneRead() async throws {
    let journal = DictationJournal(storage: .inMemory)
    let record = try DictationRecordFixtures.record(DictationRecordFixtures.lines[0])

    journal.keep(payload(.metrics, day: 1))
    journal.append(record)
    journal.keep(payload(.diagnostics, day: 0))

    let kept = try await journal.kept()
    #expect(kept.records == [record])
    #expect(kept.payloads.map(\.fileName) == ["2026-05-28T20-26-40Z-diagnostics.json", "2026-05-29T20-26-40Z-metrics.json"])
}

@Test func filesKeepTheNewestMetricKitPayloadsInTheirOwnFolderAndOneOfAPayloadDeliveredTwice() async throws {
    let directory = temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let files = DictationRecordFiles(directory: directory, keeping: 2)

    for day in 0...DictationRecordFiles.payloadCapacity {
        try await files.keep(payload(.metrics, day: day))
    }
    try await files.keep(payload(.metrics, day: DictationRecordFiles.payloadCapacity))

    let kept = try await files.payloads()
    #expect(kept.count == DictationRecordFiles.payloadCapacity)
    #expect(kept.first == payload(.metrics, day: 1))
    #expect(kept.last == payload(.metrics, day: DictationRecordFiles.payloadCapacity))
    #expect(FileManager.default.fileExists(atPath: directory.appending(path: "MetricKit/\(kept[0].fileName)").path))
    #expect(try await files.records().isEmpty)
    #expect(try directory.resourceValues(forKeys: [.isExcludedFromBackupKey]).isExcludedFromBackup == true)
}
