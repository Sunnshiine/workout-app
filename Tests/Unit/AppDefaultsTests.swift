import Foundation
import Testing

@testable import WorkoutTracker

private func makeTemporaryDirectory() throws -> URL {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent("app-defaults-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    return directory
}

@MainActor
@Test func aFileBackingReopenedAtTheSameURLReadsBackWhatWasWritten() throws {
    let directory = try makeTemporaryDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let url = directory.appendingPathComponent("settings.json")

    let first = try AppDefaults.file(url)
    first.set("SHEET123", forKey: "spreadsheetId")
    first.set("Training Log", forKey: "spreadsheetTitle")
    first.set(8, forKey: "advancedToOrderV2_Block 27")
    first.removeValue(forKey: "spreadsheetTitle")

    let reopened = try AppDefaults.file(url)
    #expect(reopened.keys == ["spreadsheetId", "advancedToOrderV2_Block 27"])
    #expect(reopened.string(forKey: "spreadsheetId") == "SHEET123")
    #expect(reopened.integer(forKey: "advancedToOrderV2_Block 27") == 8)
}

@MainActor
@Test func twoInMemoryBackingsShareNothing() {
    let written = AppDefaults.inMemory()
    let other = AppDefaults.inMemory()

    written.set("SHEET123", forKey: "spreadsheetId")

    #expect(written.string(forKey: "spreadsheetId") == "SHEET123")
    #expect(other.hasValue(forKey: "spreadsheetId") == false)
}

@MainActor
@Test func theDeviceBackingStoresTheSameTypesInStandardUserDefaults() {
    let device = AppDefaults.device()
    let stringKey = "AppDefaultsTests.string.\(UUID().uuidString)"
    let intKey = "AppDefaultsTests.int.\(UUID().uuidString)"
    defer {
        UserDefaults.standard.removeObject(forKey: stringKey)
        UserDefaults.standard.removeObject(forKey: intKey)
    }

    device.set("SHEET123", forKey: stringKey)
    device.set(8, forKey: intKey)

    #expect(UserDefaults.standard.object(forKey: stringKey) as? String == "SHEET123")
    #expect(UserDefaults.standard.object(forKey: intKey) as? Int == 8)
    #expect(AppDefaults.device().string(forKey: stringKey) == "SHEET123")
    #expect(device.integer(forKey: intKey) == 8)
    #expect(device.keys.isSuperset(of: [stringKey, intKey]))

    device.removeValue(forKey: intKey)
    #expect(device.hasValue(forKey: intKey) == false)
    #expect(device.integer(forKey: intKey) == nil)
}

@MainActor
@Test func aWrongTypedValueReadsAsAbsent() {
    let defaults = AppDefaults.inMemory()
    defaults.set("3", forKey: "standardRestDurationSeconds")

    #expect(defaults.integer(forKey: "standardRestDurationSeconds") == nil)
    #expect(defaults.string(forKey: "standardRestDurationSeconds") == "3")
}

@MainActor
@Test func aFileHoldingInvalidJSONIsRefused() throws {
    let directory = try makeTemporaryDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let url = directory.appendingPathComponent("settings.json")
    try Data("{ \"spreadsheetId\": ".utf8).write(to: url)

    #expect(throws: DecodingError.self) { try AppDefaults.file(url) }
}
