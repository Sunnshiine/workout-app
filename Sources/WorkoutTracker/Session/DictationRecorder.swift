import Foundation
import Synchronization

/// One press's audio as the recording engine reads it: 16 kHz mono, from the mic going live to the
/// end of listening, at most `DictationRecorder.capacity`.
struct DictationRecording: Equatable, Sendable {
    let samples: [Float]
    /// Audio past the capacity was dropped.
    let isTruncated: Bool
}

/// Collects a press's audio on the mic's tap thread, with the level of each whole
/// `VoiceActivity.frameSamples` of it. `SetDictation` makes one per press and closes it the instant
/// the press ends, before the live engine finalizes.
final class DictationRecorder: Sendable {
    static let sampleRate = 16_000
    /// Whisper reads one 30-second window.
    static let capacity: Duration = .seconds(30)
    private static let sampleCapacity = Int(capacity.components.seconds) * sampleRate

    private struct Buffer {
        var samples: [Float]
        /// One per whole frame of `samples`, in dBFS.
        var levels: [Float]
        /// The frame `levels` has yet to take, across appends that split it.
        var frameSumOfSquares: Double = 0
        var frameFill = 0
        var isClosed = false
        var isTruncated = false
    }

    private let buffer: Mutex<Buffer>

    init() {
        var samples: [Float] = []
        var levels: [Float] = []
        // Reserved to capacity here, so the tap thread never allocates.
        samples.reserveCapacity(Self.sampleCapacity)
        levels.reserveCapacity(Self.sampleCapacity / VoiceActivity.frameSamples)
        buffer = Mutex(Buffer(samples: samples, levels: levels))
    }

    /// On the audio thread, with 16 kHz mono samples. Dropped once closed, and past the capacity.
    func append(_ samples: UnsafeBufferPointer<Float>) {
        buffer.withLock { buffer in
            guard !buffer.isClosed else { return }
            let room = Self.sampleCapacity - buffer.samples.count
            if samples.count > room {
                buffer.isTruncated = true
            }
            let kept = samples.prefix(room)
            buffer.samples.append(contentsOf: kept)
            for sample in kept {
                buffer.frameSumOfSquares += Double(sample * sample)
                buffer.frameFill += 1
                guard buffer.frameFill == VoiceActivity.frameSamples else { continue }
                let rms = (buffer.frameSumOfSquares / Double(VoiceActivity.frameSamples)).squareRoot()
                buffer.levels.append(Float(20 * log10(rms + 1e-9)))
                buffer.frameSumOfSquares = 0
                buffer.frameFill = 0
            }
        }
    }

    /// The audio so far, still recording. A copy, so the next append never copies on the tap thread.
    func snapshot() -> DictationRecording {
        buffer.withLock { DictationRecording(samples: $0.samples.withUnsafeBufferPointer(Array.init), isTruncated: $0.isTruncated) }
    }

    /// The level of each whole frame recorded so far, from the `frame`th on. A copy, as `snapshot`.
    func levels(from frame: Int) -> [Float] {
        buffer.withLock { buffer in
            buffer.levels.withUnsafeBufferPointer { Array($0[min(frame, $0.count)...]) }
        }
    }

    /// Ends the recording; later appends are dropped. A second close returns the same audio.
    func close() -> DictationRecording {
        buffer.withLock { buffer in
            buffer.isClosed = true
            return DictationRecording(samples: buffer.samples, isTruncated: buffer.isTruncated)
        }
    }
}
