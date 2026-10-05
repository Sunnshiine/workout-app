import Foundation

enum HoldToSkipEffect: Equatable, Sendable {
    case progress(to: Double, over: TimeInterval, linear: Bool)
    case log
    case skip
}

extension HoldToSkipPolicy {
    /// The hold a Set in `state` must survive before it commits (DESIGN.md, Hold to skip).
    static func forSet(in state: SetState) -> HoldToSkipPolicy {
        switch state {
        case .pending: .standard
        case .logged: .loggedState
        case .skipped: .skippedState
        }
    }
}

/// Hold-to-skip as a pure value: every input carries the instant it happened, and the view
/// sleeps until `nextDeadline` inside a `.task(id:)`, so SwiftUI cancels the wait when the card goes.
struct HoldToSkipGesture: Equatable, Sendable {
    private enum Phase: Equatable, Sendable {
        case idle
        case pressing(since: ContinuousClock.Instant, policy: HoldToSkipPolicy, revealed: Bool)
        case committed
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
        if case .pressing = phase { return [] }
        phase = .pressing(since: now, policy: policy, revealed: false)
        return [.progress(to: 0, over: 0, linear: true)]
    }

    mutating func deadlineReached(at now: ContinuousClock.Instant) -> [HoldToSkipEffect] {
        guard case .pressing(let since, let policy, let revealed) = phase else { return [] }
        let deadlines = Self.deadlines(since: since, policy: policy)
        if now >= deadlines.commit {
            return commit(at: now)
        }
        guard !revealed, now >= deadlines.reveal else { return [] }
        phase = .pressing(since: since, policy: policy, revealed: true)
        return [.progress(to: 1, over: policy.progressAnimationDuration, linear: true)]
    }

    mutating func pressEnded(at now: ContinuousClock.Instant) -> [HoldToSkipEffect] {
        guard case .pressing(let since, let policy, _) = phase else {
            if phase == .committed {
                suppressTapsUntil = now + Self.tapSuppression
            }
            phase = .idle
            return []
        }
        phase = .idle
        switch policy.releaseOutcome(elapsed: since.duration(to: now) / .seconds(1), skipCompleted: false) {
        case .skip:
            return commit(at: now)
        case .deferToTap:
            return [Self.retreat]
        case .cancelSkip, .ignore:
            suppressTapsUntil = now + Self.tapSuppression
            return [Self.retreat]
        }
    }

    mutating func tapped(at now: ContinuousClock.Instant) -> [HoldToSkipEffect] {
        if let until = suppressTapsUntil, now < until {
            suppressTapsUntil = nil
            return []
        }
        return [.log]
    }

    mutating func skipRequested(at now: ContinuousClock.Instant) -> [HoldToSkipEffect] {
        commit(at: now)
    }

    private mutating func commit(at now: ContinuousClock.Instant) -> [HoldToSkipEffect] {
        guard phase != .committed else { return [] }
        phase = .committed
        suppressTapsUntil = now + Self.tapSuppression
        return [.skip]
    }

    private static let retreat = HoldToSkipEffect.progress(to: 0, over: Theme.Motion.holdToSkipRetreat, linear: false)

    private static func deadlines(
        since: ContinuousClock.Instant,
        policy: HoldToSkipPolicy
    ) -> (reveal: ContinuousClock.Instant, commit: ContinuousClock.Instant) {
        (since + milliseconds(policy.revealDelay), since + milliseconds(policy.holdDuration))
    }

    /// The policy's durations are millisecond tokens, and `Duration.seconds(1.1)` lands 96 attoseconds
    /// past 1100 ms.
    private static func milliseconds(_ seconds: TimeInterval) -> Duration {
        .milliseconds(Int((seconds * 1_000).rounded()))
    }
}
