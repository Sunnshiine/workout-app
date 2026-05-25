import Foundation
import Testing

@testable import WorkoutTracker

@MainActor
@Test func isConfiguredRequiresSpreadsheetIdAndAuth() {
    let store = SettingsStore(defaults: UserDefaults(suiteName: "test.\(UUID())")!)
    store.isSignedIn = true
    #expect(store.isConfigured == false)  // no URL yet
    store.setSheetURL("https://docs.google.com/spreadsheets/d/SHEET123/edit")
    #expect(store.spreadsheetId == "SHEET123")
    #expect(store.isConfigured == true)
}
