import Foundation
import Observation

/// One cue of an Effort Countdown, spoken and felt, so an athlete with their hands on the machine
/// follows it without looking at the phone.
enum CountdownCue: Equatable, Sendable {
    /// One second of the Lead-in, from 5 down to 1.
    case leadIn(Int)
    /// The effort begins.
    case begins(TimedEffort)
    /// One of the effort's last three seconds.
    case closing(Int)
    /// The effort is over.
    case ends(TimedEffort)

    var spokenText: String {
        switch self {
        case .leadIn(let second), .closing(let second): "\(second)"
        case .begins(.openingHold): "Hold"
        case .begins(.timedSet): "Go"
        case .ends(.openingHold): "Done"
        case .ends(.timedSet): "Time"
        }
    }

    var haptic: Haptic {
        switch self {
        case .leadIn, .closing: .rest(.lightTap)
        case .begins: .input(Theme.Haptics.logTap)
        case .ends: .rest(.expiryBuzz)
        }
    }
}

/// Speaks and plays each cue. The app's speaks through the speech synthesizer and plays through
/// `HapticPlayer`.
@MainActor
protocol CountdownCuePlaying: AnyObject {
    func play(_ cue: CountdownCue)
    /// Stops a cue mid-word, for a countdown cancelled while it speaks.
    func silence()
}

/// What an Effort Countdown shows at one instant.
enum CountdownPhase: Equatable, Sendable {
    case leadIn(secondsLeft: Int)
    /// `elapsedFraction` steps once a second, from 0 at the effort's start.
    case effort(secondsLeft: Int, elapsedFraction: Double)
    /// The effort is over, and the countdown lingers before it clears.
    case finished
}

/// One Effort Countdown, from the tap that started it: a fixed Lead-in, then the effort.
struct CountdownRun: Equatable, Sendable {
    /// The Lead-in is fixed, with no setting, so one tap always gives the athlete the same five
    /// seconds to get their hands on the machine (ADR-0023).
    static let leadInSeconds = 5
    static let closingSeconds = [3, 2, 1]

    /// The Set a countdown runs for, by the place in its Session a sync's re-parse keeps.
    struct Owner: Hashable, Sendable {
        let session: SessionCoordinate
        let set: ActiveSetID
    }

    let effort: TimedEffort
    let owner: Owner
    let start: Date

    var end: Date {
        start.addingTimeInterval(TimeInterval(Self.leadInSeconds + effort.duration.seconds))
    }

    func phase(at now: Date) -> CountdownPhase {
        let elapsed = max(0, Int(now.timeIntervalSince(start).rounded(.down)))
        let effortElapsed = elapsed - Self.leadInSeconds
        let effortSeconds = effort.duration.seconds
        if effortElapsed < 0 { return .leadIn(secondsLeft: -effortElapsed) }
        if effortElapsed >= effortSeconds { return .finished }
        return .effort(secondsLeft: effortSeconds - effortElapsed, elapsedFraction: Double(effortElapsed) / Double(effortSeconds))
    }

    /// Every cue, at its whole second from the tap, in order. A closing second the effort does not
    /// reach, as the 3 of a two-second hold, is none.
    var cues: [ScheduledCue] {
        let effortSeconds = effort.duration.seconds
        let leadIn = (0..<Self.leadInSeconds).map { ScheduledCue(second: $0, cue: .leadIn(Self.leadInSeconds - $0)) }
        let closing = Self.closingSeconds.filter { $0 < effortSeconds }.map {
            ScheduledCue(second: Self.leadInSeconds + effortSeconds - $0, cue: .closing($0))
        }
        return leadIn + [ScheduledCue(second: Self.leadInSeconds, cue: .begins(effort))] + closing
            + [ScheduledCue(second: Self.leadInSeconds + effortSeconds, cue: .ends(effort))]
    }
}

struct ScheduledCue: Equatable, Sendable {
    let second: Int
    let cue: CountdownCue
}

/// The one Effort Countdown the Session screen runs. Its cues ring on the expiry scheduler, so
/// they keep time whether or not a card is drawing them, and the card reads the phase from the
/// run.
@MainActor
@Observable
final class EffortCountdown {
    /// How long the finished countdown stays on the card after its last cue, so the athlete who
    /// looks up sees it ended.
    static let finishedLinger: TimeInterval = 2

    private(set) var run: CountdownRun?
    /// The first cue of `run` not yet played.
    @ObservationIgnored private var nextCue = 0
    /// Whether the card still offers `run`, asked before each cue. Set with `run`.
    @ObservationIgnored private var isOffered: ((CountdownRun) -> Bool)?

    @ObservationIgnored private let clock: any RestClock
    @ObservationIgnored private let scheduler: any RestExpiryScheduling
    @ObservationIgnored private let cues: any CountdownCuePlaying

    init(clock: any RestClock, scheduler: any RestExpiryScheduling, cues: any CountdownCuePlaying) {
        self.clock = clock
        self.scheduler = scheduler
        self.cues = cues
    }

    /// Starts `effort` for `owner` now, in place of any countdown running. It runs while
    /// `isOffered` holds, and ends silenced at the first cue it does not, since a write or a sync
    /// that no verb of the stage made can log its Set or change its effort under it.
    func start(_ effort: TimedEffort, for owner: CountdownRun.Owner, while isOffered: @escaping (CountdownRun) -> Bool) {
        cancel()
        run = CountdownRun(effort: effort, owner: owner, start: clock.now)
        nextCue = 0
        self.isOffered = isOffered
        advance()
    }

    /// Ends the countdown at once and silences a cue mid-word. Nothing runs, nothing happens.
    func cancel() {
        guard run != nil else { return }
        run = nil
        nextCue = 0
        scheduler.cancel()
        cues.silence()
    }

    /// Plays the latest cue fallen due since the last one played, and only that one, so a
    /// countdown that wakes late says where it is rather than every second it missed. Then it
    /// sleeps until the next cue, or past the finished linger, when it clears and leaves its last
    /// cue to finish speaking. A wake with nothing due plays nothing, and a wake for a run its card
    /// no longer offers ends it.
    private func advance() {
        guard let run else { return }
        guard isOffered?(run) == true else {
            cancel()
            return
        }
        let schedule = run.cues
        let now = clock.now
        let due = schedule[nextCue...].prefix { run.start.addingTimeInterval(TimeInterval($0.second)) <= now }
        if let latest = due.last {
            cues.play(latest.cue)
            nextCue += due.count
        }
        let wake: Date
        if nextCue < schedule.count {
            wake = run.start.addingTimeInterval(TimeInterval(schedule[nextCue].second))
        } else {
            wake = run.end.addingTimeInterval(Self.finishedLinger)
            guard now < wake else {
                self.run = nil
                nextCue = 0
                return
            }
        }
        scheduler.schedule(deadline: wake) { [weak self] in
            self?.advance()
        }
    }
}
