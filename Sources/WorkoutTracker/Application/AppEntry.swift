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
    /// How long a request waits for the stage: long enough for a cold launch to show the Current
    /// Session, short enough that a later visit to the stage never starts the mic unasked.
    static let requestLifetime = Duration.seconds(10)

    private var arrival: (request: AppEntryRequest, at: Duration)?
    /// Counts every request the inbox holds, so the stage answers each one.
    private(set) var arrivals = 0
    /// Onboarding has no Session to listen on, so a request that meets it ends there.
    private var showsOnboarding = false
    @ObservationIgnored private let clock: any ListeningClock

    init(clock: any ListeningClock = ContinuousListeningClock()) {
        self.clock = clock
    }

    /// Nil once the request has waited `requestLifetime`.
    var pending: AppEntryRequest? {
        guard let arrival, clock.now - arrival.at < Self.requestLifetime else { return nil }
        return arrival.request
    }

    func deliver(_ request: AppEntryRequest) {
        guard !showsOnboarding else { return }
        arrival = (request, clock.now)
        arrivals += 1
    }

    /// False for a URL that is not the app's own, which belongs to whoever else handles URLs.
    func receive(_ url: URL) -> Bool {
        guard let request = AppEntryRequest(url: url) else { return false }
        deliver(request)
        return true
    }

    func take() -> AppEntryRequest? {
        defer { arrival = nil }
        return pending
    }

    /// A request still waiting when the app leaves the screen would otherwise open the mic long
    /// after the athlete asked.
    func discard() {
        arrival = nil
    }

    /// The app reports each time onboarding shows or goes. A request onboarding meets stays
    /// ended once a Sheet is chosen.
    func reportOnboarding(isShown: Bool) {
        showsOnboarding = isShown
        if isShown {
            discard()
        }
    }
}
