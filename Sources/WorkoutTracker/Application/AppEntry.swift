import Foundation
import Observation

/// What the athlete asked for from outside the app: the Action button, Siri, or the Live Activity.
enum AppEntryRequest: Equatable, Sendable {
    /// Open the Current Session's active Set and listen for its Spoken Set.
    case dictateCurrentSet
}

extension AppEntryRequest {
    static let urlScheme = "workouttracker"

    /// Nil for any URL that is not the app's own, such as Google sign-in's redirect.
    init?(url: URL) {
        guard url.scheme?.lowercased() == Self.urlScheme, url.host()?.lowercased() == "dictate", url.path().isEmpty else {
            return nil
        }
        self = .dictateCurrentSet
    }
}

/// Holds a request from outside the app until the Session stage takes it, so a request that
/// arrives before the stage can answer it, as on a cold launch, still reaches it.
@MainActor
@Observable
final class AppEntryInbox {
    private(set) var pending: AppEntryRequest?
    /// Counts every request, taken or not, so whatever covers the stage closes for each one.
    private(set) var arrivals = 0

    func deliver(_ request: AppEntryRequest) {
        pending = request
        arrivals += 1
    }

    /// False for a URL that is not the app's own, which belongs to whoever else handles URLs.
    func receive(_ url: URL) -> Bool {
        guard let request = AppEntryRequest(url: url) else { return false }
        deliver(request)
        return true
    }

    func take() -> AppEntryRequest? {
        defer { pending = nil }
        return pending
    }

    /// A request still waiting when the app leaves the screen would otherwise open the mic long
    /// after the athlete asked.
    func discard() {
        pending = nil
    }
}
