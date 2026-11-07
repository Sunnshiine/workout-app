import AVFoundation
import CoreGraphics
import Foundation
import Observation

/// One Form Clip's playback. The review scrubs, steps, and loops through this, and the Compare
/// drives two of them. `still` stands in for the movie where a screen must render the same each time.
@MainActor
@Observable
final class ClipPlayer {
    private(set) var time: Double
    let duration: Double
    /// Width over height as displayed, once the movie's first track is read.
    private(set) var aspect: Double?
    private(set) var isPlaying = false
    private(set) var rate = ClipPlaybackRate.full
    /// The movie would not open, which an added clip only meets if its file was damaged since.
    private(set) var isUnplayable = false
    var loops = true

    @ObservationIgnored let player: AVPlayer
    @ObservationIgnored let still: CGImage?
    /// Each moment playback reports, for whoever is driving two players as one.
    @ObservationIgnored var onTick: ((Double) -> Void)?
    /// Takes over the clip's end from the player's own loop.
    @ObservationIgnored var onEnd: (() -> Void)?
    @ObservationIgnored var onReady: (() -> Void)?
    /// A seek or a synced start before this raises an exception in AVFoundation.
    @ObservationIgnored private(set) var isReady = false
    @ObservationIgnored private var timeObserver: Any?
    @ObservationIgnored private var endObserver: (any NSObjectProtocol)?
    @ObservationIgnored private var loading: Task<Void, Never>?
    @ObservationIgnored private var seekTarget: Double?
    @ObservationIgnored private var seeking: Task<Void, Never>?
    @ObservationIgnored private var isScrubbing = false
    /// Set by a loop or a press at the end, which plays on only once the seek back has landed.
    @ObservationIgnored private var playsAfterSeek = false

    init(url: URL, duration: Double) {
        let item = AVPlayerItem(url: url)
        item.audioTimePitchAlgorithm = .spectral
        player = AVPlayer(playerItem: item)
        player.actionAtItemEnd = .pause
        // A local file never stalls, and a synced start refuses to run with this on.
        player.automaticallyWaitsToMinimizeStalling = false
        still = nil
        time = 0
        self.duration = duration
        setUp()
    }

    /// A player on one frame, for a screen that must render the same every time.
    init(still: CGImage, time: Double, duration: Double, rate: ClipPlaybackRate, isPlaying: Bool) {
        player = AVPlayer()
        self.still = still
        self.time = time
        self.duration = duration
        self.rate = rate
        self.isPlaying = isPlaying
        isReady = true
        aspect = Double(still.width) / Double(still.height)
    }

    /// Opens the movie and starts its reports. A cover handing over can show a screen, take it away,
    /// and show it again on the same player, so a screen calls this each time it appears.
    func setUp() {
        guard still == nil, let item = player.currentItem else { return }
        if timeObserver == nil { observe(item) }
        if !isReady, loading == nil { loading = Task { [weak self] in await self?.load(item) } }
    }

    /// Returns once the movie has opened or failed to.
    func loaded() async {
        await loading?.value
    }

    /// Returns once every seek asked for so far has landed.
    func settled() async {
        await seeking?.value
    }

    private func load(_ item: AVPlayerItem) async {
        aspect = await Self.aspect(of: item.asset)
        // AVFoundation reports these through KVO alone, and its Combine publisher drops a change
        // that lands between two demands, so a wait on it can hang on a movie that is ready.
        while item.status == .unknown || player.status == .unknown {
            guard (try? await Task.sleep(for: .milliseconds(10))) != nil else { return }
        }
        guard item.status == .readyToPlay, player.status == .readyToPlay else {
            isUnplayable = true
            return
        }
        isReady = true
        startSeeking()
        onReady?()
    }

    private static func aspect(of asset: AVAsset) async -> Double? {
        guard let track = try? await asset.loadTracks(withMediaType: .video).first,
            let (size, transform) = try? await track.load(.naturalSize, .preferredTransform)
        else { return nil }
        return MovieDisplay(naturalSize: size, transform: transform).aspect
    }

    private func observe(_ item: AVPlayerItem) {
        timeObserver = player.addPeriodicTimeObserver(
            forInterval: CMTime(value: 1, timescale: 30),
            queue: .main
        ) { [weak self] moment in
            MainActor.assumeIsolated { self?.report(moment.seconds) }
        }
        endObserver = NotificationCenter.default.addObserver(
            forName: AVPlayerItem.didPlayToEndTimeNotification,
            object: item,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.reachedEnd() }
        }
    }

    /// The observers hold the player, so the screen ends them as it goes.
    func tearDown() {
        pause()
        loading?.cancel()
        loading = nil
        seeking?.cancel()
        if let timeObserver { player.removeTimeObserver(timeObserver) }
        if let endObserver { NotificationCenter.default.removeObserver(endObserver) }
        timeObserver = nil
        endObserver = nil
    }

    private func report(_ moment: Double) {
        guard !isScrubbing, seeking == nil, moment.isFinite else { return }
        time = min(moment, duration)
        onTick?(time)
    }

    func reachedEnd() {
        if let onEnd {
            onEnd()
        } else if loops {
            playsAfterSeek = true
            seek(to: 0)
        } else {
            isPlaying = false
        }
    }

    func togglePlaying() {
        if isPlaying { pause() } else { play() }
    }

    /// From the end, a press starts the clip over rather than doing nothing.
    func play() {
        isPlaying = true
        if time >= duration - 0.01 {
            playsAfterSeek = true
            seek(to: 0)
        } else {
            applyRate()
        }
    }

    func pause() {
        playsAfterSeek = false
        player.pause()
        isPlaying = false
    }

    /// Starts on `hostTime` from `moment`, so two players that share it run frame for frame. A
    /// Compare plays silent, since two rooms' sound at once is noise.
    func startSynced(from moment: Double, atHostTime hostTime: CMTime) {
        seekTarget = nil
        time = moment
        player.isMuted = true
        if still == nil {
            player.setRate(Float(rate.rawValue), time: CMTime(seconds: moment, preferredTimescale: 600), atHostTime: hostTime)
        }
        isPlaying = true
    }

    func setRate(_ rate: ClipPlaybackRate) {
        self.rate = rate
        if isPlaying { applyRate() }
    }

    /// Slowed gym audio is noise, so a slow review plays silent.
    private func applyRate() {
        player.isMuted = rate != .full
        player.rate = Float(rate.rawValue)
    }

    /// One frame on or back, from a pause, so the frame stays on screen.
    func step(by frames: Int) {
        pause()
        player.currentItem?.step(byCount: frames)
    }

    func beginScrub() {
        isScrubbing = true
        playsAfterSeek = false
        player.pause()
    }

    func scrub(to moment: Double) {
        seek(to: moment)
    }

    /// A scrub leaves the clip where the finger left it, so the frame the athlete found stays up.
    func endScrub() {
        isScrubbing = false
        isPlaying = false
    }

    /// Seeks one at a time to the newest target, so a fast drag shows frames, not a queue of them.
    func seek(to moment: Double) {
        time = min(max(moment, 0), duration)
        seekTarget = time
        startSeeking()
    }

    private func startSeeking() {
        guard isReady, still == nil, seekTarget != nil, seeking == nil else { return }
        seeking = Task { [weak self] in await self?.runSeeks() }
    }

    private func runSeeks() async {
        while let target = seekTarget, !Task.isCancelled {
            seekTarget = nil
            await player.seek(
                to: CMTime(seconds: target, preferredTimescale: 600),
                toleranceBefore: .zero,
                toleranceAfter: .zero
            )
        }
        seeking = nil
        if playsAfterSeek {
            playsAfterSeek = false
            applyRate()
        }
    }
}

/// Two Form Clips playing as one, lined up at their Start Marks. Either pane can leave the line to
/// find where its Set starts, and the next shared press lines them up again.
@MainActor
@Observable
final class ClipComparison {
    enum Pane: Sendable {
        case left, right
    }

    let left: ClipPlayer
    let right: ClipPlayer
    private(set) var timeline: CompareTimeline
    private(set) var isPlaying = false
    private(set) var rate = ClipPlaybackRate.half
    var loops = true
    @ObservationIgnored private var startsWhenReady = false

    init(left: ClipPlayer, right: ClipPlayer, leftStart: Double, rightStart: Double) {
        self.left = left
        self.right = right
        timeline = CompareTimeline(
            left: .init(start: leftStart, duration: left.duration),
            right: .init(start: rightStart, duration: right.duration)
        )
        left.onTick = { [weak self] _ in self?.stopAtEndOfSpan() }
        for player in [left, right] {
            player.onEnd = { [weak self] in self?.reachedEnd() }
            player.onReady = { [weak self] in self?.startIfWaiting() }
        }
        lineUp(at: 0)
    }

    /// Where the two stand, read off the left movie, the one the right lines up against.
    var sharedTime: Double { timeline.clamped(left.time - timeline.left.start) }

    func setUp() {
        left.setUp()
        right.setUp()
    }

    func tearDown() {
        left.tearDown()
        right.tearDown()
    }

    private func lineUp(at shared: Double) {
        left.seek(to: timeline.leftTime(at: shared))
        right.seek(to: timeline.rightTime(at: shared))
    }

    private func stopAtEndOfSpan() {
        if isPlaying, left.time - timeline.left.start >= timeline.span.upperBound { reachedEnd() }
    }

    func reachedEnd() {
        guard isPlaying else { return }
        if loops {
            start(from: timeline.span.lowerBound)
        } else {
            pause()
        }
    }

    func togglePlaying() {
        if isPlaying {
            pause()
        } else {
            start(from: sharedTime >= timeline.span.upperBound ? timeline.span.lowerBound : sharedTime)
        }
    }

    private func start(from shared: Double) {
        isPlaying = true
        guard left.isReady, right.isReady else {
            startsWhenReady = true
            lineUp(at: shared)
            return
        }
        startsWhenReady = false
        // A tenth of a second ahead, so both players have the moment before it arrives.
        let host = CMClockGetTime(CMClockGetHostTimeClock()) + CMTime(value: 1, timescale: 10)
        left.setRate(rate)
        right.setRate(rate)
        left.startSynced(from: timeline.leftTime(at: shared), atHostTime: host)
        right.startSynced(from: timeline.rightTime(at: shared), atHostTime: host)
    }

    private func startIfWaiting() {
        if startsWhenReady { start(from: sharedTime) }
    }

    private func pause() {
        startsWhenReady = false
        left.pause()
        right.pause()
        isPlaying = false
    }

    func setRate(_ rate: ClipPlaybackRate) {
        self.rate = rate
        if isPlaying { start(from: sharedTime) }
    }

    func step(by frames: Int) {
        pause()
        left.step(by: frames)
        right.step(by: frames)
    }

    func beginScrub() {
        pause()
    }

    func scrub(to shared: Double) {
        lineUp(at: timeline.clamped(shared))
    }

    /// A drag on one pane moves that movie alone, so the athlete can find where its Set starts.
    func scrub(_ pane: Pane, to time: Double) {
        pause()
        player(for: pane).seek(to: time)
    }

    func player(for pane: Pane) -> ClipPlayer {
        switch pane {
        case .left: left
        case .right: right
        }
    }

    /// Takes the pane's current frame as its Set's start. Paused, nothing moves, because the other
    /// pane may stand on the frame the athlete dragged it to, waiting for its own flag.
    func markStart(_ pane: Pane) -> Double {
        let mark = player(for: pane).time
        switch pane {
        case .left:
            timeline = CompareTimeline(left: .init(start: mark, duration: left.duration), right: timeline.right)
        case .right:
            timeline = CompareTimeline(left: timeline.left, right: .init(start: mark, duration: right.duration))
        }
        if isPlaying { start(from: 0) }
        return mark
    }
}
