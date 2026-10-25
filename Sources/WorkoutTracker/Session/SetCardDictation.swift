import Foundation

/// What the Set card's mic and action capsule show of a press for the card's Set.
enum SetCardDictation: Equatable {
    case ready
    /// The capsule shows what is heard in place of the Log button.
    case listening(caption: String)
    /// The capsule keeps what was heard, with the mic off, until the press's outcome is in.
    case deciding(caption: String)
    /// The capsule shows what was heard, or why nothing was, until the athlete taps it.
    case rejected(caption: String)
    /// The card's values become these, with nothing written.
    case filled(SetLogDraft)

    init(_ state: SetDictation.State, for setID: ActiveSetID) {
        switch state {
        case .preparing(setID), .listening(setID, _): self = .listening(caption: Self.caption(hearing: state.heard))
        case .deciding(setID, let heard): self = .deciding(caption: Self.caption(hearing: heard))
        case .finished(setID, .rejected(let rejection, let heard)): self = .rejected(caption: Self.caption(rejection, heard: heard))
        case .finished(setID, .filled(let values, _)): self = .filled(values)
        case .idle, .preparing, .listening, .deciding, .finished: self = .ready
        }
    }

    /// What the capsule says in place of the Log button; nil leaves the Log button.
    var caption: String? {
        switch self {
        case .listening(let caption), .deciding(let caption), .rejected(let caption): caption
        case .ready, .filled: nil
        }
    }

    var isListening: Bool {
        guard case .listening = self else { return false }
        return true
    }

    private static func caption(hearing heard: String) -> String {
        heard.isEmpty ? "Listening" : heard
    }

    private static func caption(_ rejection: SetDictation.Rejection, heard: String) -> String {
        switch rejection {
        case .transcriber(.microphoneDenied): "Microphone is off in Settings"
        case .transcriber(.unavailable): "Speech isn’t available"
        case .spokenSet(.nothingHeard), .transcriber(.nothingHeard): "Nothing heard"
        case .spokenSet, .transcriber(.failed): rejection.readback(of: heard)
        }
    }
}

extension SetDictation.Rejection {
    /// What the card and the Live Activity say of a rejected transcript: the words heard, and for a
    /// Set no lifter logs, an ask to say it again.
    func readback(of heard: String) -> String {
        guard !heard.isEmpty else { return "Nothing heard" }
        guard case .spokenSet(.implausible) = self else { return "“\(heard)”" }
        return "“\(heard)”, say it again"
    }
}

extension SetDictation {
    /// The mic's press, as a weight step answers a tap.
    nonisolated static let startHaptic = Haptic.input(Theme.Haptics.stepperTick)
}

extension SetDictation.Outcome {
    /// A write feels like the tap it stands in for; anything the athlete still has to act on warns.
    var haptic: Haptic {
        switch self {
        case .logged: .input(Theme.Haptics.logTap)
        case .skipped: .input(Theme.Haptics.skipDud)
        case .filled, .rejected: .warning
        }
    }
}
