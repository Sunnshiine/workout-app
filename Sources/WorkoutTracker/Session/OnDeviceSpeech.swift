import AVFoundation
import Speech

/// The on-device speech-to-text every Dictation hears through, from the mic or from a recording.
/// Neither model runs in the Simulator.
@available(iOS 26, macOS 26, *)
enum OnDeviceSpeech: Equatable {
    /// SpeechTranscriber, with alternatives, where the device has its model.
    case transcriber(Locale)
    case dictation(Locale)

    /// Every Set Log is English and in pounds, whatever the phone's language.
    static let locale = Locale(identifier: "en-US")

    /// SpeechTranscriber where the device supports the locale, otherwise DictationTranscriber.
    init?(transcriber: Locale?, dictation: Locale?) {
        if let transcriber {
            self = .transcriber(transcriber)
            return
        }
        guard let dictation else { return nil }
        self = .dictation(dictation)
    }

    static func supported() async -> OnDeviceSpeech? {
        let transcriber = SpeechTranscriber.isAvailable ? await SpeechTranscriber.supportedLocale(equivalentTo: locale) : nil
        return OnDeviceSpeech(transcriber: transcriber, dictation: await DictationTranscriber.supportedLocale(equivalentTo: locale))
    }

    /// Volatile results caption the press while the athlete speaks; SpeechTranscriber's preset
    /// leaves them out.
    @MainActor
    func listening(hearing: @escaping @MainActor (String) -> Void) -> SpeechListening {
        let module: any SpeechModule
        let segments: Task<TranscriptSegments, any Error>
        switch self {
        case .transcriber(let locale):
            let preset = SpeechTranscriber.Preset.transcriptionWithAlternatives
            let transcriber = SpeechTranscriber(
                locale: locale,
                transcriptionOptions: preset.transcriptionOptions,
                reportingOptions: preset.reportingOptions.union([.volatileResults]),
                attributeOptions: preset.attributeOptions
            )
            module = transcriber
            segments = Task { try await Self.segments(of: transcriber.results, hearing: hearing) }
        case .dictation(let locale):
            let preset = DictationTranscriber.Preset.phrase
            let transcriber = DictationTranscriber(
                locale: locale,
                contentHints: preset.contentHints,
                transcriptionOptions: preset.transcriptionOptions,
                reportingOptions: preset.reportingOptions.union([.volatileResults, .alternativeTranscriptions]),
                attributeOptions: preset.attributeOptions
            )
            module = transcriber
            segments = Task { try await Self.segments(of: transcriber.results, hearing: hearing) }
        }
        return SpeechListening(module: module, segments: segments)
    }

    @MainActor
    static func segments<Results: AsyncSequence>(
        of results: Results,
        hearing: @MainActor (String) -> Void
    ) async throws -> TranscriptSegments where Results.Element: TranscribedPhrase {
        var segments = TranscriptSegments()
        for try await result in results {
            let phrase = TranscriptSegments.Segment(
                top: String(result.text.characters),
                alternatives: result.alternatives.map { String($0.characters) }
            )
            segments.receive(phrase, from: result.range.start.seconds, to: result.range.end.seconds, isFinal: result.isFinal)
            hearing(segments.heard)
        }
        return segments
    }
}

/// One speech model reading one analyzer's input, from the mic or a recording, into the phrases
/// it heard.
@available(iOS 26, macOS 26, *)
@MainActor
struct SpeechListening {
    let module: any SpeechModule
    let analyzer: SpeechAnalyzer
    /// Ends once the analyzer finishes.
    let segments: Task<TranscriptSegments, any Error>

    init(module: any SpeechModule, segments: Task<TranscriptSegments, any Error>) {
        self.module = module
        self.segments = segments
        analyzer = SpeechAnalyzer(modules: [module], options: .init(priority: .userInitiated, modelRetention: .lingering))
    }

    /// Installs the speech model on first use, reporting the fraction installed to `installing`.
    static func start(
        hearing: @escaping @MainActor (String) -> Void,
        installing: @escaping @Sendable (Double) -> Void
    ) async throws(SetTranscriberError) -> SpeechListening {
        guard let speech = await OnDeviceSpeech.supported() else { throw .unavailable }
        let listening = speech.listening(hearing: hearing)
        try await listening.installAssets(reporting: installing)
        return listening
    }

    /// The transcripts heard in a recording, the most likely first, by the model and configuration
    /// the mic listens with; none when nothing was said.
    static func transcripts(
        of recording: AVAudioFile,
        installing: @escaping @Sendable (Double) -> Void
    ) async throws(SetTranscriberError) -> [String] {
        try await start(hearing: { _ in }, installing: installing).transcripts(of: recording)
    }

    /// `transcripts(of:installing:)` with the recording fed in the mic tap's buffers at the pace it
    /// was spoken, so each caption arrives when a press would show it.
    static func transcripts(
        playing recording: AVAudioFile,
        installing: @escaping @Sendable (Double) -> Void
    ) async throws(SetTranscriberError) -> (candidates: [String], captions: [HearReport.Caption]) {
        let clock = ContinuousClock()
        var playedAt: ContinuousClock.Instant?
        var captions: [HearReport.Caption] = []
        let listening = try await start(
            hearing: { heard in
                guard let playedAt, heard != captions.last?.heard else { return }
                captions.append(HearReport.Caption(atMs: (clock.now - playedAt).wholeMilliseconds, heard: heard))
            },
            installing: installing
        )
        do {
            guard let format = await SpeechAnalyzer.bestAvailableAudioFormat(compatibleWith: [listening.module]),
                let conversion = MicConversion(from: recording.processingFormat, to: format)
            else { throw SetTranscriberError.unavailable }
            try await listening.analyzer.prepareToAnalyze(in: format)
            let (stream, input) = AsyncStream.makeStream(of: AnalyzerInput.self)
            try await listening.analyzer.start(inputSequence: stream)
            let started = clock.now
            playedAt = started
            for (index, buffer) in try tapBuffers(of: recording).enumerated() {
                if let converted = conversion.convert(buffer) { input.yield(AnalyzerInput(buffer: converted)) }
                try await clock.sleep(until: started + tapInterval * (index + 1))
            }
            input.finish()
            try await listening.analyzer.finalizeAndFinishThroughEndOfInput()
            return (try await listening.segments.value.candidates, captions)
        } catch {
            await listening.cancel()
            throw .failed
        }
    }

    /// The mic tap's 4096 frames at the phone's 48 kHz.
    private static let tapInterval = Duration.seconds(4096.0 / 48_000)

    private static func tapBuffers(of recording: AVAudioFile) throws -> [AVAudioPCMBuffer] {
        let frames = AVAudioFrameCount(recording.processingFormat.sampleRate * 4096 / 48_000)
        var buffers: [AVAudioPCMBuffer] = []
        while recording.framePosition < recording.length {
            guard let buffer = AVAudioPCMBuffer(pcmFormat: recording.processingFormat, frameCapacity: frames) else { break }
            try recording.read(into: buffer, frameCount: frames)
            buffers.append(buffer)
        }
        return buffers
    }

    func cancel() async {
        await analyzer.cancelAndFinishNow()
        segments.cancel()
    }

    private func installAssets(reporting: @escaping @Sendable (Double) -> Void) async throws(SetTranscriberError) {
        do {
            let installation = try await AssetInventory.assetInstallationRequest(supporting: [module])
            let progress = installation?.progress.observe(\.fractionCompleted) { progress, _ in reporting(progress.fractionCompleted) }
            defer { progress?.invalidate() }
            try await installation?.downloadAndInstall()
        } catch {
            await cancel()
            throw .unavailable
        }
    }

    private func transcripts(of recording: AVAudioFile) async throws(SetTranscriberError) -> [String] {
        do {
            return try await segments(of: recording).candidates
        } catch {
            await cancel()
            throw .failed
        }
    }

    private func segments(of recording: AVAudioFile) async throws -> TranscriptSegments {
        guard let end = try await analyzer.analyzeSequence(from: recording) else {
            // A recording with no audio leaves nothing to finalize, and the results of an analyzer
            // cancelled after it never end until their task is cancelled too (measured on macOS 27).
            await cancel()
            return TranscriptSegments()
        }
        try await analyzer.finalizeAndFinish(through: end)
        return try await segments.value
    }
}

/// What SpeechTranscriber and DictationTranscriber each report for a phrase.
@available(iOS 26, macOS 26, *)
protocol TranscribedPhrase: SpeechModuleResult {
    var text: AttributedString { get }
    var alternatives: [AttributedString] { get }
}

@available(iOS 26, macOS 26, *)
extension SpeechTranscriber.Result: TranscribedPhrase {}

@available(iOS 26, macOS 26, *)
extension DictationTranscriber.Result: TranscribedPhrase {}
