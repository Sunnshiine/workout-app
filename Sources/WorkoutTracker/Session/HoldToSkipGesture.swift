import Foundation

enum HoldToSkipEffect: Equatable, Sendable {
    case clearFill
    case revealFill(over: TimeInterval)
    case retreatFill
    case log
    case skip
}

extension HoldToSkipPolicy {
    static func forSet(in state: SetState) -> HoldToSkipPolicy {
        switch state {
        case .pending: .standard
        case .logged: .loggedState
        case .skipped: .skippedState
        }
    }
}

struct HoldToSkipGesture: Equatable, Sendable {
    private enum Phase: Equatable, Sendable {
        case idle
        case pressing(since: ContinuousClock.Instant, policy: HoldToSkipPolicy, revealed: Bool)
        case skipped(fingerDown: Bool)
    }

    private static let tapSuppression = Duration.milliseconds(250)

    private var phase: Phase = .idle
    private var suppressTapsUntil: ContinuousClock.Instant?

    var nextDeadline: ContinuousClock.Instant? {
        guard case .pressing(let since, let policy, let revealed) = phase else { return nil }
        let deadlines = Self.deadlines(since: since, policy: policy)
        return revealed ? deadlines.commit : deadlines.reveal
    }

    mutating func pressBegan(at now: ContinuousClock.Instant, policy: HoldToSkipPolicy) -> [HoldToSkipEffect] {
        switch phase {
        case .pressing, .skipped(fingerDown: true): return []
        case .idle, .skipped(fingerDown: false): break
        }
        phase = .pressing(since: now, policy: policy, revealed: false)
        return [.clearFill]
    }

    mutating func deadlineReached(at now: ContinuousClock.Instant) -> [HoldToSkipEffect] {
        guard case .pressing(let since, let policy, let revealed) = phase else { return [] }
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
        switch policy.releaseOutcome(elapsed: since.duration(to: now) / .seconds(1), skipCompleted: false) {
        case .skip:
            return skip(at: now, fingerDown: false)
        case .deferToTap:
            phase = .idle
            return [.retreatFill]
        case .cancelSkip, .ignore:
            phase = .idle
            suppressTapsUntil = now + Self.tapSuppression
            return [.retreatFill]
        }
    }

    mutating func tapped(at now: ContinuousClock.Instant) -> [HoldToSkipEffect] {
        if case .pressing(_, _, revealed: true) = phase {
            return []
        }
        if let until = suppressTapsUntil, now < until {
            suppressTapsUntil = nil
            return []
        }
        return [.log]
    }

    mutating func skipRequested(at now: ContinuousClock.Instant) -> [HoldToSkipEffect] {
        if case .pressing = phase {
            return skip(at: now, fingerDown: true)
        }
        return skip(at: now, fingerDown: false)
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
