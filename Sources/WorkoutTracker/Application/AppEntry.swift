import Foundation
import Observation

/// What the athlete asked for from outside the app, for the card to answer: Log a Set pressed
/// with the app in front, the Lock Screen's Start, or the `workouttracker://dictate` URL that tests
/// and `simctl` open.
enum AppEntryRequest: Equatable, Sendable {
    /// Open the Current Session's active Set and listen for its Spoken Set.
    case dictateCurrentSet
    /// Open the stage on this Set and start its Effort Countdown, as a tap on its card's control does.
    case startTimedEffort(CountdownRun.Owner)
}

extension AppEntryRequest {
    enum Kind: Equatable, Sendable {
        case dictation
        case start
    }

    var kind: Kind {
        switch self {
        case .dictateCurrentSet: .dictation
        case .startTimedEffort: .start
        }
    }

    static let urlScheme = "workouttracker"

    /// Nil for any URL that is not the app's own, such as Google sign-in's redirect.
    init?(url: URL) {
        guard url.scheme?.lowercased() == Self.urlScheme, url.path().isEmpty else { return nil }
        switch url.host()?.lowercased() {
        case "dictate":
            self = .dictateCurrentSet
        case "start":
            guard let owner = Self.owner(in: url) else { return nil }
            self = .startTimedEffort(owner)
        default:
            return nil
        }
    }

    var url: URL {
        var components = URLComponents()
        components.scheme = Self.urlScheme
        switch self {
        case .dictateCurrentSet:
            components.host = "dictate"
        case .startTimedEffort(let owner):
            components.host = "start"
            components.queryItems = [
                URLQueryItem(name: "session", value: owner.session.storageValue),
                URLQueryItem(name: "exercise", value: "\(owner.set.exerciseOrder)"),
                URLQueryItem(name: "set", value: "\(owner.set.setIndex)")
            ]
        }
        // swiftlint:disable:next force_unwrapping
        return components.url!
    }

    private static func owner(in url: URL) -> CountdownRun.Owner? {
        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        func value(_ name: String) -> String? { items.first { $0.name == name }?.value }
        guard let session = value("session").flatMap(SessionCoordinate.init(storageValue:)),
            let exerciseOrder = value("exercise").flatMap({ Int($0) }),
            let setIndex = value("set").flatMap({ Int($0) })
        else { return nil }
        return CountdownRun.Owner(session: session, set: ActiveSetID(exerciseOrder: exerciseOrder, setIndex: setIndex))
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
    /// Counts each answer that heads for the mic, which closes whatever covers the stage.
    private(set) var coverClosings = 0
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

    func closeCovers() {
        coverClosings += 1
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
