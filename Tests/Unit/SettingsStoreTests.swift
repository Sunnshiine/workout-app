import Foundation
import Testing

@testable import WorkoutTracker

@MainActor
@Test func isConfiguredRequiresSpreadsheetIdAndAuth() throws {
    let defaults = AppDefaults.inMemory()
    let store = SettingsStore(defaults: defaults)
    store.isSignedIn = true
    #expect(store.isConfigured == false)  // no Sheet yet
    store.setSpreadsheet(id: "SHEET123")
    #expect(store.spreadsheetId == "SHEET123")
    #expect(store.isConfigured == true)
    store.isSignedIn = false
    #expect(store.spreadsheetId == "SHEET123")
    #expect(store.isConfigured == false)
}

@MainActor
@Test func selectedSpreadsheetPersistsIdAndTitle() throws {
    let defaults = AppDefaults.inMemory()
    let store = SettingsStore(defaults: defaults)

    store.setSpreadsheet(id: "SHEET123", title: "Training Log")

    let reloaded = SettingsStore(defaults: defaults)
    #expect(reloaded.spreadsheetId == "SHEET123")
    #expect(reloaded.spreadsheetTitle == "Training Log")
}

@MainActor
@Test func newInstallSeedsSystemAppearance() throws {
    let defaults = AppDefaults.inMemory()
    let store = SettingsStore(defaults: defaults)

    #expect(store.appearance == .system)
    #expect(defaults.string(forKey: "appearance") == "system")
}

@MainActor
@Test func existingInstallWithoutAppearanceSeedsNight() throws {
    let defaults = AppDefaults.inMemory()
    defaults.set("SHEET123", forKey: "spreadsheetId")

    let store = SettingsStore(defaults: defaults)

    #expect(store.appearance == .night)
    #expect(defaults.string(forKey: "appearance") == "dark")
}

@MainActor
@Test func cachedInstallWithoutAppearanceSeedsNight() throws {
    let defaults = AppDefaults.inMemory()

    let store = SettingsStore(defaults: defaults, hasPriorAppState: true)

    #expect(store.appearance == .night)
    #expect(defaults.string(forKey: "appearance") == "dark")
}

@MainActor
@Test func invalidAppearanceFallsBackToNight() throws {
    let defaults = AppDefaults.inMemory()
    defaults.set("legacy", forKey: "appearance")

    let store = SettingsStore(defaults: defaults)

    #expect(store.appearance == .night)
    #expect(defaults.string(forKey: "appearance") == "dark")
}

@Test func appearancePickerOffersSystemLightAndNightInOrder() {
    #expect(AppearancePreference.allCases.map(\.label) == ["System", "Light", "Night"])
}

@MainActor
@Test(arguments: [("system", AppearancePreference.system), ("light", .light), ("dark", .night)])
func storedAppearanceLoadsAsItsOwnPreference(stored: String, expected: AppearancePreference) throws {
    let defaults = AppDefaults.inMemory()
    defaults.set("SHEET123", forKey: "spreadsheetId")
    defaults.set(stored, forKey: "appearance")

    #expect(SettingsStore(defaults: defaults).appearance == expected)
    #expect(defaults.string(forKey: "appearance") == stored)
}

@MainActor
@Test func appearancePersistsManualChoicesAndDoesNotReseed() throws {
    let defaults = AppDefaults.inMemory()
    let store = SettingsStore(defaults: defaults)

    store.setAppearance(.light)
    #expect(SettingsStore(defaults: defaults).appearance == .light)

    store.setAppearance(.night)
    #expect(SettingsStore(defaults: defaults).appearance == .night)

    store.setAppearance(.system)
    defaults.set("SHEET123", forKey: "spreadsheetId")
    #expect(SettingsStore(defaults: defaults).appearance == .system)
}

@MainActor
@Test func standardRestDurationPersistsRoundTrip() throws {
    let defaults = AppDefaults.inMemory()
    let store = SettingsStore(defaults: defaults)

    #expect(store.standardRestDuration == .standard)

    store.setStandardRestDuration(RestDurationSetting(seconds: 210))

    let reloaded = SettingsStore(defaults: defaults)
    #expect(reloaded.standardRestDuration == RestDurationSetting(seconds: 210))
}

@MainActor
@Test func supersetRestDurationPersistsRoundTrip() throws {
    let defaults = AppDefaults.inMemory()
    let store = SettingsStore(defaults: defaults)

    #expect(store.supersetRestDuration == .superset)

    store.setSupersetRestDuration(RestDurationSetting(seconds: 90))

    let reloaded = SettingsStore(defaults: defaults)
    #expect(reloaded.supersetRestDuration == RestDurationSetting(seconds: 90))
}

@MainActor
@Test func loadBasisLineStaysOffUntilDeveloperToolsTurnsItOnAndPersists() throws {
    let defaults = AppDefaults.inMemory()
    let store = SettingsStore(defaults: defaults)

    #expect(store.showsLoadBasis == false)

    store.setShowsLoadBasis(true)
    #expect(SettingsStore(defaults: defaults).showsLoadBasis == true)

    store.setShowsLoadBasis(false)
    #expect(SettingsStore(defaults: defaults).showsLoadBasis == false)
}

@MainActor
@Test(
    "Onboarding is needed only once the launch's sign-in restore has answered",
    arguments: [
        (restoredSignIn: Bool?.none, hasSheet: true, needsOnboarding: false),
        (nil, false, false),
        (false, true, true),
        (true, true, false),
        (true, false, true)
    ]
)
func onboardingIsNeededOnlyOnceTheSignInRestoreHasAnswered(restoredSignIn: Bool?, hasSheet: Bool, needsOnboarding: Bool) {
    let store = SettingsStore(defaults: .inMemory())
    if hasSheet {
        store.setSpreadsheet(id: "SHEET123", title: "Training Log")
    }

    if let restoredSignIn {
        store.isSignedIn = restoredSignIn
    }

    #expect(store.needsOnboarding == needsOnboarding)
}

@MainActor
@Test func signOutClearsAuthAndSpreadsheetSelection() throws {
    let defaults = AppDefaults.inMemory()
    let store = SettingsStore(defaults: defaults)
    store.isSignedIn = true
    store.setSpreadsheet(id: "SHEET123", title: "Training Log")

    store.signOut()

    #expect(store.isSignedIn == false)
    #expect(store.spreadsheetId == nil)
    #expect(store.spreadsheetTitle == nil)

    let reloaded = SettingsStore(defaults: defaults)
    #expect(reloaded.spreadsheetId == nil)
    #expect(reloaded.spreadsheetTitle == nil)
}
