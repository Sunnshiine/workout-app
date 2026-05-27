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

enum SessionProgressSegmentState: Equatable, Sendable {
    case logged
    case skipped
    case currentPending
    case futurePending
}

struct SessionProgressSegmentPresentation: Equatable, Sendable {
    let state: SessionProgressSegmentState
}

struct SessionProgressHeaderPresentation: Equatable, Sendable {
    let locationLabel: String
    let locationText: String
    let completedSetCount: Int
    let totalSetCount: Int
    let segments: [SessionProgressSegmentPresentation]

    var remainingSetCount: Int {
        totalSetCount - completedSetCount
    }

    var remainingText: String {
        "\(remainingSetCount) left"
    }

    init(session: Session, activeSetID: ActiveSetID? = nil) {
        let weekNumber = session.week?.number ?? 0
        locationLabel = "W\(weekNumber) D\(session.dayNumber)"
        locationText = "\(locationLabel) ›"

        let sets = session.exercises
            .sorted { $0.order < $1.order }
            .flatMap { exercise in
                exercise.sets.sorted { $0.index < $1.index }.map { set in
                    (id: ActiveSetID(exerciseOrder: exercise.order, setIndex: set.index), set: set)
                }
            }
        totalSetCount = sets.count
        completedSetCount = sets.filter { $0.set.state == .logged || $0.set.state == .skipped }.count
        let pendingSetIDs = sets.filter { $0.set.state == .pending }.map(\.id)
        let currentPendingID =
            if let activeSetID, pendingSetIDs.contains(activeSetID) {
                activeSetID
            } else {
                pendingSetIDs.first
            }
        segments = sets.map { pair in
            switch pair.set.state {
            case .logged:
                return SessionProgressSegmentPresentation(state: .logged)
            case .skipped:
                return SessionProgressSegmentPresentation(state: .skipped)
            case .pending:
                if pair.id == currentPendingID {
                    return SessionProgressSegmentPresentation(state: .currentPending)
                }
                return SessionProgressSegmentPresentation(state: .futurePending)
            }
        }
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

struct LastPerformedCardPresentation: Equatable, Sendable {
    let label: String
    let resultText: String
    let sourceText: String

    init(entry: LastPerformedEntry) {
        label = "Last Performed"
        resultText = entry.result.formatted
        sourceText = entry.source
    }

    @MainActor
    init?(exercise: Exercise, index: LastPerformedIndex) {
        guard let entry = index.lookup(exerciseName: exercise.name, baseName: exercise.baseName) else {
            return nil
        }
        self.init(entry: entry)
    }
}
