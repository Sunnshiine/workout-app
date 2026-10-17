import Foundation

/// The timings one press is held to (DESIGN.md §5.3, §7). A press keeps the policy it began with.
struct HoldToSkipPolicy: Equatable, Sendable {
    let holdDuration: TimeInterval
    let revealDelay: TimeInterval = Theme.Motion.holdToSkipReveal

    private init(holdDuration: TimeInterval) {
        self.holdDuration = holdDuration
    }

    /// The idle-Set hold: reveal 250ms, commit 850ms.
    static let standard = HoldToSkipPolicy(holdDuration: Theme.Motion.holdToSkipCommit)

    /// The longer hold a Set already logged must survive before it re-skips (900ms).
    static let loggedState = HoldToSkipPolicy(holdDuration: Theme.Motion.holdToSkipLoggedCommit)

    /// The hold a Set in `state` takes, or nil when its capsule takes none: a Skipped Set's capsule
    /// only logs, because a hold could only skip it again (#820). Its More menu clears it.
    static func forSet(in state: SetState) -> HoldToSkipPolicy? {
        switch state {
        case .pending: .standard
        case .logged: .loggedState
        case .skipped: nil
        }
    }

    var progressAnimationDuration: TimeInterval {
        max(holdDuration - revealDelay, 0)
    }
}

enum HoldToSkipEffect: Equatable, Sendable {
    case clearFill
    case revealFill(over: TimeInterval)
    case retreatFill
    case log
    case skip
}

struct HoldToSkipGesture: Equatable, Sendable {
    private enum Phase: Equatable, Sendable {
        case idle
        case pressing(since: ContinuousClock.Instant, policy: HoldToSkipPolicy?, revealed: Bool)
        case skipped(fingerDown: Bool)
    }

    private static let tapMaximum = milliseconds(Theme.holdToSkipTapMaximumDuration)
    private static let tapSuppression = milliseconds(Theme.holdToSkipTapSuppression)

    private var phase: Phase = .idle
    private var suppressTapsUntil: ContinuousClock.Instant?

    var isPressing: Bool {
        if case .pressing = phase { return true }
        return false
    }

    var nextDeadline: ContinuousClock.Instant? {
        guard case .pressing(let since, let policy?, let revealed) = phase else { return nil }
        let deadlines = Self.deadlines(since: since, policy: policy)
        return revealed ? deadlines.commit : deadlines.reveal
    }

    /// A nil `policy` is a press on a capsule that takes no hold, so its release only logs or cancels.
    mutating func pressBegan(at now: ContinuousClock.Instant, policy: HoldToSkipPolicy?) -> [HoldToSkipEffect] {
        switch phase {
        case .pressing, .skipped(fingerDown: true): return []
        case .idle, .skipped(fingerDown: false): break
        }
        phase = .pressing(since: now, policy: policy, revealed: false)
        return [.clearFill]
    }

    mutating func deadlineReached(at now: ContinuousClock.Instant) -> [HoldToSkipEffect] {
        guard case .pressing(let since, let policy?, let revealed) = phase else { return [] }
        let deadlines = Self.deadlines(since: since, policy: policy)
        if now >= deadlines.commit {
            return skip(at: now, fingerDown: true)
        }
        guard !revealed, now >= deadlines.reveal else { return [] }
        phase = .pressing(since: since, policy: policy, revealed: true)
        return [.revealFill(over: policy.progressAnimationDuration)]
    }

    mutating func pressEnded(at now: ContinuousClock.Instant) -> [HoldToSkipEffect] {
        guard case .pressing(let since, let policy, _) = phase else {
            if phase == .skipped(fingerDown: true) {
                phase = .skipped(fingerDown: false)
                suppressTapsUntil = now + Self.tapSuppression
            }
            return []
        }
        let held = since.duration(to: now)
        if let policy, held >= Self.milliseconds(policy.holdDuration) {
            return skip(at: now, fingerDown: false)
        }
        phase = .idle
        if held > Self.tapMaximum {
            suppressTapsUntil = now + Self.tapSuppression
        }
        return [.retreatFill]
    }

    mutating func tapped(at now: ContinuousClock.Instant) -> [HoldToSkipEffect] {
        if case .pressing(_, _, revealed: true) = phase {
            return []
        }
        if let until = suppressTapsUntil, now < until {
            suppressTapsUntil = nil
            return []
        }
        if case .pressing = phase {
            phase = .idle
        }
        return [.log]
    }

    mutating func skipRequested(at now: ContinuousClock.Instant) -> [HoldToSkipEffect] {
        if case .pressing = phase {
            return skip(at: now, fingerDown: true)
        }
        return skip(at: now, fingerDown: false)
    }

    mutating func disappeared() {
        if case .pressing = phase {
            phase = .idle
        }
    }

    private mutating func skip(at now: ContinuousClock.Instant, fingerDown: Bool) -> [HoldToSkipEffect] {
        if case .skipped = phase { return [] }
        phase = .skipped(fingerDown: fingerDown)
        suppressTapsUntil = now + Self.tapSuppression
        return [.skip]
    }

    private static func deadlines(
        since: ContinuousClock.Instant,
        policy: HoldToSkipPolicy
    ) -> (reveal: ContinuousClock.Instant, commit: ContinuousClock.Instant) {
        (since + milliseconds(policy.revealDelay), since + milliseconds(policy.holdDuration))
    }

    private static func milliseconds(_ seconds: TimeInterval) -> Duration {
        .milliseconds(Int((seconds * 1_000).rounded()))
    }
}
