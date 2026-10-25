import Foundation
import Synchronization

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
        var awaitingAppend: CheckedContinuation<Void, Never>?
    }

    private let state = Mutex(State())

    /// Nil until a write began.
    var ranOnMainThread: Bool? { state.withLock { $0.ranOnMainThread } }
    var appends: Int { state.withLock { $0.appends } }

    func append(_ record: DictationRecord) async {
        let onMainThread = pthread_main_np() != 0
        await withCheckedContinuation { continuation in
            let (test, isHeld) = state.withLock { state -> (CheckedContinuation<Void, Never>?, Bool) in
                state.appends += 1
                state.ranOnMainThread = onMainThread
                state.kept.append(record)
                if state.isHeld { state.parked.append(continuation) }
                defer { state.awaitingAppend = nil }
                return (state.awaitingAppend, state.isHeld)
            }
            if !isHeld { continuation.resume() }
            test?.resume()
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
    func waitUntilAppending() async {
        await withCheckedContinuation { continuation in
            let appending = state.withLock { state -> Bool in
                guard state.appends == 0 else { return true }
                state.awaitingAppend = continuation
                return false
            }
            if appending { continuation.resume() }
        }
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
