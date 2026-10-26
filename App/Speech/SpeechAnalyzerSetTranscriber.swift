import ActivityKit
import AVFoundation
import Speech
import UIKit

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
    func start(
        hearing: @escaping @MainActor (String) -> Void,
        recording recorder: DictationRecorder
    ) async throws(SetTranscriberStartError) {
        guard await AVAudioApplication.requestRecordPermission() else { throw SetTranscriberStartError(.microphoneDenied) }
        let speech: SpeechListening
        do throws(SetTranscriberError) {
            speech = try await SpeechListening.start(hearing: hearing, installing: { _ in })
        } catch {
            throw SetTranscriberStartError(error)
        }
        guard let format = await SpeechAnalyzer.bestAvailableAudioFormat(compatibleWith: [speech.module]) else {
            await speech.cancel()
            throw SetTranscriberStartError(.unavailable)
        }
        let analyzer = speech.analyzer
        let (stream, input) = AsyncStream.makeStream(of: AnalyzerInput.self)
        let engine = AVAudioEngine()
        let started = Listening(engine: engine, input: input, speech: speech)
        var step = "prepareToAnalyze"
        do {
            try await analyzer.prepareToAnalyze(in: format)
            step = "activateAudioSession"
            try Self.activateAudioSession()
            step = "installTap"
            try Self.installTap(on: engine, converting: format, into: input, recording: recorder)
            step = "engineStart"
            engine.prepare()
            try engine.start()
            step = "analyzerStart"
            try await analyzer.start(inputSequence: stream)
        } catch {
            let refusal = Self.refusal(at: step, error, hearing: engine.inputNode.outputFormat(forBus: 0))
            await stop(started)
            throw SetTranscriberStartError(.failed, refusal: refusal)
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

    /// Read before the session is deactivated, so it shows what the start found.
    private static func refusal(at step: String, _ error: any Error, hearing mic: AVAudioFormat) -> MicStartRefusal {
        let session = AVAudioSession.sharedInstance()
        return MicStartRefusal(
            step: step,
            error: "\(describing(error)), mic \(Int(mic.sampleRate)) Hz \(mic.channelCount) ch",
            appState: appState(UIApplication.shared.applicationState),
            otherAudioPlaying: session.isOtherAudioPlaying,
            liveActivities: Activity<WorkoutActivityAttributes>.activities.map { String(describing: $0.activityState) }
        )
    }

    private static func appState(_ state: UIApplication.State) -> String {
        switch state {
        case .active: "active"
        case .inactive: "inactive"
        case .background: "background"
        @unknown default: "unknown"
        }
    }

    /// An audio session status code is four characters packed in an Int32, such as `!rec`.
    private static func describing(_ error: any Error) -> String {
        if let error = error as? SetTranscriberError { return "SetTranscriberError.\(error.rawValue)" }
        let error = error as NSError
        let code = UInt32(bitPattern: Int32(truncatingIfNeeded: error.code))
        let bytes = [24, 16, 8, 0].map { UInt8((code >> $0) & 0xFF) }
        let printable = bytes.allSatisfy { (0x20...0x7E).contains($0) }
        let fourCharacters = printable ? String(bytes: bytes, encoding: .ascii).map { " '\($0)'" } : nil
        return "\(error.domain) \(error.code)\(fourCharacters ?? "")"
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
