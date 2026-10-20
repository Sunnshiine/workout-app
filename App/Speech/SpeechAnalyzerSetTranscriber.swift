import AVFoundation
import Speech

/// The mic every Dictation listens with, heard by the model `OnDeviceSpeech` chooses and configures.
@MainActor
final class SpeechAnalyzerSetTranscriber: SetTranscriber {
    private struct Listening {
        let engine: AVAudioEngine
        let input: AsyncStream<AnalyzerInput>.Continuation
        let speech: SpeechListening
    }

    private var listening: Listening?

    /// Asks for the microphone on the first press, and installs the speech model on first use.
    func start(hearing: @escaping @MainActor (String) -> Void, recording recorder: DictationRecorder) async throws(SetTranscriberError) {
        guard await AVAudioApplication.requestRecordPermission() else { throw .microphoneDenied }
        let speech = try await SpeechListening.start(hearing: hearing, installing: { _ in })
        guard let format = await SpeechAnalyzer.bestAvailableAudioFormat(compatibleWith: [speech.module]) else {
            await speech.cancel()
            throw .unavailable
        }
        let analyzer = speech.analyzer
        let (stream, input) = AsyncStream.makeStream(of: AnalyzerInput.self)
        let engine = AVAudioEngine()
        let started = Listening(engine: engine, input: input, speech: speech)
        do {
            try await analyzer.prepareToAnalyze(in: format)
            try Self.activateAudioSession()
            try Self.installTap(on: engine, converting: format, into: input, recording: recorder)
            engine.prepare()
            try engine.start()
            try await analyzer.start(inputSequence: stream)
        } catch {
            await stop(started)
            throw .failed
        }
        listening = started
    }

    func finish() async throws(SetTranscriberError) -> [String] {
        guard let listening else { throw .failed }
        self.listening = nil
        let segments: TranscriptSegments
        do {
            stopCapture(listening)
            try await listening.speech.analyzer.finalizeAndFinishThroughEndOfInput()
            segments = try await listening.speech.segments.value
            Self.deactivateAudioSession()
        } catch {
            await stop(listening)
            throw .failed
        }
        guard !segments.candidates.isEmpty else { throw .nothingHeard }
        return segments.candidates
    }

    func cancel() async {
        guard let listening else { return }
        self.listening = nil
        await stop(listening)
    }

    private func stop(_ listening: Listening) async {
        stopCapture(listening)
        await listening.speech.cancel()
        Self.deactivateAudioSession()
    }

    private func stopCapture(_ listening: Listening) {
        listening.engine.inputNode.removeTap(onBus: 0)
        listening.engine.stop()
        listening.input.finish()
    }

    private static func activateAudioSession() throws {
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playAndRecord, mode: .spokenAudio, options: [.duckOthers])
        try session.setActive(true, options: .notifyOthersOnDeactivation)
    }

    private static func deactivateAudioSession() {
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    /// The engine calls the tap on its realtime audio thread, where a main-actor closure traps.
    /// SpeechAnalyzer takes only its own format and the recording engine only 16 kHz mono, so each
    /// buffer is converted there twice, once for each.
    private nonisolated static func installTap(
        on engine: AVAudioEngine,
        converting analyzerFormat: AVAudioFormat,
        into input: AsyncStream<AnalyzerInput>.Continuation,
        recording recorder: DictationRecorder
    ) throws {
        let node = engine.inputNode
        let hardwareFormat = node.outputFormat(forBus: 0)
        guard let toAnalyzer = MicConversion(from: hardwareFormat, to: analyzerFormat),
            let toRecording = MicConversion.toRecording(from: hardwareFormat)
        else { throw SetTranscriberError.failed }
        node.installTap(onBus: 0, bufferSize: 4096, format: hardwareFormat) { buffer, _ in
            if let converted = toAnalyzer.convert(buffer) {
                input.yield(AnalyzerInput(buffer: converted))
            }
            toRecording.record(buffer, into: recorder)
        }
    }
}
