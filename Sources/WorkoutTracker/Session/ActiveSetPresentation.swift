import Foundation

enum HoldToSkipButtonTone: Equatable, Sendable {
    case primary
    case incomplete
}

struct HoldToSkipButtonPresentation: Equatable, Sendable {
    let progress: Double
    let logTitle: String
    let canLog: Bool
    let setState: SetState

    init(progress: Double, logTitle: String, canLog: Bool = true, setState: SetState = .pending) {
        self.progress = progress
        self.logTitle = logTitle
        self.canLog = canLog
        self.setState = setState
    }

    /// The hold a press on this capsule takes; nil when it takes none.
    var holdPolicy: HoldToSkipPolicy? {
        .forSet(in: setState)
    }

    /// How long SwiftUI's long press runs before it reports the press over. It is never shorter
    /// than the hold, so the reducer's own commit deadline arrives first.
    var longPressDuration: TimeInterval {
        (holdPolicy ?? .standard).holdDuration
    }

    /// The capsule settles into the dashed empty bed once its Set is Skipped (DESIGN.md §5.3).
    var showsSkippedBed: Bool {
        setState == .skipped
    }

    /// Whether the capsule offers Skip at all, by hold or by the accessibility action.
    var offersSkip: Bool {
        holdPolicy != nil
    }

    var skipOpacity: Double {
        clampedProgress
    }

    var logOpacity: Double {
        1 - clampedProgress
    }

    var accessibilityLabel: String {
        showsSkippedBed || clampedProgress > 0 ? "Skipped" : logTitle
    }

    var accessibilityValue: String {
        clampedProgress > 0 ? "\(Int((clampedProgress * 100).rounded()))% Skip" : ""
    }

    var accessibilityHint: String {
        switch (canLog, offersSkip) {
        case (true, true): "Double tap to log. Press and hold to skip."
        case (true, false): "Double tap to log."
        case (false, true): "Double tap to show what is missing. Press and hold to skip this Set."
        case (false, false): "Double tap to show what is missing."
        }
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
    /// "Set 2, 5 · RPE 8", or "Set 2" alone when the coach left Reps and Load blank.
    let accessibilityLabel: String

    init(set: ExerciseSet) {
        let title = Self.title(of: set)
        self.title = title
        accessibilityLabel = title.isEmpty ? "Set \(set.index + 1)" : "Set \(set.index + 1), \(title)"
    }

    private static func title(of set: ExerciseSet) -> String {
        switch set.state {
        case .logged:
            set.setLog?.formatted ?? set.displayReps
        case .skipped:
            SetLogToken.skipSentinel
        case .pending:
            [set.prescribedReps, set.prescribedLoad]
                .filter { !$0.isEmpty }
                .joined(separator: " · ")
        }
    }
}

enum SetCardMode: Equatable, Sendable {
    case logging
    case reviewingLogged
    /// A Set just written by speech, which reads as written: only its Clear menu changes it.
    case held
}

/// What the head of the Set card shows at its trailing edge (DESIGN.md §5.2).
enum SetCardHeadAccessory: Equatable, Sendable {
    case none
    case saved
    case clearMenu
    /// A Set written by speech: the write and its undo.
    case savedAndClearMenu
}

@MainActor
extension SetCardSlot.Mode {
    var cardMode: SetCardMode {
        switch self {
        case .logging: .logging
        case .reviewingLogged: .reviewingLogged
        case .heldAfterSpokenWrite: .held
        }
    }

    func headAccessory(for set: ExerciseSet) -> SetCardHeadAccessory {
        switch self {
        case .heldAfterSpokenWrite: .savedAndClearMenu
        case .reviewingLogged(showsSavedConfirmation: true): .saved
        case .logging, .reviewingLogged: SetCardPresentation(mode: cardMode, set: set).showsClearMenu ? .clearMenu : .none
        }
    }
}

struct SetCardPresentation: Equatable, Sendable {
    enum ActionRow: Equatable, Sendable {
        case log
        case skipped
        case logged(line: String)
        case incompleteDraft

        /// A Set as written: Skipped, or its logged line.
        @MainActor
        static func written(_ set: ExerciseSet) -> ActionRow {
            set.state == .skipped ? .skipped : .logged(line: set.displayReps)
        }
    }

    static let incompleteDraftHint = "Complete weight, reps, and RPE"

    let showsClearMenu: Bool
    let commitsChangesOnDisappear: Bool
    /// False leaves every value and the action capsule untouchable, for touch and VoiceOver alike.
    let editsValues: Bool
    private let row: ActionRow
    private let incompleteDraftRow: ActionRow

    @MainActor
    init(mode: SetCardMode, set: ExerciseSet) {
        switch mode {
        case .logging:
            showsClearMenu = set.state != .pending
            commitsChangesOnDisappear = false
            editsValues = true
            row = set.state == .skipped ? .skipped : .log
            incompleteDraftRow = row
        case .reviewingLogged:
            showsClearMenu = false
            commitsChangesOnDisappear = true
            editsValues = true
            row = .logged(line: set.displayReps)
            let isUnstructuredSetLog = set.setLog == nil
            incompleteDraftRow = isUnstructuredSetLog ? row : .incompleteDraft
        case .held:
            showsClearMenu = false
            commitsChangesOnDisappear = false
            editsValues = false
            row = .written(set)
            incompleteDraftRow = row
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
        let locationCore = session.placement.locationText(separator: " · ")
        if let block {
            runlineText = "\(block.tabName) · \(locationCore)"
        } else {
            runlineText = locationCore
        }
        locationActionAccessibilityLabel = "Open Block Overview for \(session.placement.locationText(separator: ", "))"

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
        guard let entry = lookup.lookup(for: exercise.exerciseName) else {
            return nil
        }
        resultText = entry.resultText
        sourceText = entry.sourceText
        matchedName = entry.matchedName
    }
}
