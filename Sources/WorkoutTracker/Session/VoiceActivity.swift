/// Whether the athlete is speaking, read frame by frame from the mic level of a press's recording.
/// The noise floor is the 15th percentile of the levels so far, and a frame 9 dB over it is loud.
/// Two loud frames in a row are speech. After speech, the quiet frames since the last loud one are
/// a Pause.
///
/// The constants are the ones measured on synthetic voices, clean and with pink noise at 15 dB SNR
/// (ADR-0021). A 12 dB margin missed one more noisy phrase than 9 dB.
struct VoiceActivity: Equatable, Sendable {
    /// One 4096-frame tap buffer at 48 kHz, in the recording's 16 kHz samples.
    static let frameSamples = 1365
    /// `frameSamples` at 16 kHz: 85.3125 ms.
    static let frameDuration: Duration = .nanoseconds(85_312_500)
    static let loudMargin: Float = 9
    static let floorPercentile: Float = 0.15
    /// No frame is loud until this many give the floor something to read.
    static let framesBeforeFloor = 3
    static let loudFramesToSpeak = 2

    /// The quiet after the athlete last spoke.
    struct Pause: Equatable, Sendable {
        /// Quiet frames since the last loud one.
        let frames: Int
        /// How many samples were recorded when the last loud frame ended.
        let began: Int
    }

    /// How many levels this has heard.
    private(set) var frames = 0
    private(set) var hasSpoken = false
    private var sortedLevels: [Float] = []
    private var loudRun = 0
    /// Frames heard when the last loud frame ended.
    private var lastLoudEnd = 0

    /// `levels` in dBFS, one per frame, oldest first.
    init(levels: some Sequence<Float> = []) {
        hear(levels)
    }

    /// Nil before the athlete spoke and while they speak.
    var pause: Pause? {
        guard hasSpoken, frames > lastLoudEnd else { return nil }
        return Pause(frames: frames - lastLoudEnd, began: lastLoudEnd * Self.frameSamples)
    }

    /// Whether the athlete spoke and has said nothing since `samples` were recorded, so a read of
    /// that much of the recording heard all of it.
    func isPaused(since samples: Int) -> Bool {
        pause.map { samples >= $0.began } ?? false
    }

    /// The next frames' levels, oldest first.
    mutating func hear(_ levels: some Sequence<Float>) {
        for level in levels {
            hear(level)
        }
    }

    private mutating func hear(_ level: Float) {
        sortedLevels.insert(level, at: sortedLevels.firstIndex { $0 > level } ?? sortedLevels.endIndex)
        frames += 1
        guard frames >= Self.framesBeforeFloor, level > floor + Self.loudMargin else {
            loudRun = 0
            return
        }
        loudRun += 1
        lastLoudEnd = frames
        if loudRun >= Self.loudFramesToSpeak { hasSpoken = true }
    }

    /// The `floorPercentile` of the levels so far, between the two nearest as numpy reads it.
    private var floor: Float {
        let rank = Self.floorPercentile * Float(sortedLevels.count - 1)
        let below = Int(rank)
        let above = min(below + 1, sortedLevels.count - 1)
        return sortedLevels[below] + (rank - Float(below)) * (sortedLevels[above] - sortedLevels[below])
    }
}
