import AVFoundation
import Testing

@testable import WorkoutTracker

/// `count` frames of a 440 Hz tone at 48 kHz on every channel, picking up where `start` left off.
private func tone(channels: AVAudioChannelCount, frames count: Int, from start: Int) throws -> AVAudioPCMBuffer {
    let format = try #require(AVAudioFormat(standardFormatWithSampleRate: 48_000, channels: channels))
    let buffer = try #require(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(count)))
    buffer.frameLength = AVAudioFrameCount(count)
    let data = try #require(buffer.floatChannelData)
    for channel in 0..<Int(channels) {
        for frame in 0..<count {
            data[channel][frame] = Float(sin(2 * Double.pi * 440 * Double(start + frame) / 48_000)) * 0.5
        }
    }
    return buffer
}

@Test(arguments: [1, 2] as [AVAudioChannelCount])
func aMicBufferConvertsToSixteenKilohertzMono(channels: AVAudioChannelCount) throws {
    let mic = try tone(channels: channels, frames: 4096, from: 0)
    let conversion = try #require(MicConversion.toRecording(from: mic.format))

    let converted = try #require(conversion.convert(mic))

    #expect(converted.format.sampleRate == Double(DictationRecorder.sampleRate))
    #expect(converted.format.channelCount == 1)
    #expect(converted.format.commonFormat == .pcmFormatFloat32)
}

/// The tone at 16 kHz, `delay` samples behind the mic, as the resampler's filter holds it back.
private func toneAtSixteenKilohertz(_ sample: Int, delay: Double) -> Float {
    Float(sin(2 * Double.pi * 440 * (Double(sample) - delay) / Double(DictationRecorder.sampleRate))) * 0.5
}

/// The widest gap between `samples` and the tone, `delay` behind, over `range`.
private func gap(_ samples: [Float], delay: Double, over range: Range<Int>) -> Float {
    range.map { abs(samples[$0] - toneAtSixteenKilohertz($0, delay: delay)) }.max() ?? .infinity
}

/// The recording is held against the tone itself, delayed as much as the first buffer's worth
/// shows the resampler delays it. Audio at another rate drifts from it, and a buffer repeated or
/// dropped jumps away from it.
@Test(arguments: [1, 2] as [AVAudioChannelCount])
func aPressOfMicBuffersRecordsAsOneUnbrokenToneAtSixteenKilohertz(channels: AVAudioChannelCount) throws {
    let buffers = 12
    let frames = 4096
    let first = try tone(channels: channels, frames: frames, from: 0)
    let conversion = try #require(MicConversion.toRecording(from: first.format))
    let recorder = DictationRecorder()

    conversion.record(first, into: recorder)
    for index in 1..<buffers {
        conversion.record(try tone(channels: channels, frames: frames, from: index * frames), into: recorder)
    }

    let samples = recorder.close().samples
    let expected = buffers * frames / 3
    #expect(abs(samples.count - expected) <= 64, "\(samples.count) samples, not about \(expected)")
    let settled = 100..<(frames / 3)
    let delay = try #require(
        stride(from: -8.0, to: 64, by: 0.05).min { gap(samples, delay: $0, over: settled) < gap(samples, delay: $1, over: settled) }
    )
    let widest = gap(samples, delay: delay, over: 100..<(samples.count - 100))
    #expect(widest < 0.01, "the recording strays \(widest) from the tone \(delay) samples behind")
}
