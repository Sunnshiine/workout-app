import Foundation

struct MoveOnCelebrationStatPresentation: Equatable, Sendable {
    let value: String
    let label: String
}

enum MoveOnCelebrationHapticStyle: Equatable, Hashable, Sendable {
    case success
    case successWithImpact
}

enum MoveOnCelebrationVisualTreatment: Equatable, Sendable {
    case animatedBloom
    case reducedMotionLens
}

struct MoveOnCelebrationBloomMotion: Equatable, Sendable {
    let pulseDuration: TimeInterval
    let loopDuration: TimeInterval

    var repeatCount: Int {
        max(Int((loopDuration / pulseDuration).rounded(.down)), 1)
    }
}

struct MoveOnCelebrationPresentation: Equatable, Sendable {
    static let longQuoteFixture =
        "Strong work is still strong when today asks you to leave a few Sets for later; take the win, keep the thread, and come back ready."
    static let approvedQuotes = [
        "You're fucking amazing.",
        "God damn!",
        "Get it girl!",
        "Shake it!"
    ]
    static let animatedBloomMotion = MoveOnCelebrationBloomMotion(
        pulseDuration: 1.2,
        loopDuration: 7.2
    )

    let contextText: String
    let stats: [MoveOnCelebrationStatPresentation]
    let quoteText: String
    let accessibilityLabel: String
    let accessibilityValue: String
    let accessibilityHint: String
    let hapticStyle: MoveOnCelebrationHapticStyle

    @MainActor
    init(session: Session, quoteText requestedQuoteText: String? = nil) {
        let weekNumber = session.week?.number ?? 0
        let sets = session.exercises.flatMap(\.sets)
        let totalSetCount = sets.count
        let exerciseCount = session.exercises.count
        let pendingSetCount = sets.filter { $0.state == .pending }.count
        let selectedQuote = requestedQuoteText ?? Self.launchQuoteOverride ?? Self.approvedQuotes.randomElement() ?? ""

        contextText = "Week \(weekNumber) · Day \(session.dayNumber)"
        stats = [
            MoveOnCelebrationStatPresentation(value: "\(totalSetCount)", label: "Sets"),
            MoveOnCelebrationStatPresentation(value: "\(exerciseCount)", label: "Exercises"),
            MoveOnCelebrationStatPresentation(value: "\(pendingSetCount)", label: "Left")
        ]
        quoteText = selectedQuote
        accessibilityLabel = "Week \(weekNumber), Day \(session.dayNumber)"
        accessibilityValue = ([selectedQuote] + stats.map { "\($0.value) \($0.label)" })
            .joined(separator: ", ")
        accessibilityHint = "Tap anywhere to continue"
        hapticStyle = pendingSetCount == 0 ? .successWithImpact : .success
    }

    func visualTreatment(reduceMotion: Bool) -> MoveOnCelebrationVisualTreatment {
        reduceMotion ? .reducedMotionLens : .animatedBloom
    }

    func bloomMotion(reduceMotion: Bool) -> MoveOnCelebrationBloomMotion? {
        reduceMotion ? nil : Self.animatedBloomMotion
    }

    private static var launchQuoteOverride: String? {
        guard ProcessInfo.processInfo.arguments.contains("-UITEST_LONG_CELEBRATION_QUOTE") else {
            return nil
        }
        return longQuoteFixture
    }
}
