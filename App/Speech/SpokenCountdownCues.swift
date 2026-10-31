import AVFoundation

/// Speaks an Effort Countdown's cues and plays each one's haptic. The voice ducks the athlete's
/// music rather than stopping it, and sounds with the silent switch on, because a gym is loud and
/// the athlete's hands are on the machine (ADR-0023). It holds the audio session only while it
/// speaks and a beat after, so the music comes back up between cues far apart. Dictation sets its
/// own category when its mic opens, and the coordinator ends a countdown before then.
@MainActor
final class SpokenCountdownCues: CountdownCuePlaying {
    /// Long enough past a cue to keep the music down across the Lead-in's one-second cues.
    private static let releaseDelay: Duration = .milliseconds(1_500)

    private let synthesizer = AVSpeechSynthesizer()
    private var holdsAudioSession = false
    private var release: Task<Void, Never>?

    func play(_ cue: CountdownCue) {
        HapticPlayer.shared.play(cue.haptic)
        activateAudioSession()
        // A cue still speaking when the next falls due gives way to it, so the voice keeps time.
        synthesizer.stopSpeaking(at: .immediate)
        synthesizer.speak(AVSpeechUtterance(string: cue.spokenText))
        releaseAfterABeat()
    }

    func silence() {
        release?.cancel()
        synthesizer.stopSpeaking(at: .immediate)
        deactivateAudioSession()
    }

    /// Lets the music back up once the voice has been quiet a beat. A cue played before then
    /// starts the beat again.
    private func releaseAfterABeat() {
        release?.cancel()
        release = Task { [weak self] in
            try? await Task.sleep(for: Self.releaseDelay)
            while let self, synthesizer.isSpeaking, !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(250))
            }
            guard !Task.isCancelled else { return }
            self?.deactivateAudioSession()
        }
    }

    private func activateAudioSession() {
        guard !holdsAudioSession else { return }
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.playback, mode: .voicePrompt, options: [.duckOthers, .interruptSpokenAudioAndMixWithOthers])
            try session.setActive(true)
            holdsAudioSession = true
        } catch {
            // The cue has played its haptic, and the voice speaks on whatever session there is.
        }
    }

    private func deactivateAudioSession() {
        guard holdsAudioSession else { return }
        holdsAudioSession = false
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }
}
