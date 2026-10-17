import Foundation
import Testing

@testable import WorkoutTracker

private let dictateURL = URL(string: "workouttracker://dictate")!
private let googleSignInURL = URL(string: "com.googleusercontent.apps.123-abc:/oauth2redirect/google?code=4")!

@Test func theDictateURLAsksToSayTheCurrentSet() {
    #expect(AppEntryRequest(url: dictateURL) == .dictateCurrentSet)
    #expect(AppEntryRequest(url: URL(string: "WorkoutTracker://Dictate")!) == .dictateCurrentSet)
}

@Test(
    "No other URL asks the app for anything",
    arguments: [
        googleSignInURL.absoluteString,
        "workouttracker://",
        "workouttracker://log",
        "workouttracker://dictate/now",
        "https://dictate",
        "dictate"
    ]
)
func noOtherURLAsksTheAppForAnything(url: String) {
    #expect(AppEntryRequest(url: URL(string: url)!) == nil)
}

@Test func theAppRegistersItsURLSchemeBesideGoogleSignIns() throws {
    let data = try Data(contentsOf: RepositoryFiles.existingURL(of: "App/Info.plist"))
    let plist = try #require(try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any])
    let urlTypes = try #require(plist["CFBundleURLTypes"] as? [[String: Any]])
    let schemes = urlTypes.flatMap { $0["CFBundleURLSchemes"] as? [String] ?? [] }

    #expect(schemes.contains(AppEntryRequest.urlScheme))
    #expect(schemes.contains("$(GID_REVERSED_CLIENT_ID)"))
}

@MainActor
@Test func aRequestIsTakenOnceHoweverOftenItArrives() {
    let entry = AppEntryInbox()

    entry.deliver(.dictateCurrentSet)
    entry.deliver(.dictateCurrentSet)

    #expect(entry.arrivals == 2)
    #expect(entry.take() == .dictateCurrentSet)
    #expect(entry.take() == nil)
}

@MainActor
@Test func onlyTheAppsOwnURLsReachTheInbox() {
    let entry = AppEntryInbox()

    #expect(!entry.receive(googleSignInURL))
    #expect(entry.pending == nil)
    #expect(entry.arrivals == 0)

    #expect(entry.receive(dictateURL))
    #expect(entry.pending == .dictateCurrentSet)
    #expect(entry.arrivals == 1)
}

@MainActor
@Test func aDiscardedRequestIsNeverTaken() {
    let entry = AppEntryInbox()
    entry.deliver(.dictateCurrentSet)

    entry.discard()

    #expect(entry.take() == nil)
}
