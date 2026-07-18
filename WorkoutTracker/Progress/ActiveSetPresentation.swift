import CoreGraphics
import Foundation

enum HoldToSkipReleaseOutcome: Equatable, Sendable {
    case deferToTap
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
            return .deferToTap
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
            title = SetLogToken.skipSentinel
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

/// The one Set card serves two modes: logging the active pending Set, or
/// reviewing an already-logged one in place. The mode decides the commit
/// trigger — the Log button when logging, an automatic commit of changed valid
/// values when the review collapses — and the header chrome around the shared
/// weight/reps/RPE fields.
enum SetCardMode: Equatable, Sendable {
    case logging
    case reviewingLogged
}

struct SetCardPresentation: Equatable, Sendable {
    let statusText: String
    /// Original text of an Unstructured Set Log, kept visible as reference
    /// while its structured replacement is edited.
    let referenceText: String?
    let showsLogControls: Bool
    let commitsChangesOnDisappear: Bool

    @MainActor
    init(mode: SetCardMode, set: ExerciseSet) {
        switch mode {
        case .logging:
            statusText = "Up next"
            referenceText = nil
            showsLogControls = true
            commitsChangesOnDisappear = false
        case .reviewingLogged:
            if set.setLog == nil, let unstructuredSetLog = set.unstructuredSetLog {
                statusText = "Unstructured Set Log"
                referenceText = unstructuredSetLog
            } else {
                statusText = "Set Log"
                referenceText = nil
            }
            showsLogControls = false
            commitsChangesOnDisappear = true
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
        completedSetCount = session.completedSetCount
        progressAccessibilityValue = "\(locationLabel), \(totalSetCount - completedSetCount) left"
        let pendingSetIDs = sets.filter { $0.set.isPending }.map(\.id)
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

struct SessionSettingsOverpullState: Equatable, Sendable {
    enum Phase: Equatable, Sendable {
        case hidden
        case pinned
    }

    static let hidden = SessionSettingsOverpullState(phase: .hidden, progress: 0)
    static let pinned = SessionSettingsOverpullState(phase: .pinned, progress: 1)

    static let idleDismissDelay: TimeInterval = 2.5

    private static let revealThreshold: CGFloat = 72
    private static let contentDismissOffset: CGFloat = -16

    let phase: Phase
    let progress: CGFloat

    var isVisible: Bool {
        phase != .hidden
    }

    var isPinned: Bool {
        phase == .pinned
    }

    func tracking(topContentOffset: CGFloat) -> Self {
        // An active upward scroll into the content dismisses the reveal.
        if topContentOffset <= Self.contentDismissOffset {
            return .hidden
        }

        // Once revealed, stay revealed so transient top-edge geometry settling
        // cannot retract the control mid-pull.
        if isVisible {
            return self
        }

        // Reveal as soon as the overpull clears the threshold.
        guard topContentOffset >= Self.revealThreshold else {
            return .hidden
        }

        return .pinned
    }

    func dismissedAfterIdle() -> Self {
        .hidden
    }

    static func overpullDistance(startTopContentOffset: CGFloat, translationHeight: CGFloat) -> CGFloat {
        max(0, startTopContentOffset + translationHeight)
    }
}

struct ExerciseSummaryRowPresentation: Equatable, Sendable {
    let title: String

    init(exercise: Exercise) {
        var previousWeight: Weight?
        let setResults = exercise.sets
            .sorted { $0.index < $1.index }
            .compactMap { set -> String? in
                guard set.state != .skipped else { return SetLogToken.skipSentinel }
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
    /// The matched entry's own entered name for a tier-3 (Movement-level) line, rendered
    /// *as "…"* in muted italic — nil for the byte-identical tier-1/2 lines (ADR-0013).
    let matchedName: String?

    init(entry: LastPerformedEntry) {
        label = "Last Performed"
        resultText = entry.resultText
        sourceText = entry.source
        matchedName = nil
    }

    init?(exercise: Exercise, lookup: LastPerformedLookupSnapshot) {
        guard let entry = lookup.lookup(for: exercise.name) else {
            return nil
        }
        label = "Last Performed"
        resultText = entry.resultText
        sourceText = entry.sourceText
        matchedName = entry.matchedName
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
                    // The resting side shows its next Pending Set — route the ordering-and-first
                    // selection through the Superset owner's single home rather than re-deriving it.
                    SupersetState.nextPendingSet(for: exercise)
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
