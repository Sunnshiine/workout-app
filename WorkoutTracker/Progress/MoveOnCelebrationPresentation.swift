struct MoveOnCelebrationStatPresentation: Equatable, Sendable {
    let value: String
    let label: String
}

enum MoveOnCelebrationHapticStyle: Equatable, Hashable, Sendable {
    case success
    case successWithImpact
}

struct MoveOnCelebrationPresentation: Equatable, Sendable {
    static let approvedQuotes = [
        "You're fucking amazing.",
        "God damn!",
        "Get it girl!",
        "Shake it!"
    ]

    let weekText: String
    let titleText: String
    let sublineText: String
    let stats: [MoveOnCelebrationStatPresentation]
    let quoteText: String
    let accessibilityLabel: String
    let accessibilityValue: String
    let hapticStyle: MoveOnCelebrationHapticStyle

    @MainActor
    init(session: Session) {
        let weekNumber = session.week?.number ?? 0
        let sets = session.exercises.flatMap(\.sets)
        let totalSetCount = sets.count
        let exerciseCount = session.exercises.count
        let pendingSetCount = sets.filter { $0.state == .pending }.count

        weekText = "Week \(weekNumber)"
        titleText = "Day \(session.dayNumber) Done"
        sublineText = pendingSetCount == 0 ? "Perfect session" : "Moved on with \(pendingSetCount) left"
        stats = [
            MoveOnCelebrationStatPresentation(value: "\(totalSetCount)", label: "Sets"),
            MoveOnCelebrationStatPresentation(value: "\(exerciseCount)", label: "Exercises"),
            MoveOnCelebrationStatPresentation(value: "\(pendingSetCount)", label: "Left")
        ]
        quoteText = Self.approvedQuotes.randomElement() ?? ""
        accessibilityLabel = "\(weekText), \(titleText)"
        accessibilityValue = (stats.map { "\($0.value) \($0.label)" } + [sublineText])
            .joined(separator: ", ")
        hapticStyle = pendingSetCount == 0 ? .successWithImpact : .success
    }
}
