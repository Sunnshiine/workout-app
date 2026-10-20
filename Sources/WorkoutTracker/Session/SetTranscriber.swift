import Foundation

/// Why a transcriber returned no transcript.
enum SetTranscriberError: String, Error, Equatable, Sendable, Codable {
    case microphoneDenied
    /// The device has no on-device speech model for the locale, or its assets would not install.
    case unavailable
    case nothingHeard
    case failed
}

/// Speech-to-text heard while the athlete speaks: the caption, the auto-stop, and the Live
/// Transcript, from `start` until `finish`.
@MainActor
protocol SetTranscriber: AnyObject {
    /// Returns once the microphone is live. `hearing` receives the whole transcript so far each
    /// time it changes, and `recording` the mic's audio at 16 kHz mono, until `finish` or `cancel`
    /// returns. A start that throws leaves nothing listening.
    func start(hearing: @escaping @MainActor (String) -> Void, recording: DictationRecorder) async throws(SetTranscriberError)
    /// Stops listening, even when it throws, and returns the transcripts heard, the most likely
    /// first.
    func finish() async throws(SetTranscriberError) -> [String]
    func cancel() async
}

/// The time hands-free Dictation reads: how long a request to listen waits for the stage, and
/// when the athlete has stopped talking.
@MainActor
protocol ListeningClock: AnyObject {
    /// The time since a fixed origin.
    var now: Duration { get }
    /// The wall-clock time at `now`, which dates a press's Dictation Record.
    var date: Date { get }
    /// Returns at `deadline`, or at once when it has passed.
    func sleep(until deadline: Duration) async
}

@MainActor
final class ContinuousListeningClock: ListeningClock {
    private let origin = ContinuousClock.now

    var now: Duration { ContinuousClock.now - origin }
    var date: Date { Date() }

    func sleep(until deadline: Duration) async {
        try? await Task.sleep(until: origin + deadline, clock: .continuous)
    }
}
