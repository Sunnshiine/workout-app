import Foundation

struct MoveOnCelebrationStatPresentation: Equatable, Sendable {
    let value: String
    let label: String
}

/// The copy and stats behind the Move On ceremony (DESIGN.md §5.7, picks
/// sunbird-moments-a/-d). The ceremony marks **completion, not achievement**: the
/// Fraunces title names the finished day, the coach's line reads below the grown
/// branch, and the stats surface the day's shape. There is no richer variant for a
/// perfect Session, no elapsed-time UI, and no confetti — those rules are dead.
struct MoveOnCelebrationPresentation: Equatable, Sendable {
    static let longQuoteFixture =
        "Strong work is still strong when today asks you to leave a few Sets for later; take the win, keep the thread, and come back ready."
    static let approvedQuotes = [
        "You're fucking amazing.",
        "God damn!",
        "Get it girl!",
        "Shake it!"
    ]

    let titleText: String
    let contextText: String
    let actionText: String
    let quoteText: String
    let continueText: String
    let stats: [MoveOnCelebrationStatPresentation]
    let accessibilityLabel: String
    let accessibilityValue: String
    let accessibilityHint: String

    @MainActor
    init(session: Session, quoteText requestedQuoteText: String? = nil) {
        let weekNumber = session.week?.number ?? 0
        let dayNumber = session.dayNumber
        let sets = session.exercises.flatMap(\.sets)
        let totalSetCount = sets.count
        let exerciseCount = session.exercises.count
        let pendingSetCount = session.pendingSetCount
        let selectedQuote = requestedQuoteText ?? Self.launchQuoteOverride ?? Self.approvedQuotes.randomElement() ?? ""

        let locationCore = "Week \(weekNumber) · Day \(dayNumber)"
        titleText = "Day \(dayNumber), done."
        if let tabName = session.week?.block?.tabName {
            contextText = "\(tabName) · \(locationCore)"
        } else {
            contextText = locationCore
        }
        actionText = "Move On"
        quoteText = selectedQuote
        continueText = "Continue"
        stats = [
            MoveOnCelebrationStatPresentation(value: "\(totalSetCount)", label: "Sets"),
            MoveOnCelebrationStatPresentation(value: "\(exerciseCount)", label: "Exercises"),
            MoveOnCelebrationStatPresentation(value: "\(pendingSetCount)", label: "Left")
        ]
        accessibilityLabel = "Week \(weekNumber), Day \(dayNumber)"
        accessibilityValue = ([titleText, selectedQuote] + stats.map { "\($0.value) \($0.label)" })
            .joined(separator: ", ")
        accessibilityHint = "Double tap to continue"
    }

    private static var launchQuoteOverride: String? {
        guard ProcessInfo.processInfo.arguments.contains("-UITEST_LONG_CELEBRATION_QUOTE") else {
            return nil
        }
        return longQuoteFixture
    }
}
