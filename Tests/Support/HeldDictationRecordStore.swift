import Foundation
import Synchronization
import Testing

@testable import WorkoutTracker

/// A record store whose writes park until the test lets them through, as a disk that has stalled,
/// and that tells the test where they ran.
final class HeldDictationRecordStore: DictationRecordStore {
    private struct State {
        var kept: [DictationRecord] = []
        var isHeld = true
        var appends = 0
        var ranOnMainThread: Bool?
        var parked: [CheckedContinuation<Void, Never>] = []
    }

    private let state = Mutex(State())

    /// Nil until a write began.
    var ranOnMainThread: Bool? { state.withLock { $0.ranOnMainThread } }
    var appends: Int { state.withLock { $0.appends } }

    func append(_ record: DictationRecord) async {
        let onMainThread = pthread_main_np() != 0
        // release() lets every parked write through, and a failed waitUntilAppending() calls it.
        // swiftlint:disable:next tests_never_park_on_a_bare_continuation
        await withCheckedContinuation { continuation in
            let isHeld = state.withLock { state -> Bool in
                state.appends += 1
                state.ranOnMainThread = onMainThread
                state.kept.append(record)
                if state.isHeld { state.parked.append(continuation) }
                return state.isHeld
            }
            if !isHeld { continuation.resume() }
        }
    }

    func records() -> [DictationRecord] {
        state.withLock { $0.kept }
    }

    func keep(_ payload: MetricKitPayload) {}

    func payloads() -> [MetricKitPayload] {
        []
    }

    /// Returns once a write has parked, so what the test does next happens with the disk stalled.
    /// When no write comes it records a failure and releases the store, so a late write cannot park.
    @MainActor
    func waitUntilAppending(sourceLocation: SourceLocation = #_sourceLocation) async {
        if await waitUntil({ appends > 0 }, orRecord: "no write reached the store", sourceLocation: sourceLocation) {
            return
        }
        release()
    }

    /// Lets every parked write, and every later one, through.
    func release() {
        let parked = state.withLock { state -> [CheckedContinuation<Void, Never>] in
            state.isHeld = false
            defer { state.parked = [] }
            return state.parked
        }
        for continuation in parked {
            continuation.resume()
        }
    }
}
