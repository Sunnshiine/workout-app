import Foundation

/// The result of fetching a single tab under the fill's retry policy.
///
/// A **failed** tab — transient 429/5xx failures that outlast the backoff budget — is a
/// first-class outcome the history fill can halt on, deliberately distinct from a tab that
/// simply fetched **empty**. A silent skip would leave a hole that corrupts the fill's
/// coverage count (ADR-0012); surfacing the failure lets the caller stop and resume later.
enum TabFetchOutcome: Sendable, Equatable {
    /// The tab's grid, however small — an empty grid still counts as a successful read.
    case fetched(SheetSnapshot)
    /// Every retry was spent against a transient server error; the tab could not be read.
    case failed
}

/// Retry-with-backoff for a single tab read, independent of how the fetched grid is stored.
///
/// Transient failures (HTTP 429 and 5xx) are retried on an exponential schedule — 1s, 2s,
/// 4s, 8s — after which the tab is reported `.failed` rather than throwing. Non-transient
/// errors (auth, malformed responses) are never retried and propagate to the caller so a
/// misconfiguration surfaces immediately instead of stalling behind pointless waits.
struct SheetsBackoff: Sendable {
    /// The delays applied before each successive retry; its count is the retry budget.
    static let defaultSchedule: [Duration] = [.seconds(1), .seconds(2), .seconds(4), .seconds(8)]

    private let schedule: [Duration]
    private let sleep: @Sendable (Duration) async throws -> Void

    init(
        schedule: [Duration] = SheetsBackoff.defaultSchedule,
        sleep: @escaping @Sendable (Duration) async throws -> Void = { try await Task.sleep(for: $0) }
    ) {
        self.schedule = schedule
        self.sleep = sleep
    }

    /// Runs `operation`, retrying transient failures on the backoff schedule.
    ///
    /// - Returns: `.fetched` on success (including an empty snapshot), or `.failed` once the
    ///   schedule is exhausted against a transient error.
    /// - Throws: any non-transient error, without retrying.
    func fetch(_ operation: @Sendable () async throws -> SheetSnapshot) async throws -> TabFetchOutcome {
        var retry = 0
        while true {
            do {
                return .fetched(try await operation())
            } catch let error where Self.isTransient(error) {
                guard retry < schedule.count else { return .failed }
                try await sleep(schedule[retry])
                retry += 1
            }
        }
    }

    /// Transient failures worth retrying: quota throttling (429) and server-side errors (5xx).
    static func isTransient(_ error: Error) -> Bool {
        guard case let SheetsError.http(status) = error else { return false }
        return status == 429 || (500..<600).contains(status)
    }
}
