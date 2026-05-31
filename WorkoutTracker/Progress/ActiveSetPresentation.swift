import CoreGraphics
import Foundation

enum HoldToSkipReleaseOutcome: Equatable, Sendable {
    case log
    case cancelSkip
    case skip
    case ignore
}

struct HoldToSkipPolicy: Equatable, Sendable {
    let holdDuration: TimeInterval
    let tapMaximumDuration: TimeInterval
    let revealDelay: TimeInterval

    init(
        holdDuration: TimeInterval = Theme.holdToSkipDuration,
        tapMaximumDuration: TimeInterval = Theme.holdToSkipTapMaximumDuration,
        revealDelay: TimeInterval = Theme.holdToSkipRevealDelay
    ) {
        self.holdDuration = holdDuration
        self.tapMaximumDuration = tapMaximumDuration
        self.revealDelay = revealDelay
    }

    func releaseOutcome(elapsed: TimeInterval, skipCompleted: Bool) -> HoldToSkipReleaseOutcome {
        if skipCompleted {
            return .ignore
        }

        if elapsed >= holdDuration {
            return .skip
        }

        if elapsed <= tapMaximumDuration {
            return .log
        }

        return .cancelSkip
    }

    func shouldRevealProgress(elapsed: TimeInterval) -> Bool {
        elapsed >= revealDelay && elapsed < holdDuration
    }

    var progressAnimationDuration: TimeInterval {
        max(holdDuration - revealDelay, 0)
    }
}

enum HoldToSkipButtonTone: Equatable, Sendable {
    case primary
    case incomplete
}

struct HoldToSkipButtonPresentation: Equatable, Sendable {
    let progress: Double
    let logTitle: String
    let canLog: Bool

    init(progress: Double, logTitle: String, canLog: Bool = true) {
        self.progress = progress
        self.logTitle = logTitle
        self.canLog = canLog
    }

    var skipOpacity: Double {
        clampedProgress
    }

    var logOpacity: Double {
        1 - clampedProgress
    }

    var accessibilityLabel: String {
        clampedProgress > 0 ? "Skipped" : logTitle
    }

    var accessibilityHint: String {
        if canLog {
            return "Double tap to log. Press and hold to skip."
        }
        return "Double tap to show what is missing. Press and hold to skip this Set."
    }

    var tone: HoldToSkipButtonTone {
        canLog ? .primary : .incomplete
    }

    var controlOpacity: Double {
        1
    }

    var showsSkipAffordance: Bool {
        false
    }

    private var clampedProgress: Double {
        min(max(progress, 0), 1)
    }
}

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

struct LoggedSetReviewPresentation: Equatable, Sendable {
    let statusText: String
    let detailText: String
    let referenceText: String?
    let allowsEditing: Bool

    init(set: ExerciseSet) {
        if let setLog = set.setLog {
            statusText = "Set Log"
            detailText = setLog.formatted
            referenceText = nil
            allowsEditing = true
        } else if let unstructuredSetLog = set.unstructuredSetLog {
            statusText = "Unstructured Set Log"
            detailText = unstructuredSetLog
            referenceText = unstructuredSetLog
            allowsEditing = true
        } else if let legacyLog = set.exercise?.legacyLog {
            statusText = "Legacy Log"
            detailText = legacyLog
            referenceText = nil
            allowsEditing = false
        } else {
            statusText = "Logged Set"
            detailText = set.displayReps
            referenceText = nil
            allowsEditing = false
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
    let locationActionAccessibilityLabel: String
    let progressAccessibilityValue: String

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
        locationActionAccessibilityLabel = "Open Block Overview for Week \(weekNumber), Day \(session.dayNumber)"

        let sets = session.exercises
            .sorted { $0.order < $1.order }
            .flatMap { exercise in
                exercise.sets.sorted { $0.index < $1.index }.map { set in
                    (id: ActiveSetID(exerciseOrder: exercise.order, setIndex: set.index), set: set)
                }
            }
        totalSetCount = sets.count
        completedSetCount = sets.filter { $0.set.state == .logged || $0.set.state == .skipped }.count
        progressAccessibilityValue = "\(locationLabel), \(totalSetCount - completedSetCount) left"
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

struct SessionControlsVisibility: Equatable, Sendable {
    static let hidden = SessionControlsVisibility(isVisible: false)
    static let visible = SessionControlsVisibility(isVisible: true)

    private static let revealOffset: CGFloat = 32
    private static let dismissOffset: CGFloat = -24

    let isVisible: Bool

    func updated(topContentOffset: CGFloat) -> Self {
        if topContentOffset >= Self.revealOffset {
            return .visible
        }

        if isVisible, topContentOffset > Self.dismissOffset {
            return .visible
        }

        return .hidden
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
        let hasStructuredSetLog = exercise.sets.contains { $0.setLog != nil }
        let resultText = !hasStructuredSetLog ? exercise.legacyLog ?? setResults : setResults
        title = "✓ \(exercise.baseName) · \(resultText)"
    }
}

struct LastPerformedCardPresentation: Equatable, Sendable {
    let label: String
    let resultText: String
    let sourceText: String

    init(entry: LastPerformedEntry) {
        label = "Last Performed"
        resultText = entry.displayResultText
        sourceText = entry.source
    }

    init?(exercise: Exercise, lookup: LastPerformedLookupSnapshot) {
        guard let entry = lookup.lookup(exerciseName: exercise.name, baseName: exercise.baseName) else {
            return nil
        }
        label = "Last Performed"
        resultText = entry.resultText
        sourceText = entry.sourceText
    }
}

struct ActiveSupersetSidePresentation: Equatable, Sendable {
    let exerciseOrder: Int
    let exerciseName: String
    let nextSetText: String
    let prescriptionText: String
    let isActive: Bool
    let accessibilityLabel: String
}

struct ActiveSupersetPresentation: Equatable, Sendable {
    let activeSetID: ActiveSetID?
    let sides: [ActiveSupersetSidePresentation]

    var activeExerciseOrder: Int? {
        sides.first { $0.isActive }?.exerciseOrder
    }

    var containerExerciseOrder: Int? {
        sides.map(\.exerciseOrder).min()
    }

    @MainActor
    init?(exercises: [Exercise], activeSetID: ActiveSetID?) {
        guard exercises.count == 2 else { return nil }
        let activeExerciseOrder = activeSetID?.exerciseOrder
        let activeSetIndex = activeSetID?.setIndex
        // A / B identity follows Session (sheet) order: the higher Exercise is A.
        let orderedExercises = exercises.sorted { $0.order < $1.order }
        let sides = orderedExercises.compactMap { exercise -> ActiveSupersetSidePresentation? in
            let sortedSets = exercise.sets.sorted { $0.index < $1.index }
            let isActive = exercise.order == activeExerciseOrder
            let nextSet =
                if isActive {
                    sortedSets.first { set in
                        set.index == activeSetIndex && set.state == .pending
                    }
                } else {
                    sortedSets.first { $0.state == .pending }
                }
            guard let nextSet else { return nil }
            let ordinal = (sortedSets.firstIndex { $0.persistentModelID == nextSet.persistentModelID } ?? nextSet.index) + 1
            let nextSetText = "Set \(ordinal) of \(sortedSets.count)"
            let prescriptionText = [nextSet.prescribedReps, nextSet.prescribedLoad]
                .filter { !$0.isEmpty }
                .joined(separator: " · ")
            return ActiveSupersetSidePresentation(
                exerciseOrder: exercise.order,
                exerciseName: exercise.name,
                nextSetText: nextSetText,
                prescriptionText: prescriptionText,
                isActive: isActive,
                accessibilityLabel: "\(exercise.name), \(nextSetText), \(prescriptionText)"
            )
        }
        guard sides.count == 2 else { return nil }
        self.activeSetID = activeSetID
        self.sides = sides
    }
}
