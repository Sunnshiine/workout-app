import Foundation
import Hub
import Network
import Synchronization
import UIKit
@preconcurrency import WhisperKit

/// The recording engine, prompted Whisper small. The one file that imports WhisperKit, so its types
/// never leave here. `SpeechModelPlan` decides every step of the model's lifecycle, and this actor
/// only carries them out, all of it off the main actor.
actor WhisperEngine: RecordingTranscriber {
    enum Models: Sendable {
        /// Application Support, downloaded there on a network that costs nothing.
        case applicationSupport
        #if DEBUG
            /// A Hugging Face download folder already holding the model and its tokenizer, as the
            /// Simulator proof launch reads it. Never downloaded into or written to.
            case host(URL)
        #endif
    }

    private struct Status {
        var state = SpeechModelState.absent
        var downloaded = 0.0
    }

    /// A loaded model, and the decode options with the prompt tokenized for it.
    private struct Pipe {
        let kit: WhisperKit
        let options: DecodingOptions
    }

    private let store: SpeechModelStore
    /// Written only as events are applied, in order. Read without waiting, from any thread.
    private let status = Mutex(Status())
    private let events: AsyncStream<SpeechModelEvent>.Continuation
    /// Applies `events` in the order they came. Set once, the instant the actor exists.
    private let running = Mutex<Task<Void, Never>?>(nil)
    private let network = NWPathMonitor()
    private let observers: Mutex<[any NSObjectProtocol]>

    private var pipe: Pipe?
    /// The download, specialization, or load in flight. Each waits for the one before it.
    private var working: Task<Void, Never>?
    /// Counts the work started, so work the model has moved on from reports nothing.
    private var attempt = 0
    /// Decodes run one at a time, since the actor is reentrant across WhisperKit's awaits and one
    /// WhisperKit must not decode twice at once.
    private var decoding: Task<RecordingDecode, Never>?
    /// Models let go, each once the decode in flight when it went is done.
    private var releasing: Task<Void, Never>?
    private var idle: Task<Void, Never>?

    init(models: Models) {
        let store = SpeechModelStore(models)
        self.store = store
        let (stream, events) = AsyncStream.makeStream(of: SpeechModelEvent.self)
        self.events = events
        observers = Mutex(Self.observePressure(into: events))
        let network = network
        network.pathUpdateHandler = { path in events.yield(.network(NetworkCost(path))) }
        running.withLock { running in
            running = Task { [weak self] in
                // Reads the disk here rather than on the caller's thread, and before any network
                // event, so a model already on disk is never downloaded again.
                events.yield(.launched(store.stored()))
                if store.downloads {
                    network.start(queue: DispatchQueue(label: "WhisperEngine.network", qos: .utility))
                }
                for await event in stream {
                    await self?.apply(event)
                }
            }
        }
    }

    deinit {
        events.finish()
        network.cancel()
        observers.withLock { $0.forEach(NotificationCenter.default.removeObserver) }
    }

    #if DEBUG
        /// The files a host folder lacks for the engine to load from it.
        static func missingFiles(inHost folder: URL) -> [URL] {
            SpeechModelStore(.host(folder)).missingFiles
        }
    #endif

    nonisolated var readiness: SpeechModelState {
        status.withLock(\.state)
    }

    /// The Settings row's words for where the model stands.
    nonisolated var caption: String {
        status.withLock { SpeechModelPlan.caption($0.state, downloaded: $0.downloaded) }
    }

    nonisolated func expectRecording() {
        events.yield(.pressBegan)
    }

    func transcribe(_ recording: DictationRecording) async -> RecordingDecode {
        // Never WhisperKit's own inline load, which would hide seconds inside the press.
        guard let pipe, readiness == .ready else { return .missing(.modelNotReady(readiness)) }
        guard ProcessInfo.processInfo.thermalState != .critical else { return .missing(.tooHot) }
        let asked = ContinuousClock.now
        let previous = decoding
        let decode = Task {
            _ = await previous?.value
            return await self.decode(recording, with: pipe, queued: .now - asked)
        }
        decoding = decode
        return await withTaskCancellationHandler {
            await decode.value
        } onCancel: {
            decode.cancel()
        }
    }

    private func decode(_ recording: DictationRecording, with pipe: Pipe, queued: Duration) async -> RecordingDecode {
        let interval = SpeechModelInterval("Decode")
        defer { interval.end() }
        do {
            let results: [TranscriptionResult] = try await pipe.kit.transcribe(
                audioArray: recording.samples,
                decodeOptions: pipe.options
            )
            return Self.reading(results, queued: queued)
        } catch {
            return .missing(.failed(String(describing: error)))
        }
    }

    private static func reading(_ results: [TranscriptionResult], queued: Duration) -> RecordingDecode {
        let text = results.map(\.text).joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)
        let segments = results.flatMap(\.segments).map {
            SegmentScore(
                avgLogprob: $0.avgLogprob,
                compressionRatio: $0.compressionRatio,
                noSpeechProb: $0.noSpeechProb,
                temperature: $0.temperature
            )
        }
        return RecordingDecode(
            result: .heard(text, segments: segments),
            timings: results.first.map { timings($0.timings, queued: queued) }
        )
    }

    /// `tokens` counts decoder steps, the prompt's included, since a prompt turns off prefill.
    private static func timings(_ timings: TranscriptionTimings, queued: Duration) -> DecodeTimings {
        DecodeTimings(
            queued: queued,
            melSpectrogram: .seconds(timings.logmels),
            encoding: .seconds(timings.encoding),
            decodingLoop: .seconds(timings.decodingLoop),
            total: .seconds(timings.fullPipeline),
            tokens: Int(timings.totalDecodingLoops),
            fallbacks: Int(timings.totalDecodingFallbacks)
        )
    }

    // MARK: Lifecycle

    private func apply(_ event: SpeechModelEvent) {
        let step = status.withLock { status in
            let step = SpeechModelPlan.next(status.state, on: event)
            status.state = step.state
            return step
        }
        if event == .pressBegan || event == .finished(.load, succeeded: true) {
            restartIdle()
        }
        switch step.command {
        case .start(let work): start(work)
        case .stopDownload: working?.cancel()
        case .unload: unload()
        case .none: break
        }
    }

    private func start(_ work: SpeechModelWork) {
        attempt += 1
        let previous = working
        working = Task { [attempt] in
            await previous?.value
            let succeeded = await self.perform(work, attempt: attempt)
            self.finish(work, succeeded: succeeded, attempt: attempt)
        }
    }

    private func perform(_ work: SpeechModelWork, attempt: Int) async -> Bool {
        switch work {
        case .download: await store.download { [weak self] fraction in self?.downloaded(fraction) }
        case .specialize: await specialize()
        case .load: await load(attempt: attempt)
        }
    }

    private func finish(_ work: SpeechModelWork, succeeded: Bool, attempt: Int) {
        guard attempt == self.attempt else { return }
        events.yield(.finished(work, succeeded: succeeded))
    }

    private nonisolated func downloaded(_ fraction: Double) {
        status.withLock { $0.downloaded = fraction }
    }

    /// Core ML compiles each model for this chip, one in memory at a time, and lets it go.
    private func specialize() async -> Bool {
        let interval = SpeechModelInterval("Specialize")
        defer { interval.end() }
        do {
            _ = try await WhisperKit(store.config(prewarm: true))
            try store.markSpecialized()
            return true
        } catch {
            return false
        }
    }

    private func load(attempt: Int) async -> Bool {
        let interval = SpeechModelInterval("Load")
        defer { interval.end() }
        guard let kit = try? await WhisperKit(store.config(prewarm: false)), let options = Self.options(for: kit) else {
            return false
        }
        // An unload, or a later load, came while this one ran.
        guard attempt == self.attempt, readiness == .loading else {
            await kit.unloadModels()
            return false
        }
        pipe = Pipe(kit: kit, options: options)
        return true
    }

    private func unload() {
        idle?.cancel()
        guard let pipe else { return }
        self.pipe = nil
        let decoding = decoding
        let previous = releasing
        releasing = Task {
            await previous?.value
            _ = await decoding?.value
            await pipe.kit.unloadModels()
        }
    }

    private func restartIdle() {
        idle?.cancel()
        idle = Task { [events] in
            guard (try? await Task.sleep(for: SpeechModelPlan.idleUnload)) != nil else { return }
            events.yield(.pressure(.idle))
        }
    }

    private static func observePressure(into events: AsyncStream<SpeechModelEvent>.Continuation) -> [any NSObjectProtocol] {
        let center = NotificationCenter.default
        return [
            center.addObserver(forName: UIApplication.didReceiveMemoryWarningNotification, object: nil, queue: nil) { _ in
                events.yield(.pressure(.memoryWarning))
            },
            center.addObserver(forName: ProcessInfo.thermalStateDidChangeNotification, object: nil, queue: nil) { _ in
                if ProcessInfo.processInfo.thermalState == .critical {
                    events.yield(.pressure(.tooHot))
                }
            }
        ]
    }

    /// The speech bench's settings, shipped as is, are temperature 0, no timestamps, and the prompt
    /// as prompt tokens. `windowClipTime` 0 keeps a clip under a second from decoding nothing.
    private static func options(for kit: WhisperKit) -> DecodingOptions? {
        guard let tokenizer = kit.tokenizer else { return nil }
        var options = DecodingOptions(
            language: "en",
            temperature: 0,
            usePrefillPrompt: true,
            skipSpecialTokens: true,
            withoutTimestamps: true
        )
        options.windowClipTime = 0
        options.promptTokens = tokenizer.encode(text: " " + RecordingPrompt.p1.text)
            .filter { $0 < tokenizer.specialTokens.specialTokenBegin }
        return options
    }

    #if targetEnvironment(simulator)
        /// The Simulator has no Neural Engine, and its GPU decodes about twice as fast as its CPU.
        fileprivate static var compute: ModelComputeOptions {
            ModelComputeOptions(
                melCompute: .cpuAndGPU,
                audioEncoderCompute: .cpuAndGPU,
                textDecoderCompute: .cpuAndGPU,
                prefillCompute: .cpuOnly
            )
        }
    #else
        /// Never the GPU, which iOS refuses an app in the background, as a press on the locked
        /// phone is.
        fileprivate static var compute: ModelComputeOptions {
            ModelComputeOptions(
                melCompute: .cpuOnly,
                audioEncoderCompute: .cpuAndNeuralEngine,
                textDecoderCompute: .cpuAndNeuralEngine,
                prefillCompute: .cpuOnly
            )
        }
    #endif
}

/// The model's files, in the Hugging Face download layout WhisperKit reads, and what a launch
/// finds of them.
private struct SpeechModelStore: Sendable {
    private static let version = SpeechModelVersion.shipped
    private static let modelFiles = ["MelSpectrogram.mlmodelc", "AudioEncoder.mlmodelc", "TextDecoder.mlmodelc", "config.json"]
    private static let tokenizerFiles = ["tokenizer.json", "tokenizer_config.json", "config.json"]
    /// Changes with every OS update, after which Core ML specializes the model again.
    private static var system: String { ProcessInfo.processInfo.operatingSystemVersionString }

    let base: URL
    /// False for a host folder, which is never downloaded into.
    let downloads: Bool

    init(_ models: WhisperEngine.Models) {
        switch models {
        case .applicationSupport:
            base = Self.root.appending(path: Self.version.modelRevision, directoryHint: .isDirectory)
            downloads = true
        #if DEBUG
            case .host(let folder):
                base = folder
                downloads = false
        #endif
        }
    }

    /// Kept out of the phone's backup, as a download that can be fetched again.
    private static let root = URL.applicationSupportDirectory.appending(path: "SpeechModels", directoryHint: .isDirectory)

    private var modelFolder: URL {
        base.appending(path: "models/\(SpeechModelVersion.repository)/\(Self.version.model)", directoryHint: .isDirectory)
    }

    private var tokenizerFolder: URL {
        base.appending(path: "models/\(SpeechModelVersion.tokenizerRepository)", directoryHint: .isDirectory)
    }

    private var downloadedMarker: URL { base.appending(path: "downloaded") }
    private var specializedMarker: URL { base.appending(path: "specialized") }

    func stored() -> StoredSpeechModel {
        guard downloads else { return .specialized }
        guard FileManager.default.fileExists(atPath: downloadedMarker.path) else { return .none }
        let specializedFor = try? String(contentsOf: specializedMarker, encoding: .utf8)
        return specializedFor == Self.system ? .specialized : .downloaded
    }

    func config(prewarm: Bool) -> WhisperKitConfig {
        WhisperKitConfig(
            modelFolder: modelFolder.path,
            tokenizerFolder: base,
            computeOptions: WhisperEngine.compute,
            verbose: false,
            logLevel: .error,
            prewarm: prewarm,
            load: !prewarm,
            download: false
        )
    }

    /// The pinned revisions of the tokenizer and the model, resuming any files already in. False
    /// when stopped, failed, or short of a file.
    func download(progress: @escaping @Sendable (Double) -> Void) async -> Bool {
        do {
            try excludeFromBackup()
            let hub = HubApi(downloadBase: base, useBackgroundSession: true)
            try await hub.snapshot(
                from: Hub.Repo(id: SpeechModelVersion.tokenizerRepository),
                revision: Self.version.tokenizerRevision,
                matching: Self.tokenizerFiles
            )
            try await hub.snapshot(
                from: Hub.Repo(id: SpeechModelVersion.repository),
                revision: Self.version.modelRevision,
                matching: ["\(Self.version.model)/*"]
            ) { progress($0.fractionCompleted) }
            // A stopped snapshot returns as if it finished.
            try Task.checkCancellation()
            guard isComplete else { return false }
            try Data().write(to: downloadedMarker)
            return true
        } catch {
            return false
        }
    }

    func markSpecialized() throws {
        guard downloads else { return }
        try Data(Self.system.utf8).write(to: specializedMarker)
    }

    /// The files a load reads that are not on disk.
    var missingFiles: [URL] {
        let files =
            Self.modelFiles.map { modelFolder.appending(path: $0) } + Self.tokenizerFiles.map { tokenizerFolder.appending(path: $0) }
        return files.filter { !FileManager.default.fileExists(atPath: $0.path) }
    }

    private var isComplete: Bool { missingFiles.isEmpty }

    /// Before the first byte lands.
    private func excludeFromBackup() throws {
        try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        var root = Self.root
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try root.setResourceValues(values)
    }
}

extension NetworkCost {
    fileprivate init(_ path: NWPath) {
        guard path.status == .satisfied else {
            self = .offline
            return
        }
        self = path.isExpensive || path.isConstrained ? .metered : .unmetered
    }
}
