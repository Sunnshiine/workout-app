import Foundation

/// A Session render item with the hidden paired entries dropped, plus the
/// progress readings the Stage needs: title, Set order, completion, and the
/// next pending Set.
struct SessionStageItem: Identifiable {
    let item: SessionRenderItem

    var id: String { item.id }

    var exercises: [Exercise] {
        switch item {
        case .exercise(let config): [config.exercise]
        case .superset(let config): config.exercises
        case .hiddenPairedExercise: []
        }
    }

    var title: String {
        switch item {
        case .exercise(let config): config.exercise.name
        case .superset(let config): config.exercises.map(\.baseName).joined(separator: " + ")
        case .hiddenPairedExercise: ""
        }
    }

    var sortedSets: [ExerciseSet] {
        exercises
            .sorted { $0.order < $1.order }
            .flatMap { exercise in
                exercise.sets.sorted { $0.index < $1.index }
            }
    }

    var completedSetCount: Int {
        exercises.reduce(0) { $0 + $1.completedSetCount }
    }

    var isComplete: Bool {
        !exercises.isEmpty && exercises.allSatisfy(\.isComplete)
    }

    var nextPendingSet: ExerciseSet? {
        sortedSets.first { $0.state == .pending }
    }

    func contains(_ setID: ActiveSetID?) -> Bool {
        guard let setID else { return false }
        return exercises.contains { $0.order == setID.exerciseOrder }
    }
}

/// The part a queue row plays while Superset pairing is in flight.
enum QueuePairingRole: Equatable, Sendable {
    case none
    case source
    case eligibleTarget
    case ineligibleTarget
    case confirmingTarget
}

/// Stage resolution: which item is on stage, which Set it shows, what is up
/// next, and the queue/completion summaries. Kept out of the view layer so the
/// Stage's follow-the-focus behavior is unit-testable.
@MainActor
enum SessionStagePresentation {
    /// Stage items in Session order, hidden paired entries dropped.
    static func items(_ renderItems: [SessionRenderItem]) -> [SessionStageItem] {
        renderItems.compactMap { item in
            if case .hiddenPairedExercise = item { return nil }
            return SessionStageItem(item: item)
        }
    }

    /// The item on stage: the one holding visual focus, else the first
    /// incomplete one. `nil` means the Session is complete.
    static func stageItem(in items: [SessionStageItem], focusID: ActiveSetID?) -> SessionStageItem? {
        if let item = items.first(where: { $0.contains(focusID) }) {
            return item
        }
        return items.first { !$0.isComplete }
    }

    /// Animation identity for the stage surface — changes exactly when focus
    /// moves to another Set so the stage transition runs once per move.
    static func stageIdentity(in items: [SessionStageItem], focusID: ActiveSetID?) -> String {
        guard let focusID else {
            return stageItem(in: items, focusID: nil)?.id ?? "complete"
        }
        return "\(focusID.exerciseOrder)-\(focusID.setIndex)"
    }

    static func positionLabel(of item: SessionStageItem, in items: [SessionStageItem]) -> String {
        guard let index = items.firstIndex(where: { $0.id == item.id }) else { return "" }
        return "Exercise \(index + 1) of \(items.count)"
    }

    /// The next incomplete item after the stage item in Session order, wrapping
    /// around to earlier skipped-over items; never the stage item itself.
    static func upNextItem(
        after stageItem: SessionStageItem?,
        in items: [SessionStageItem]
    ) -> SessionStageItem? {
        guard let stageItem else { return nil }
        if let stageIndex = items.firstIndex(where: { $0.id == stageItem.id }),
            let next = items[items.index(after: stageIndex)...].first(where: { !$0.isComplete }) {
            return next
        }
        return items.first { !$0.isComplete && $0.id != stageItem.id }
    }

    /// The queue button label: completed items out of all items.
    static func queueProgressLabel(for items: [SessionStageItem]) -> String {
        "\(items.filter(\.isComplete).count) of \(items.count)"
    }

    /// The completion stage summary, e.g. "12 sets done across 4 exercises".
    static func completionSummary(for items: [SessionStageItem]) -> String {
        let setCount = items.reduce(0) { $0 + $1.completedSetCount }
        let exerciseCount = items.reduce(0) { $0 + $1.exercises.count }
        let sets = setCount == 1 ? "1 set" : "\(setCount) sets"
        let exercises = exerciseCount == 1 ? "1 exercise" : "\(exerciseCount) exercises"
        return "\(sets) done across \(exercises)"
    }

    /// The Set on stage: the coordinator's active Set, else the next pending one.
    static func stageSet(activeSetID: ActiveSetID?, in sortedSets: [ExerciseSet]) -> ExerciseSet? {
        if let set = set(matching: activeSetID, in: sortedSets) {
            return set
        }
        return sortedSets.first { $0.state == .pending }
    }

    static func set(matching id: ActiveSetID?, in sortedSets: [ExerciseSet]) -> ExerciseSet? {
        guard let id else { return nil }
        return sortedSets.first { SessionCoordinator.activeSetID(for: $0) == id }
    }

    static func ordinal(of set: ExerciseSet, in sortedSets: [ExerciseSet]) -> Int {
        (sortedSets.firstIndex { $0.persistentModelID == set.persistentModelID } ?? set.index) + 1
    }

    /// The pairing role of a queue row. Eligibility leans on the render
    /// config's pairing availability, which the coordinator keeps current
    /// while pairing is active.
    static func pairingRole(of item: SessionStageItem, mode: PairingMode) -> QueuePairingRole {
        switch mode {
        case .inactive:
            return .none
        case .selecting(let sourceOrder):
            return role(of: item, sourceOrder: sourceOrder, confirmingOrder: nil)
        case .confirming(let sourceOrder, let targetOrder):
            return role(of: item, sourceOrder: sourceOrder, confirmingOrder: targetOrder)
        }
    }

    private static func role(
        of item: SessionStageItem,
        sourceOrder: Int,
        confirmingOrder: Int?
    ) -> QueuePairingRole {
        guard let config = item.item.exerciseConfig else { return .ineligibleTarget }
        if config.exercise.order == confirmingOrder { return .confirmingTarget }
        if config.exercise.order == sourceOrder { return .source }
        return config.pairingAvailability == .available ? .eligibleTarget : .ineligibleTarget
    }
}
