import Foundation
import Testing

@testable import WorkoutTracker

@MainActor
@Test func anExportArchivesTheJournalItsLabelsAndItsMetricKitPayloadsForReplay() async throws {
    let directory = FileManager.default.temporaryDirectory.appending(path: "dictation-export-\(UUID().uuidString)")
    defer { try? FileManager.default.removeItem(at: directory) }
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let app = try WorkoutApplication(environment: .inMemory(workbook: WorkbookScenario.freshBlock.workbook()))
    _ = try await app.selectSpreadsheet(id: "FIXTURE", title: "Fixture Training Log")
    let written = try DictationRecordFixtures.record(DictationRecordFixtures.lines[0])
    let september = try DictationRecordFixtures.cancelled(3, pressedAt: "2026-09-30T23:00:00Z")
    let hang = MetricKitPayload(kind: .diagnostics, endedAt: Date(timeIntervalSince1970: 1_780_000_000), json: Data(#"{"hang":1}"#.utf8))
    app.dictationJournal.append(september)
    app.dictationJournal.append(written)
    app.dictationJournal.keep(hang)
    _ = try app.log(try #require(SetAddress("w1d1.e0.s0")), setLog: "185x5@9")

    _ = try await app.exportDictations(into: directory)
    let archive = try await app.exportDictations(into: directory)

    #expect(archive.lastPathComponent == "Dictation Records.zip")
    #expect(try Data(contentsOf: archive).prefix(4) == Data([0x50, 0x4B, 0x03, 0x04]), "the archive is a zip")
    let folder = directory.appending(path: "Dictation Records")
    #expect(try DictationRecordLines.files(in: folder).map(\.lastPathComponent) == ["records-2026-09.jsonl", "records-2026-10.jsonl"])
    #expect(try DictationRecordLines(at: folder).records == [september, written])
    let labels = try DictationLabels(at: folder.appending(path: "labels.json"))
    #expect(labels.labels.map(\.setLog) == ["185x5@9"])
    #expect(try Data(contentsOf: folder.appending(path: "MetricKit/\(hang.fileName)")) == hang.json)
    let replay = try WorkoutApplication.dictationReplay(reading: folder, labels: folder.appending(path: "labels.json"))
    let lead = try #require(replay.versions.first?.rules["lead"]?.scored)
    #expect((lead.correct, lead.wrong, lead.nowrite, lead.unscored) == (0, 1, 0, 0), "185x5@8 was corrected to 185x5@9")
}
