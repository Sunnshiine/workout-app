/// The model, prompt, and decode options a Recording Transcript is read with. Every Dictation
/// Record carries it, so a change of any of them can be told apart in the records.
struct SpeechModelVersion: Equatable, Sendable, Codable {
    /// The model's folder in `repository`, as "openai_whisper-small.en".
    let model: String
    /// The pinned commit of `repository` the model's files come from.
    let modelRevision: String
    /// The pinned commit of `tokenizerRepository` the tokenizer comes from.
    let tokenizerRevision: String
    let prompt: RecordingPrompt.ID
    /// Temperature 0, no timestamps, `windowClipTime` 0, and temperature fallbacks, which the
    /// recording engine's decode options spell out. Without `windowClipTime` 0 a clip under a second,
    /// as a skip said alone, decodes nothing.
    let options: String

    /// Prompted Whisper small, as the speech bench measured it with WhisperKit 0.18.0.
    static let shipped = SpeechModelVersion(
        model: "openai_whisper-small.en",
        modelRevision: "0f63a7800b00dd0226abd051b906c246e1907482",
        tokenizerRevision: "e8727524f962ee844a7319d92be39ac1bd25655a",
        prompt: RecordingPrompt.p1.id,
        options: "t0.nots.wc0.fb5"
    )

    static let repository = "argmaxinc/whisperkit-coreml"
    static let tokenizerRepository = "openai/whisper-small.en"
}

/// Where the recording engine's model stands on this phone. The model is downloaded, never
/// bundled, and a press reads with it only once it is `ready`.
enum SpeechModelState: Hashable, Sendable {
    /// No model on disk, and no network seen yet.
    case absent
    /// The model downloads only on a network that is neither expensive nor constrained.
    case waitingForNetwork
    case downloading
    /// Core ML compiling the model for this chip, once after a download and again after an OS
    /// update. It takes seconds to minutes.
    case specializing
    /// On disk and specialized, not loaded since launch. The next press loads it.
    case downloaded
    case loading
    case ready
    /// On disk, out of memory until the next press loads it again.
    case unloaded(UnloadReason)
    /// Tried again on the next launch, never per press.
    case failed(SpeechModelWork)
}

/// Why a loaded model left memory.
enum UnloadReason: String, CaseIterable, Sendable {
    case memoryWarning
    /// No press for `SpeechModelPlan.idleUnload`.
    case idle
    /// The phone's thermal state turned critical.
    case tooHot
}

/// The long steps the model takes on its way to a press, each run off the main actor.
enum SpeechModelWork: String, CaseIterable, Sendable {
    case download
    case specialize
    case load

    /// The state the model is in while this runs.
    var state: SpeechModelState {
        switch self {
        case .download: .downloading
        case .specialize: .specializing
        case .load: .loading
        }
    }

    /// Where the model stands once this succeeds, and what runs next.
    fileprivate var next: SpeechModelPlan.Step {
        switch self {
        case .download: SpeechModelPlan.Step(.specializing, .start(.specialize))
        case .specialize: SpeechModelPlan.Step(.downloaded, .none)
        case .load: SpeechModelPlan.Step(.ready, .none)
        }
    }
}

extension SpeechModelState: CaseIterable, Codable {
    static let allCases: [SpeechModelState] =
        [.absent, .waitingForNetwork, .downloading, .specializing, .downloaded, .loading, .ready]
        + UnloadReason.allCases.map(SpeechModelState.unloaded)
        + SpeechModelWork.allCases.map(SpeechModelState.failed)

    /// The state as a record and the summary name it, as "unloaded.memoryWarning".
    var name: String {
        switch self {
        case .unloaded(let reason): "unloaded.\(reason.rawValue)"
        case .failed(let work): "failed.\(work.rawValue)"
        // The case's own name, which the round-trip test over every state pins.
        default: String(describing: self)
        }
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        let name = try container.decode(String.self)
        guard let state = Self.allCases.first(where: { $0.name == name }) else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "\"\(name)\" is not a speech model state")
        }
        self = state
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(name)
    }
}

/// What the network the phone is on would cost a 465 MB download.
enum NetworkCost: Equatable, Sendable {
    case unmetered
    /// Expensive, as cellular or a hotspot, or constrained, as Low Data Mode.
    case metered
    case offline
}

/// What the model has on disk at launch.
enum StoredSpeechModel: Equatable, Sendable {
    case none
    /// Every file, not yet specialized for this OS.
    case downloaded
    case specialized
}

/// What happened to the model, from any thread, in the order the engine takes them.
enum SpeechModelEvent: Equatable, Sendable {
    case launched(StoredSpeechModel)
    case network(NetworkCost)
    case finished(SpeechModelWork, succeeded: Bool)
    case pressBegan
    case pressure(UnloadReason)
}

/// What the engine does next.
enum SpeechModelCommand: Equatable, Sendable {
    case start(SpeechModelWork)
    /// Stops the download where it is. Files already in are kept, so the next one resumes.
    case stopDownload
    /// Waits out a load and a decode in flight, then lets the model go.
    case unload
    case none
}

/// Every decision about the model's lifecycle, as a table the tests pin and the engine only
/// carries out.
enum SpeechModelPlan {
    /// How long the model stays loaded with no press. The press after it loads the model again,
    /// which took about 1.2 s on the Mac bench, so a press that long may still read with it.
    static let idleUnload: Duration = .seconds(30 * 60)

    struct Step: Equatable, Sendable {
        let state: SpeechModelState
        let command: SpeechModelCommand

        init(_ state: SpeechModelState, _ command: SpeechModelCommand) {
            self.state = state
            self.command = command
        }
    }

    static func next(_ state: SpeechModelState, on event: SpeechModelEvent) -> Step {
        switch event {
        case .launched(let stored): launched(with: stored)
        case .network(let cost): network(cost, in: state)
        case .finished(let work, let succeeded): finished(work, succeeded: succeeded, in: state)
        case .pressBegan: pressBegan(in: state)
        case .pressure(let reason): pressure(reason, in: state)
        }
    }

    /// A model downloaded but not specialized for this OS is specialized now, rather than on the
    /// press that first needs it.
    private static func launched(with stored: StoredSpeechModel) -> Step {
        switch stored {
        case .none: Step(.absent, .none)
        case .downloaded: Step(.specializing, .start(.specialize))
        case .specialized: Step(.downloaded, .none)
        }
    }

    private static func network(_ cost: NetworkCost, in state: SpeechModelState) -> Step {
        switch (state, cost) {
        case (.absent, .unmetered), (.waitingForNetwork, .unmetered): Step(.downloading, .start(.download))
        case (.absent, _): Step(.waitingForNetwork, .none)
        case (.downloading, .metered), (.downloading, .offline): Step(.waitingForNetwork, .stopDownload)
        default: Step(state, .none)
        }
    }

    /// Work the model has since moved on from, as a load an unload stopped, changes nothing.
    private static func finished(_ work: SpeechModelWork, succeeded: Bool, in state: SpeechModelState) -> Step {
        guard state == work.state else { return Step(state, .none) }
        guard succeeded else { return Step(.failed(work), .none) }
        return work.next
    }

    /// A press that finds the model out of memory starts loading it, so the press may still read
    /// with it. A failed model waits for the next launch.
    private static func pressBegan(in state: SpeechModelState) -> Step {
        switch state {
        case .downloaded, .unloaded: Step(.loading, .start(.load))
        default: Step(state, .none)
        }
    }

    private static func pressure(_ reason: UnloadReason, in state: SpeechModelState) -> Step {
        switch state {
        case .ready, .loading: Step(.unloaded(reason), .unload)
        default: Step(state, .none)
        }
    }

    /// The Settings row's words for `state`, so no View switches on it. `downloaded` is the
    /// fraction of the download in, which only `downloading` reads.
    static func caption(_ state: SpeechModelState, downloaded fraction: Double) -> String {
        guard state != .downloading else { return "Downloading \(Int((fraction * 100).rounded(.down)))%" }
        return captions[state, default: ""]
    }

    private static let captions: [SpeechModelState: String] = Dictionary(
        uniqueKeysWithValues: [
            (.absent, "Not downloaded"),
            (.waitingForNetwork, "Waiting for Wi-Fi"),
            (.specializing, "Preparing"),
            (.downloaded, "Downloaded"),
            (.loading, "Loading"),
            (.ready, "Ready"),
            (.failed(.download), "Couldn’t download"),
            (.failed(.specialize), "Couldn’t prepare"),
            (.failed(.load), "Couldn’t load")
        ] + UnloadReason.allCases.map { (SpeechModelState.unloaded($0), "Downloaded") }
    )
}
