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
    /// How long a countdown cancelled mid-word waits before it lets the music back up.
    private static let silencedReleaseDelay: Duration = .milliseconds(250)
    private static let releaseRecheck: Duration = .milliseconds(250)
    private static let releaseAttempts = 8

    private let synthesizer = AVSpeechSynthesizer()
    private var holdsAudioSession = false
    private var release: Task<Void, Never>?

    func play(_ cue: CountdownCue) {
        HapticPlayer.shared.play(cue.haptic)
        activateAudioSession()
        // A cue still speaking when the next falls due gives way to it, so the voice keeps time.
        synthesizer.stopSpeaking(at: .immediate)
        synthesizer.speak(AVSpeechUtterance(string: cue.spokenText))
        release(after: Self.releaseDelay)
    }

    func silence() {
        synthesizer.stopSpeaking(at: .immediate)
        release(after: Self.silencedReleaseDelay)
    }

    /// Lets the music back up once the voice has been quiet for `delay`. A cue played before then
    /// starts the wait again.
    private func release(after delay: Duration) {
        release?.cancel()
        release = Task { [weak self] in
            try? await Task.sleep(for: delay)
            await self?.releaseOnceQuiet()
        }
    }

    /// The session refuses to deactivate while the synthesizer still runs its audio, as it can just
    /// after `stopSpeaking(at:)`, so a refused release tries again a beat later, a few times.
    /// The session stays held until one succeeds, and the next cue's release tries again.
    private func releaseOnceQuiet() async {
        for _ in 0..<Self.releaseAttempts {
            while synthesizer.isSpeaking, !Task.isCancelled {
                try? await Task.sleep(for: Self.releaseRecheck)
            }
            guard !Task.isCancelled, !deactivateAudioSession() else { return }
            try? await Task.sleep(for: Self.releaseRecheck)
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

    /// True once the session is let go, or when it was never held.
    private func deactivateAudioSession() -> Bool {
        guard holdsAudioSession else { return true }
        do {
            try AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
            holdsAudioSession = false
            return true
        } catch {
            return false
        }
    }
}
