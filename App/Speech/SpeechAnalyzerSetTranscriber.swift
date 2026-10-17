import AVFoundation
import Speech

/// SpeechAnalyzer behind the Active Set Card's mic. SpeechTranscriber with alternatives where the
/// device has its model, otherwise DictationTranscriber. Neither runs in the Simulator.
@MainActor
final class SpeechAnalyzerSetTranscriber: SetTranscriber {
    private struct Listening {
        let engine: AVAudioEngine
        let analyzer: SpeechAnalyzer
        let input: AsyncStream<AnalyzerInput>.Continuation
        let segments: Task<TranscriptSegments, any Error>
    }

    /// Every Set Log is English and in pounds, whatever the phone's language.
    private static let locale = Locale(identifier: "en-US")

    private var listening: Listening?

    /// Asks for the microphone on the first press, and installs the speech model on first use.
    func start(hearing: @escaping @MainActor (String) -> Void) async throws(SetTranscriberError) {
        guard await AVAudioApplication.requestRecordPermission() else { throw .microphoneDenied }
        let (module, results) = try await Self.installedModule(hearing: hearing)
        guard let format = await SpeechAnalyzer.bestAvailableAudioFormat(compatibleWith: [module]) else {
            results.cancel()
            throw .unavailable
        }
        let analyzer = SpeechAnalyzer(modules: [module], options: .init(priority: .userInitiated, modelRetention: .lingering))
        let (stream, input) = AsyncStream.makeStream(of: AnalyzerInput.self)
        let engine = AVAudioEngine()
        let started = Listening(engine: engine, analyzer: analyzer, input: input, segments: results)
        do {
            try await analyzer.prepareToAnalyze(in: format)
            try Self.activateAudioSession()
            try Self.installTap(on: engine, converting: format, into: input)
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
            try await listening.analyzer.finalizeAndFinishThroughEndOfInput()
            segments = try await listening.segments.value
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
        await listening.analyzer.cancelAndFinishNow()
        listening.segments.cancel()
        Self.deactivateAudioSession()
    }

    private func stopCapture(_ listening: Listening) {
        listening.engine.inputNode.removeTap(onBus: 0)
        listening.engine.stop()
        listening.input.finish()
    }

    /// Volatile results caption the press while the athlete speaks; SpeechTranscriber's preset
    /// leaves them out.
    private static func installedModule(
        hearing: @escaping @MainActor (String) -> Void
    ) async throws(SetTranscriberError) -> (any SpeechModule, Task<TranscriptSegments, any Error>) {
        let module: any SpeechModule
        let results: Task<TranscriptSegments, any Error>
        if SpeechTranscriber.isAvailable, let locale = await SpeechTranscriber.supportedLocale(equivalentTo: locale) {
            let preset = SpeechTranscriber.Preset.transcriptionWithAlternatives
            let transcriber = SpeechTranscriber(
                locale: locale,
                transcriptionOptions: preset.transcriptionOptions,
                reportingOptions: preset.reportingOptions.union([.volatileResults]),
                attributeOptions: preset.attributeOptions
            )
            module = transcriber
            results = Task { try await segments(of: transcriber.results, hearing: hearing) }
        } else if let locale = await DictationTranscriber.supportedLocale(equivalentTo: locale) {
            let preset = DictationTranscriber.Preset.phrase
            let transcriber = DictationTranscriber(
                locale: locale,
                contentHints: preset.contentHints,
                transcriptionOptions: preset.transcriptionOptions,
                reportingOptions: preset.reportingOptions.union([.volatileResults, .alternativeTranscriptions]),
                attributeOptions: preset.attributeOptions
            )
            module = transcriber
            results = Task { try await segments(of: transcriber.results, hearing: hearing) }
        } else {
            throw .unavailable
        }
        do {
            if let installation = try await AssetInventory.assetInstallationRequest(supporting: [module]) {
                try await installation.downloadAndInstall()
            }
        } catch {
            results.cancel()
            throw .unavailable
        }
        return (module, results)
    }

    private static func segments<Results: AsyncSequence>(
        of results: Results,
        hearing: @MainActor (String) -> Void
    ) async throws -> TranscriptSegments where Results.Element: TranscribedPhrase {
        var segments = TranscriptSegments()
        for try await result in results {
            let phrase = TranscriptSegments.Segment(
                top: String(result.text.characters),
                alternatives: result.alternatives.map { String($0.characters) }
            )
            segments.receive(
                phrase,
                from: result.range.start.seconds,
                to: result.range.end.seconds,
                isFinal: result.isFinal
            )
            hearing(segments.heard)
        }
        return segments
    }

    private static func activateAudioSession() throws {
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playAndRecord, mode: .spokenAudio, options: [.duckOthers])
        try session.setActive(true, options: .notifyOthersOnDeactivation)
    }

    private static func deactivateAudioSession() {
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    /// The engine calls the tap on its realtime audio thread, where a main-actor closure traps, and
    /// SpeechAnalyzer takes only its own format, so each buffer is converted there.
    private nonisolated static func installTap(
        on engine: AVAudioEngine,
        converting analyzerFormat: AVAudioFormat,
        into input: AsyncStream<AnalyzerInput>.Continuation
    ) throws {
        let node = engine.inputNode
        let hardwareFormat = node.outputFormat(forBus: 0)
        guard let converter = AVAudioConverter(from: hardwareFormat, to: analyzerFormat) else { throw SetTranscriberError.failed }
        converter.primeMethod = .none
        node.installTap(onBus: 0, bufferSize: 4096, format: hardwareFormat) { buffer, _ in
            let ratio = analyzerFormat.sampleRate / hardwareFormat.sampleRate
            let capacity = AVAudioFrameCount((Double(buffer.frameLength) * ratio).rounded(.up))
            guard let converted = AVAudioPCMBuffer(pcmFormat: analyzerFormat, frameCapacity: capacity) else { return }
            var consumed = false
            let status = converter.convert(to: converted, error: nil) { _, inputStatus in
                defer { consumed = true }
                inputStatus.pointee = consumed ? .noDataNow : .haveData
                return consumed ? nil : buffer
            }
            if status != .error, converted.frameLength > 0 {
                input.yield(AnalyzerInput(buffer: converted))
            }
        }
    }
}

/// What SpeechTranscriber and DictationTranscriber each report for a phrase.
private protocol TranscribedPhrase: SpeechModuleResult {
    var text: AttributedString { get }
    var alternatives: [AttributedString] { get }
}

extension SpeechTranscriber.Result: TranscribedPhrase {}
extension DictationTranscriber.Result: TranscribedPhrase {}
