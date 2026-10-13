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
        holdDuration: TimeInterval = Theme.Motion.holdToSkipCommit,
        tapMaximumDuration: TimeInterval = Theme.holdToSkipTapMaximumDuration,
        revealDelay: TimeInterval = Theme.Motion.holdToSkipReveal
    ) {
        self.holdDuration = holdDuration
        self.tapMaximumDuration = tapMaximumDuration
        self.revealDelay = revealDelay
    }

    /// The idle-Set hold: reveal 250ms, commit 850ms.
    static let standard = HoldToSkipPolicy()

    /// The longer hold a Set already logged must survive before it re-skips (900ms).
    static let loggedState = HoldToSkipPolicy(holdDuration: Theme.Motion.holdToSkipLoggedCommit)

    /// The longest hold, to undo an already-skipped Set (1100ms).
    static let skippedState = HoldToSkipPolicy(holdDuration: Theme.Motion.holdToSkipSkippedCommit)

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

    private var clampedProgress: Double {
        min(max(progress, 0), 1)
    }
}

struct SetRowPresentation: Equatable, Sendable {
    let title: String

    init(set: ExerciseSet) {
        switch set.state {
        case .logged:
            title = set.setLog?.formatted ?? set.displayReps
        case .skipped:
            title = SetLogToken.skipSentinel
        case .pending:
            title = [set.prescribedReps, set.prescribedLoad]
                .filter { !$0.isEmpty }
                .joined(separator: " · ")
        }
    }
}

enum SetCardMode: Equatable, Sendable {
    case logging
    case reviewingLogged
}

struct SetCardPresentation: Equatable, Sendable {
    enum ActionRow: Equatable, Sendable {
        case log
        case skipped
        case logged(line: String)
        case incompleteDraft
    }

    static let incompleteDraftHint = "Complete weight, reps, and RPE"

    let showsClearMenu: Bool
    let commitsChangesOnDisappear: Bool
    private let row: ActionRow
    private let incompleteDraftRow: ActionRow

    @MainActor
    init(mode: SetCardMode, set: ExerciseSet) {
        switch mode {
        case .logging:
            showsClearMenu = set.state != .pending
            commitsChangesOnDisappear = false
            row = set.state == .skipped ? .skipped : .log
            incompleteDraftRow = row
        case .reviewingLogged:
            showsClearMenu = false
            commitsChangesOnDisappear = true
            row = .logged(line: set.displayReps)
            let isUnstructuredSetLog = set.setLog == nil
            incompleteDraftRow = isUnstructuredSetLog ? row : .incompleteDraft
        }
    }

    @MainActor
    func actionRow(for draft: SmartValuePillsForm) -> ActionRow {
        draft.hasChanges && !draft.canLog ? incompleteDraftRow : row
    }
}

struct SessionProgressHeaderPresentation: Equatable, Sendable {
    let runlineText: String
    let completedSetCount: Int
    let totalSetCount: Int
    let locationActionAccessibilityLabel: String
    let progressAccessibilityValue: String

    var remainingSetCount: Int {
        totalSetCount - completedSetCount
    }

    var remainingText: String {
        remainingSetCount == 1 ? "1 Set left" : "\(remainingSetCount) Sets left"
    }

    init(session: Session, block: Block? = nil) {
        let weekNumber = session.week?.number ?? 0
        let dayNumber = session.dayNumber
        let locationCore = "Week \(weekNumber) · Day \(dayNumber)"
        if let block {
            runlineText = "\(block.tabName) · \(locationCore)"
        } else {
            runlineText = locationCore
        }
        locationActionAccessibilityLabel = "Open Block Overview for Week \(weekNumber), Day \(dayNumber)"

        let sets = session.exercises
            .sorted { $0.order < $1.order }
            .flatMap { exercise in
                exercise.sets.sorted { $0.index < $1.index }.map { set in
                    (id: ActiveSetID(exerciseOrder: exercise.order, setIndex: set.index), set: set)
                }
            }
        totalSetCount = sets.count
        completedSetCount = session.completedSetCount
        let remaining = totalSetCount - completedSetCount
        let remainingPhrase = remaining == 1 ? "1 Set left" : "\(remaining) Sets left"
        progressAccessibilityValue = "\(runlineText), \(remainingPhrase)"
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

struct LastPerformedCardPresentation: Equatable, Sendable {
    let resultText: String
    let sourceText: String
    /// The matched entry's own entered name for a tier-3 (Movement-level) line, rendered
    /// *as "…"* in muted italic — nil for the byte-identical tier-1/2 lines (ADR-0013).
    let matchedName: String?

    init(entry: LastPerformedEntry) {
        resultText = entry.resultText
        sourceText = entry.source
        matchedName = nil
    }

    init?(exercise: Exercise, lookup: LastPerformedLookupSnapshot) {
        guard let entry = lookup.lookup(for: exercise.name) else {
            return nil
        }
        resultText = entry.resultText
        sourceText = entry.sourceText
        matchedName = entry.matchedName
    }
}

struct ActiveSupersetSidePresentation: Equatable, Sendable {
    let exerciseOrder: Int
    let isActive: Bool
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
        guard exercises.count == 2, exercises.allSatisfy(\.hasPendingSet) else { return nil }
        self.activeSetID = activeSetID
        // A / B identity follows Session (sheet) order: the higher Exercise is A.
        sides = exercises.sorted { $0.order < $1.order }.map { exercise in
            ActiveSupersetSidePresentation(
                exerciseOrder: exercise.order,
                isActive: exercise.order == activeSetID?.exerciseOrder
            )
        }
    }
}
