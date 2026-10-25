import AVFoundation

/// One converter from the mic's format to the format an engine reads, kept across a press's
/// buffers so a resampler carries its state from each buffer to the next. The mic's tap calls it
/// on its realtime audio thread.
struct MicConversion {
    private let converter: AVAudioConverter
    private let format: AVAudioFormat
    private let ratio: Double

    init?(from source: AVAudioFormat, to format: AVAudioFormat) {
        guard let converter = AVAudioConverter(from: source, to: format) else { return nil }
        converter.primeMethod = .none
        self.converter = converter
        self.format = format
        ratio = format.sampleRate / source.sampleRate
    }

    /// Into the 16 kHz mono the recording engine reads and `DictationRecorder` collects.
    static func toRecording(from source: AVAudioFormat) -> MicConversion? {
        AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: Double(DictationRecorder.sampleRate),
            channels: 1,
            interleaved: false
        ).flatMap { MicConversion(from: source, to: $0) }
    }

    /// Nil when the converter fails or has nothing to give for this buffer yet.
    func convert(_ buffer: AVAudioPCMBuffer) -> AVAudioPCMBuffer? {
        let capacity = AVAudioFrameCount((Double(buffer.frameLength) * ratio).rounded(.up))
        guard let converted = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: capacity) else { return nil }
        var consumed = false
        let status = converter.convert(to: converted, error: nil) { _, inputStatus in
            defer { consumed = true }
            inputStatus.pointee = consumed ? .noDataNow : .haveData
            return consumed ? nil : buffer
        }
        return status != .error && converted.frameLength > 0 ? converted : nil
    }

    /// Converts `buffer` and appends its first channel, the only one a recording conversion has.
    func record(_ buffer: AVAudioPCMBuffer, into recorder: DictationRecorder) {
        guard let converted = convert(buffer), let samples = converted.floatChannelData else { return }
        recorder.append(UnsafeBufferPointer(start: samples[0], count: Int(converted.frameLength)))
    }
}
