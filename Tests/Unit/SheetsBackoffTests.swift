import Foundation
import Testing

@testable import WorkoutTracker

/// Records the backoff delays the client asks to sleep for, so tests observe the
/// retry schedule without waiting on the wall clock.
private final class SleepRecorder: @unchecked Sendable {
    private(set) var delays: [Duration] = []

    func sleep(_ duration: Duration) async throws {
        delays.append(duration)
    }
}

/// Counts operation invocations while yielding a scripted sequence of results.
private final class ScriptedFetch: @unchecked Sendable {
    private var results: [Result<SheetSnapshot, Error>]
    private(set) var callCount = 0

    init(_ results: [Result<SheetSnapshot, Error>]) {
        self.results = results
    }

    func run() async throws -> SheetSnapshot {
        callCount += 1
        // Once a single result remains it repeats, so an "always fails" script is one element.
        let result = results.count > 1 ? results.removeFirst() : results[0]
        return try result.get()
    }
}

@Test func backoffRetriesTransientFailuresThenReturnsFetchedSnapshot() async throws {
    let recorder = SleepRecorder()
    let snapshot = SheetSnapshot(values: [["Squat"]])
    let fetch = ScriptedFetch([
        .failure(SheetsError.http(503)),
        .failure(SheetsError.http(429)),
        .success(snapshot)
    ])
    let backoff = SheetsBackoff(sleep: recorder.sleep)

    let outcome = try await backoff.fetch(fetch.run)

    #expect(outcome == .fetched(snapshot))
    #expect(recorder.delays == [.seconds(1), .seconds(2)])
    #expect(fetch.callCount == 3)
}

@Test func backoffExhaustsScheduleThenFailsTheTab() async throws {
    let recorder = SleepRecorder()
    let fetch = ScriptedFetch([.failure(SheetsError.http(429))])
    let backoff = SheetsBackoff(sleep: recorder.sleep)

    let outcome = try await backoff.fetch(fetch.run)

    #expect(outcome == .failed)
    #expect(recorder.delays == [.seconds(1), .seconds(2), .seconds(4), .seconds(8)])
    #expect(fetch.callCount == 5)
}

@Test func backoffRetriesEveryServerErrorStatus() async throws {
    for status in [429, 500, 502, 503, 504] {
        let recorder = SleepRecorder()
        let fetch = ScriptedFetch([
            .failure(SheetsError.http(status)),
            .success(SheetSnapshot(values: []))
        ])
        let backoff = SheetsBackoff(sleep: recorder.sleep)

        let outcome = try await backoff.fetch(fetch.run)

        #expect(outcome == .fetched(SheetSnapshot(values: [])))
        #expect(recorder.delays == [.seconds(1)])
    }
}

@Test func backoffDoesNotRetryNonTransientErrors() async throws {
    let recorder = SleepRecorder()
    let fetch = ScriptedFetch([.failure(SheetsError.http(403))])
    let backoff = SheetsBackoff(sleep: recorder.sleep)

    await #expect(throws: SheetsError.http(403)) {
        _ = try await backoff.fetch(fetch.run)
    }
    #expect(recorder.delays.isEmpty)
    #expect(fetch.callCount == 1)
}

@Test func backoffDoesNotRetryAuthErrors() async throws {
    let recorder = SleepRecorder()
    let fetch = ScriptedFetch([.failure(SheetsError.notAuthorized)])
    let backoff = SheetsBackoff(sleep: recorder.sleep)

    await #expect(throws: SheetsError.notAuthorized) {
        _ = try await backoff.fetch(fetch.run)
    }
    #expect(recorder.delays.isEmpty)
    #expect(fetch.callCount == 1)
}

@Test func backoffTreatsAnEmptySnapshotAsFetchedNotFailed() async throws {
    let recorder = SleepRecorder()
    let empty = SheetSnapshot(values: [])
    let fetch = ScriptedFetch([.success(empty)])
    let backoff = SheetsBackoff(sleep: recorder.sleep)

    let outcome = try await backoff.fetch(fetch.run)

    #expect(outcome == .fetched(empty))
    #expect(outcome != .failed)
    #expect(recorder.delays.isEmpty)
    #expect(fetch.callCount == 1)
}
