struct MoveOnCelebrationStatPresentation: Equatable, Sendable {
    let value: String
    let label: String
}

struct MoveOnCelebrationPresentation: Equatable, Sendable {
    let weekText: String
    let titleText: String
    let sublineText: String
    let stats: [MoveOnCelebrationStatPresentation]
    let accessibilityLabel: String
    let accessibilityValue: String

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
        accessibilityLabel = "\(weekText), \(titleText)"
        accessibilityValue = (stats.map { "\($0.value) \($0.label)" } + [sublineText])
            .joined(separator: ", ")
    }
}
