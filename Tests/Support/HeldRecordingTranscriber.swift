import Foundation
import Synchronization
import Testing

@testable import WorkoutTracker

/// A recording engine that parks `transcribe` until the test answers it, and tells the test when it
/// was asked, where it ran, and whether the read was cancelled.
final class HeldRecordingTranscriber: RecordingTranscriber {
    private struct Calls {
        var expectations = 0
        var transcribes = 0
        var ranOnMainThread: Bool?
        var wasCancelled = false
        var answering: CheckedContinuation<RecordingDecode, Never>?
        var awaitingCall: CheckedContinuation<Void, Never>?
    }

    private let calls = Mutex(Calls())

    let readiness = SpeechModelState.ready

    /// How many presses began.
    var expectations: Int { calls.withLock { $0.expectations } }
    var transcribes: Int { calls.withLock { $0.transcribes } }
    /// Nil until `transcribe` ran.
    var ranOnMainThread: Bool? { calls.withLock { $0.ranOnMainThread } }
    var wasCancelled: Bool { calls.withLock { $0.wasCancelled } }

    func expectRecording() {
        calls.withLock { $0.expectations += 1 }
    }

    @concurrent func transcribe(_ recording: DictationRecording) async -> RecordingDecode {
        let onMainThread = pthread_main_np() != 0
        return await withTaskCancellationHandler {
            // answer(_:) or the cancel handler resumes the read.
            // swiftlint:disable:next tests_never_park_on_a_bare_continuation
            await withCheckedContinuation { park($0, onMainThread: onMainThread) }
        } onCancel: {
            cancelRead()
        }
    }

    /// Returns once `transcribe` has parked, so what the test does next happens with the read in
    /// flight.
    func waitUntilCalled() async {
        // The read runs off the main actor, so a waitUntil count does not bound it (#1105).
        // swiftlint:disable:next tests_never_park_on_a_bare_continuation
        await withCheckedContinuation { continuation in
            let called = calls.withLock { calls -> Bool in
                guard calls.transcribes == 0 else { return true }
                calls.awaitingCall = continuation
                return false
            }
            if called { continuation.resume() }
        }
    }

    /// Lets the parked read return `decode`.
    func answer(_ decode: RecordingDecode) {
        let answering = calls.withLock { calls -> CheckedContinuation<RecordingDecode, Never>? in
            defer { calls.answering = nil }
            return calls.answering
        }
        answering?.resume(returning: decode)
    }

    /// Parks under the lock the cancel takes, so a cancel that lands first still answers the read.
    private func park(_ continuation: CheckedContinuation<RecordingDecode, Never>, onMainThread: Bool) {
        let (test, cancelled) = calls.withLock { calls -> (CheckedContinuation<Void, Never>?, Bool) in
            calls.transcribes += 1
            calls.ranOnMainThread = onMainThread
            if !calls.wasCancelled { calls.answering = continuation }
            defer { calls.awaitingCall = nil }
            return (calls.awaitingCall, calls.wasCancelled)
        }
        if cancelled { continuation.resume(returning: RecordingDecode.missing(.late)) }
        test?.resume()
    }

    private func cancelRead() {
        let answering = calls.withLock { calls -> CheckedContinuation<RecordingDecode, Never>? in
            calls.wasCancelled = true
            defer { calls.answering = nil }
            return calls.answering
        }
        answering?.resume(returning: RecordingDecode.missing(.late))
    }
}
