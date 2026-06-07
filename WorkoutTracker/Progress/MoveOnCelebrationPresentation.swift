import Foundation

struct MoveOnCelebrationStatPresentation: Equatable, Sendable {
    let value: String
    let label: String
}

enum MoveOnCelebrationHapticStyle: Equatable, Hashable, Sendable {
    case success
    case successWithImpact
}

enum MoveOnCelebrationTimingPresentation: Equatable, Sendable {
    case available(String)
    case unavailable
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

    let markText: String
    let contextText: String
    let actionText: String
    let setsCopyText: String
    let stats: [MoveOnCelebrationStatPresentation]
    let quoteText: String
    let tapHintText: String
    let accessibilityLabel: String
    let accessibilityValue: String
    let accessibilityHint: String
    let hapticStyle: MoveOnCelebrationHapticStyle
    let timing: MoveOnCelebrationTimingPresentation

    @MainActor
    init(session: Session, requestedAt: Date? = nil, quoteText requestedQuoteText: String? = nil) {
        let weekNumber = session.week?.number ?? 0
        let sets = session.exercises.flatMap(\.sets)
        let totalSetCount = sets.count
        let exerciseCount = session.exercises.count
        let pendingSetCount = sets.filter { $0.state == .pending }.count
        let selectedQuote = requestedQuoteText ?? Self.launchQuoteOverride ?? Self.approvedQuotes.randomElement() ?? ""
        let timing = Self.timingPresentation(for: sets, requestedAt: requestedAt)
        let timingStats: [MoveOnCelebrationStatPresentation]
        if case .available(let value) = timing {
            timingStats = [MoveOnCelebrationStatPresentation(value: value, label: "Time")]
        } else {
            timingStats = []
        }

        markText = "TFN"
        contextText = "Week \(weekNumber) · Day \(session.dayNumber)"
        actionText = "Move On"
        setsCopyText = "Logged Sets are saved. Open Sets stay with the Week."
        stats = timingStats + [
            MoveOnCelebrationStatPresentation(value: "\(totalSetCount)", label: "Sets"),
            MoveOnCelebrationStatPresentation(value: "\(exerciseCount)", label: "Exercises"),
            MoveOnCelebrationStatPresentation(value: "\(pendingSetCount)", label: "Left")
        ]
        quoteText = selectedQuote
        tapHintText = "Tap anywhere to continue"
        accessibilityLabel = "Week \(weekNumber), Day \(session.dayNumber)"
        accessibilityValue = ([actionText, selectedQuote, setsCopyText] + stats.map { "\($0.value) \($0.label)" })
            .joined(separator: ", ")
        accessibilityHint = tapHintText
        hapticStyle = pendingSetCount == 0 ? .successWithImpact : .success
        self.timing = timing
    }

    private static var launchQuoteOverride: String? {
        guard ProcessInfo.processInfo.arguments.contains("-UITEST_LONG_CELEBRATION_QUOTE") else {
            return nil
        }
        return longQuoteFixture
    }

    private static func timingPresentation(
        for sets: [ExerciseSet],
        requestedAt: Date?
    ) -> MoveOnCelebrationTimingPresentation {
        let loggedSets = sets.filter { $0.state == .logged }
        guard
            let requestedAt,
            !loggedSets.isEmpty,
            loggedSets.allSatisfy({ $0.loggedAt != nil }),
            let firstLoggedAt = loggedSets.compactMap(\.loggedAt).min()
        else { return .unavailable }

        return .available(elapsedText(from: firstLoggedAt, to: requestedAt))
    }

    private static func elapsedText(from start: Date, to end: Date) -> String {
        let elapsedSeconds = max(0, Int(end.timeIntervalSince(start).rounded(.down)))
        let elapsedMinutes = elapsedSeconds / 60
        guard elapsedMinutes > 0 else { return "<1m" }
        guard elapsedMinutes >= 60 else { return "\(elapsedMinutes)m" }

        let hours = elapsedMinutes / 60
        let minutes = elapsedMinutes % 60
        return minutes == 0 ? "\(hours)h" : "\(hours)h \(minutes)m"
    }
}
