import Synchronization

/// One press's audio as the recording engine reads it: 16 kHz mono, from the mic going live to the
/// end of listening, at most `DictationRecorder.capacity`.
struct DictationRecording: Equatable, Sendable {
    let samples: [Float]
    /// Audio past the capacity was dropped.
    let isTruncated: Bool
}

/// Collects a press's audio on the mic's tap thread. `SetDictation` makes one per press and closes
/// it the instant the press ends, before the live engine finalizes.
final class DictationRecorder: Sendable {
    static let sampleRate = 16_000
    /// Whisper reads one 30-second window.
    static let capacity: Duration = .seconds(30)
    private static let sampleCapacity = Int(capacity.components.seconds) * sampleRate

    private struct Buffer {
        var samples: [Float]
        var isClosed = false
        var isTruncated = false
    }

    private let buffer: Mutex<Buffer>

    init() {
        var samples: [Float] = []
        // Reserved to capacity here, so the tap thread never allocates.
        samples.reserveCapacity(Self.sampleCapacity)
        buffer = Mutex(Buffer(samples: samples))
    }

    /// On the audio thread, with 16 kHz mono samples. Dropped once closed, and past the capacity.
    func append(_ samples: UnsafeBufferPointer<Float>) {
        buffer.withLock { buffer in
            guard !buffer.isClosed else { return }
            let room = Self.sampleCapacity - buffer.samples.count
            if samples.count > room {
                buffer.isTruncated = true
            }
            buffer.samples.append(contentsOf: samples.prefix(room))
        }
    }

    /// The audio so far, still recording.
    func snapshot() -> DictationRecording {
        buffer.withLock { DictationRecording(samples: $0.samples, isTruncated: $0.isTruncated) }
    }

    /// Ends the recording; later appends are dropped. A second close returns the same audio.
    func close() -> DictationRecording {
        buffer.withLock { buffer in
            buffer.isClosed = true
            return DictationRecording(samples: buffer.samples, isTruncated: buffer.isTruncated)
        }
    }
}
