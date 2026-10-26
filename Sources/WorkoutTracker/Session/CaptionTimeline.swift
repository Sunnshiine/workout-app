/// The captions a recording played to the live engine showed, each with when it arrived after
/// playback began, as `workout hear --paced` reports them.
@MainActor
final class CaptionTimeline {
    private let clock: any ListeningClock
    private var startedAt: Duration?
    private(set) var captions: [HearReport.Caption] = []

    init(clock: any ListeningClock = ContinuousListeningClock()) {
        self.clock = clock
    }

    /// Playback began; captions before it are the engine warming up and are dropped.
    func start() {
        startedAt = clock.now
    }

    /// A caption the same as the last is not a new one.
    func hear(_ heard: String) {
        guard let startedAt, heard != captions.last?.heard else { return }
        captions.append(HearReport.Caption(atMs: (clock.now - startedAt).wholeMilliseconds, heard: heard))
    }
}
