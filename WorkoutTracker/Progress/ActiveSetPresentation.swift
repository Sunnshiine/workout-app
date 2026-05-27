import Foundation

enum SetRowTone: Equatable, Sendable {
    case accent
    case muted
}

struct SetRowPresentation: Equatable, Sendable {
    let title: String
    let tone: SetRowTone
    let showsCheckmark: Bool

    init(set: ExerciseSet) {
        switch set.state {
        case .logged:
            title = set.setLog?.formatted ?? set.displayReps
            tone = .accent
            showsCheckmark = true
        case .skipped:
            title = "skip"
            tone = .muted
            showsCheckmark = false
        case .pending:
            title = [set.prescribedReps, set.prescribedLoad]
                .filter { !$0.isEmpty }
                .joined(separator: " · ")
            tone = .muted
            showsCheckmark = false
        }
    }
}

struct SessionProgressHeaderPresentation: Equatable, Sendable {
    let breadcrumb: String
    let completedSetCount: Int
    let totalSetCount: Int

    var remainingSetCount: Int {
        totalSetCount - completedSetCount
    }

    var remainingText: String {
        "\(remainingSetCount) left"
    }

    var progress: Double {
        guard totalSetCount > 0 else { return 0 }
        return Double(completedSetCount) / Double(totalSetCount)
    }

    init(session: Session) {
        let weekNumber = session.week?.number ?? 0
        let blockName = session.week?.block?.tabName ?? "Block"
        breadcrumb = "\(blockName) · W\(weekNumber) D\(session.dayNumber)"

        let sets = session.exercises.flatMap(\.sets)
        totalSetCount = sets.count
        completedSetCount = sets.filter { $0.state == .logged || $0.state == .skipped }.count
    }
}

struct ExerciseSummaryRowPresentation: Equatable, Sendable {
    let title: String

    init(exercise: Exercise) {
        var previousWeight: Weight?
        let setResults = exercise.sets
            .sorted { $0.index < $1.index }
            .compactMap { set -> String? in
                guard set.state != .skipped else { return "skip" }
                guard set.state == .logged, let setLog = set.setLog else { return nil }
                defer { previousWeight = setLog.weight }
                if previousWeight == setLog.weight {
                    return "×\(setLog.reps)"
                }
                return "\(setLog.weight.label)×\(setLog.reps)"
            }
            .joined(separator: " / ")
        title = "✓ \(exercise.baseName) · \(setResults)"
    }
}
