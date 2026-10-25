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
        var isAbandoned = false
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
            // answer(_:) or a cancel resumes this, and a failed waitUntilCalled() stops later parks.
            // swiftlint:disable:next tests_never_park_on_a_bare_continuation
            await withCheckedContinuation { park($0, onMainThread: onMainThread) }
        } onCancel: {
            cancelRead()
        }
    }

    /// Returns once `transcribe` has parked, so what the test does next happens with the read in
    /// flight. When no read comes it records a failure, and a later read returns late at once.
    @MainActor
    func waitUntilCalled(sourceLocation: SourceLocation = #_sourceLocation) async {
        if await waitUntil({ transcribes > 0 }, orRecord: "the recording engine was never asked to read", sourceLocation: sourceLocation) {
            return
        }
        calls.withLock { $0.isAbandoned = true }
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
        let parks = calls.withLock { calls -> Bool in
            calls.transcribes += 1
            calls.ranOnMainThread = onMainThread
            let parks = !calls.wasCancelled && !calls.isAbandoned
            if parks { calls.answering = continuation }
            return parks
        }
        if !parks { continuation.resume(returning: RecordingDecode.missing(.late)) }
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
