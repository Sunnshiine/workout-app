import Foundation

struct MoveOnCelebrationStatPresentation: Equatable, Sendable {
    let value: String
    let label: String
}

/// The one swell-and-peak Move On haptic pattern, identical on every day.
///
/// Completion, Not Achievement (DESIGN.md §5.7): the ceremony marks the
/// athlete's explicit choice to Move On, not the quality of the day — so there
/// is exactly one pattern, never a richer variant for a perfect Session.
enum MoveOnCelebrationHaptic: Equatable, Hashable, Sendable {
    case moveOn
}

/// The presentation-model seam for the Move On ceremony. Derives the ceremony's
/// copy and stats from the closed Session; the view owns the branch-grow-and-land
/// choreography and the shared soft surface.
struct MoveOnCelebrationPresentation: Equatable, Sendable {
    static let longQuoteFixture =
        "Strong work is still strong when today asks you to leave a few Sets for later; take the win, keep the thread, and come back ready."
    static let approvedQuotes = [
        "You're fucking amazing.",
        "God damn!",
        "Get it girl!",
        "Shake it!"
    ]

    let contextText: String
    let actionText: String
    let quoteText: String
    let setsCopyText: String
    let stats: [MoveOnCelebrationStatPresentation]
    let tapHintText: String
    let accessibilityLabel: String
    let accessibilityValue: String
    let accessibilityHint: String
    let haptic: MoveOnCelebrationHaptic

    @MainActor
    init(session: Session, quoteText requestedQuoteText: String? = nil) {
        let weekNumber = session.week?.number ?? 0
        let sets = session.exercises.flatMap(\.sets)
        let totalSetCount = sets.count
        let exerciseCount = session.exercises.count
        let pendingSetCount = session.pendingSetCount
        let selectedQuote = requestedQuoteText ?? Self.launchQuoteOverride ?? Self.approvedQuotes.randomElement() ?? ""

        contextText = "Week \(weekNumber) · Day \(session.dayNumber)"
        actionText = "Move On"
        quoteText = selectedQuote
        setsCopyText = "Logged Sets are saved. Open Sets stay with the Week."
        stats = [
            MoveOnCelebrationStatPresentation(value: "\(totalSetCount)", label: "Sets"),
            MoveOnCelebrationStatPresentation(value: "\(exerciseCount)", label: "Exercises"),
            MoveOnCelebrationStatPresentation(value: "\(pendingSetCount)", label: "Left")
        ]
        tapHintText = "Tap anywhere to continue"
        accessibilityLabel = "Week \(weekNumber), Day \(session.dayNumber)"
        accessibilityValue = ([actionText, selectedQuote, setsCopyText] + stats.map { "\($0.value) \($0.label)" })
            .joined(separator: ", ")
        accessibilityHint = tapHintText
        // One pattern, always — the ceremony must not curdle on an ordinary day
        // with Skipped Sets, and must not swell richer on a perfect Session.
        haptic = .moveOn
    }

    private static var launchQuoteOverride: String? {
        guard ProcessInfo.processInfo.arguments.contains("-UITEST_LONG_CELEBRATION_QUOTE") else {
            return nil
        }
        return longQuoteFixture
    }
}
