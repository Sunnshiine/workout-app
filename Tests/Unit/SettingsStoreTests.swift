import Foundation
import Testing

@testable import WorkoutTracker

@MainActor
@Test func isConfiguredRequiresSpreadsheetIdAndAuth() throws {
    let defaults = try #require(UserDefaults(suiteName: "test.\(UUID())"))
    let store = SettingsStore(defaults: defaults)
    store.isSignedIn = true
    #expect(store.isConfigured == false)  // no URL yet
    store.setSheetURL("https://docs.google.com/spreadsheets/d/SHEET123/edit")
    #expect(store.spreadsheetId == "SHEET123")
    #expect(store.isConfigured == true)
}

@MainActor
@Test func selectedSpreadsheetPersistsIdAndTitle() throws {
    let defaults = try #require(UserDefaults(suiteName: "test.\(UUID())"))
    let store = SettingsStore(defaults: defaults)

    store.setSpreadsheet(id: "SHEET123", title: "Training Log")

    let reloaded = SettingsStore(defaults: defaults)
    #expect(reloaded.spreadsheetId == "SHEET123")
    #expect(reloaded.spreadsheetTitle == "Training Log")
}
