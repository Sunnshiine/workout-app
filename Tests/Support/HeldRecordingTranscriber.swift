import Foundation
import Synchronization
import Testing

@testable import WorkoutTracker

/// A recording engine that parks each `transcribe` until the test answers it, and tells the test
/// when it was asked, what it was given, where it ran, and whether the read was cancelled.
final class HeldRecordingTranscriber: RecordingTranscriber {
    private struct Read {
        let samples: Int
        var answering: CheckedContinuation<RecordingDecode, Never>?
        var wasCancelled = false
    }

    private struct Calls {
        var expectations = 0
        var reads: [Read] = []
        var parked = 0
        var ranOnMainThread: Bool?
        var awaitingCall: (parked: Int, continuation: CheckedContinuation<Void, Never>)?
    }

    private let calls = Mutex(Calls())

    let readiness = SpeechModelState.ready

    /// How many presses began.
    var expectations: Int { calls.withLock { $0.expectations } }
    var transcribes: Int { calls.withLock { $0.reads.count } }
    /// How many samples each read was given, oldest first.
    var samplesRead: [Int] { calls.withLock { $0.reads.map(\.samples) } }
    /// Nil until `transcribe` ran.
    var ranOnMainThread: Bool? { calls.withLock { $0.ranOnMainThread } }
    /// Whether any read was cancelled.
    var wasCancelled: Bool { calls.withLock { $0.reads.contains(where: \.wasCancelled) } }

    func expectRecording() {
        calls.withLock { $0.expectations += 1 }
    }

    @concurrent func transcribe(_ recording: DictationRecording) async -> RecordingDecode {
        let onMainThread = pthread_main_np() != 0
        let read = calls.withLock { calls -> Int in
            calls.reads.append(Read(samples: recording.samples.count))
            return calls.reads.count - 1
        }
        return await withTaskCancellationHandler {
            // answer(_:) or the cancel handler resumes the read.
            // swiftlint:disable:next tests_never_park_on_a_bare_continuation
            await withCheckedContinuation { park($0, read: read, onMainThread: onMainThread) }
        } onCancel: {
            cancel(read: read)
        }
    }

    /// Returns once the first `transcribe` has parked, so what the test does next happens with the
    /// read in flight.
    func waitUntilCalled() async {
        await waitUntilCalled(times: 1)
    }

    /// Returns once `count` reads have parked.
    func waitUntilCalled(times count: Int) async {
        // The read runs off the main actor, so a waitUntil count does not bound it (#1105).
        // swiftlint:disable:next tests_never_park_on_a_bare_continuation
        await withCheckedContinuation { continuation in
            let called = calls.withLock { calls -> Bool in
                guard calls.parked < count else { return true }
                calls.awaitingCall = (count, continuation)
                return false
            }
            if called { continuation.resume() }
        }
    }

    /// Lets the latest parked read return `decode`.
    func answer(_ decode: RecordingDecode) {
        let answering = calls.withLock { calls -> CheckedContinuation<RecordingDecode, Never>? in
            guard let read = calls.reads.lastIndex(where: { $0.answering != nil }) else { return nil }
            defer { calls.reads[read].answering = nil }
            return calls.reads[read].answering
        }
        answering?.resume(returning: decode)
    }

    /// Lets the latest parked read return `transcript`.
    func answer(hearing transcript: String) {
        answer(RecordingDecode(result: .heard(transcript, segments: []), timings: nil))
    }

    /// Parks under the lock the cancel takes, so a cancel that lands first still answers the read.
    private func park(_ continuation: CheckedContinuation<RecordingDecode, Never>, read: Int, onMainThread: Bool) {
        let (test, cancelled) = calls.withLock { calls -> (CheckedContinuation<Void, Never>?, Bool) in
            calls.parked += 1
            calls.ranOnMainThread = onMainThread
            if !calls.reads[read].wasCancelled { calls.reads[read].answering = continuation }
            let cancelled = calls.reads[read].wasCancelled
            guard let awaiting = calls.awaitingCall, calls.parked >= awaiting.parked else { return (nil, cancelled) }
            calls.awaitingCall = nil
            return (awaiting.continuation, cancelled)
        }
        if cancelled { continuation.resume(returning: RecordingDecode.missing(.late)) }
        test?.resume()
    }

    private func cancel(read: Int) {
        let answering = calls.withLock { calls -> CheckedContinuation<RecordingDecode, Never>? in
            calls.reads[read].wasCancelled = true
            defer { calls.reads[read].answering = nil }
            return calls.reads[read].answering
        }
        answering?.resume(returning: RecordingDecode.missing(.late))
    }
}
