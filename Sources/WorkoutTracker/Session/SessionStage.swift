import Foundation

/// What the Session stage shows, decided once per render by `SessionCoordinator.stage(in:lookup:)`.
/// Views switch on it and lay it out; they never pick an item, a Set, a side, or a gate.
struct SessionStage: Equatable {
    enum Focus: Equatable {
        case exercise(ExerciseStage)
        case superset(SupersetStage)
        case complete(CompletionStage)
    }

    let focus: Focus
    /// The next incomplete item after the one on stage, wrapping; nil on the completion stage.
    let upNext: UpNext?
    let queue: SessionQueue
}

struct UpNext: Equatable {
    let title: String
    /// The item's first Pending Set, which a tap brings on stage.
    let target: ExerciseSet?
}

/// The focus manager's state a stage is built from, as one value.
struct SessionFocusSnapshot: Equatable {
    let activeSetID: ActiveSetID?
    let expandedLoggedSetID: ActiveSetID?
    /// Live Supersets, each as its two Exercises in the order they were paired.
    let supersets: [[Exercise]]
    /// Orders of the Exercises that could start or join a Superset now.
    let pairableExerciseOrders: Set<Int>
}

/// Move On and the Open Exercises makeup queue exist only at the live edge.
enum LiveEdgeContext: Equatable {
    case atLiveEdge(canMoveOn: Bool, openExercises: [Exercise])
    case browsedAway

    var showsMoveOn: Bool {
        switch self {
        case .atLiveEdge(let canMoveOn, _): canMoveOn
        case .browsedAway: false
        }
    }

    var openExercises: [Exercise] {
        switch self {
        case .atLiveEdge(_, let openExercises): openExercises
        case .browsedAway: []
        }
    }
}

/// A node on the living stage's branch. Each state derives from Set State plus which Set is on
/// stage, so the branch stays textless.
enum BranchNodeState: Equatable, Sendable {
    /// A Logged Set: an inked leaf.
    case leaf
    /// A Skipped Set: a dashed-outline leaf.
    case dashedLeaf
    /// The active Set: a cream-filled leaf inside a green stroke.
    case bud
    /// A Pending Set still ahead: a faint ghost outline.
    case future
}

struct BranchNode: Equatable {
    let set: ExerciseSet
    let state: BranchNodeState
}

struct StageBranch: Equatable {
    let nodes: [BranchNode]
    /// The Active Set when it belongs to this branch; the branch animates its leaves on it.
    let activeSetID: ActiveSetID?
}

/// The one Active Set Card on stage. `id` keys `holdsStill(acrossChangesOf:)`, so a change of Set
/// or mode never animates the card's frame.
struct SetCardSlot: Equatable {
    enum Mode: Equatable {
        case logging
        case reviewingLogged(showsSavedConfirmation: Bool)
    }

    let set: ExerciseSet
    let ordinal: Int
    let count: Int
    let mode: Mode
    let id: String
}

struct ExerciseStage: Equatable {
    let exercise: Exercise
    let branch: StageBranch
    let card: SetCardSlot?
    let lastPerformed: LastPerformedCardPresentation?
}

struct SupersetStage: Equatable {
    /// The side holding the Active Set, else the lower-ordered side.
    let focused: Exercise
    let partner: Exercise
    let branch: StageBranch
    /// Bud-less: the bud rides the focus (DESIGN.md §5.4).
    let partnerNodes: [BranchNode]
    let card: SetCardSlot?
    /// Only while the Active Set is in this Superset.
    let lastPerformed: LastPerformedCardPresentation?
}

struct CompletionStage: Equatable {
    let summary: String
    let openExercises: [Exercise]
    let showsMoveOn: Bool
}

struct QueuePosition: Equatable, Sendable {
    let number: Int
    let count: Int

    var label: String { "\(number) of \(count)" }
    var accessibilityLabel: String { "Queue, \(number) of \(count)" }
}

/// The part a queue row plays while Superset pairing is in flight.
enum QueuePairingRole: Equatable, Sendable {
    case none
    case source
    case eligibleTarget
    case ineligibleTarget
    case confirmingTarget
}

struct SessionQueue: Equatable {
    struct Row: Equatable, Identifiable {
        /// `exercise-<order>` or `superset-<order>`; UI tests key `stage-queue-row-<id>` on it.
        let id: String
        let title: String
        /// The item's Sets in Exercise order then Set order, for the dots.
        let sets: [ExerciseSet]
        let isComplete: Bool
        let isOnStage: Bool
        /// The Exercise the pairing verbs take: the single Exercise, or the Superset's first side.
        let exercise: Exercise
        /// The item's first Pending Set, which a tap brings on stage.
        let jumpTarget: ExerciseSet?
        let canBeginPairing: Bool
        let pairingRole: QueuePairingRole
    }

    let rows: [Row]
    /// The stage item's place in the queue; the last place once the Session is complete.
    let position: QueuePosition
    let pairingMode: PairingMode
    let showsMoveOn: Bool
    let openExercises: [Exercise]

    var isPairing: Bool { pairingMode != .inactive }
}

enum SessionStageComposition: Equatable, Sendable {
    case reading
    case editingWeight

    init(isEditingWeight: Bool) {
        self = isEditingWeight ? .editingWeight : .reading
    }
}

@MainActor
extension SessionStage {
    init(
        session: Session,
        focus: SessionFocusSnapshot,
        savedLoggedSetID: ActiveSetID?,
        pairingMode: PairingMode,
        liveEdge: LiveEdgeContext,
        lookup: LastPerformedLookupSnapshot
    ) {
        let items = StageItem.items(in: session, supersets: focus.supersets)
        let onStage = StageItem.onStage(in: items, focusID: focus.expandedLoggedSetID ?? focus.activeSetID)
        upNext = onStage.flatMap { StageItem.upNext(after: $0, in: items) }
        queue = SessionQueue(items: items, onStage: onStage, snapshot: focus, pairingMode: pairingMode, liveEdge: liveEdge)
        guard let onStage else {
            self.focus = .complete(CompletionStage(items: items, liveEdge: liveEdge))
            return
        }
        self.focus = onStage.focus(snapshot: focus, savedLoggedSetID: savedLoggedSetID, lookup: lookup)
    }
}

@MainActor
extension SessionFocusSnapshot {
    /// The Active Set while no Logged Set is open for review.
    fileprivate var visualActiveSetID: ActiveSetID? {
        expandedLoggedSetID == nil ? activeSetID : nil
    }
}

@MainActor
extension ExerciseStage {
    fileprivate init(
        _ exercise: Exercise,
        snapshot: SessionFocusSnapshot,
        savedLoggedSetID: ActiveSetID?,
        lookup: LastPerformedLookupSnapshot
    ) {
        let sets = exercise.sortedSets
        let activeSetID = snapshot.visualActiveSetID.scoped(to: [exercise])
        self.exercise = exercise
        branch = StageBranch(sets: sets, activeSetID: activeSetID)
        card = SetCardSlot.exerciseCard(
            in: sets,
            exerciseOrder: exercise.order,
            activeSetID: activeSetID,
            reviewedSetID: snapshot.expandedLoggedSetID.scoped(to: [exercise]),
            savedLoggedSetID: savedLoggedSetID
        )
        lastPerformed = LastPerformedCardPresentation(exercise: exercise, lookup: lookup)
    }
}

@MainActor
extension SupersetStage {
    fileprivate init(_ exercises: [Exercise], snapshot: SessionFocusSnapshot, lookup: LastPerformedLookupSnapshot) {
        let activeSetID = snapshot.visualActiveSetID.scoped(to: exercises)
        let lowerFirst = exercises.sorted { $0.order < $1.order }
        let focused = lowerFirst.first { $0.order == activeSetID?.exerciseOrder } ?? lowerFirst[0]
        let partner = exercises.first { $0.order != focused.order } ?? focused
        let sets = focused.sortedSets
        self.focused = focused
        self.partner = partner
        branch = StageBranch(sets: sets, activeSetID: activeSetID)
        partnerNodes = StageBranch(sets: partner.sortedSets, activeSetID: nil).nodes.map { node in
            BranchNode(set: node.set, state: node.state == .bud ? .future : node.state)
        }
        card = SetCardSlot.supersetCard(in: sets, focused: focused, activeSetID: activeSetID)
        lastPerformed = activeSetID == nil ? nil : LastPerformedCardPresentation(exercise: focused, lookup: lookup)
    }
}

@MainActor
extension CompletionStage {
    fileprivate init(items: [StageItem], liveEdge: LiveEdgeContext) {
        let setCount = items.reduce(0) { $0 + $1.exercises.completedSetCount }
        let exerciseCount = items.reduce(0) { $0 + $1.exercises.count }
        let sets = setCount == 1 ? "1 set" : "\(setCount) sets"
        let exercises = exerciseCount == 1 ? "1 exercise" : "\(exerciseCount) exercises"
        summary = "\(sets) done across \(exercises)"
        openExercises = liveEdge.openExercises
        showsMoveOn = liveEdge.showsMoveOn
    }
}

@MainActor
extension StageBranch {
    /// One leaf per Logged Set, a dashed leaf per Skipped Set, the bud on the Active Set when it is
    /// Pending (else the first Pending Set), and ghost outlines for the rest.
    fileprivate init(sets: [ExerciseSet], activeSetID: ActiveSetID?) {
        let bud = Self.budSet(in: sets, activeSetID: activeSetID)
        nodes = sets.map { BranchNode(set: $0, state: BranchNodeState(of: $0, bud: bud)) }
        self.activeSetID = activeSetID
    }

    private static func budSet(in sets: [ExerciseSet], activeSetID: ActiveSetID?) -> ExerciseSet? {
        if let active = sets.first(matching: activeSetID), active.isPending {
            return active
        }
        return sets.first(where: \.isPending)
    }
}

@MainActor
extension BranchNodeState {
    fileprivate init(of set: ExerciseSet, bud: ExerciseSet?) {
        switch set.state {
        case .logged: self = .leaf
        case .skipped: self = .dashedLeaf
        case .pending: self = set === bud ? .bud : .future
        }
    }
}

@MainActor
extension SetCardSlot {
    /// The Logged Set open for review, else the Active Set, else the first Pending Set.
    fileprivate static func exerciseCard(
        in sets: [ExerciseSet],
        exerciseOrder: Int,
        activeSetID: ActiveSetID?,
        reviewedSetID: ActiveSetID?,
        savedLoggedSetID: ActiveSetID?
    ) -> SetCardSlot? {
        if let reviewed = sets.first(matching: reviewedSetID) {
            return SetCardSlot(
                reviewed,
                in: sets,
                mode: .reviewingLogged(showsSavedConfirmation: reviewedSetID == savedLoggedSetID),
                id: "stage-review-\(exerciseOrder)-\(reviewed.index)"
            )
        }
        guard let set = sets.first(matching: activeSetID) ?? sets.first(where: \.isPending) else { return nil }
        return SetCardSlot(set, in: sets, mode: .logging, id: "stage-active-\(exerciseOrder)-\(set.index)")
    }

    /// The Active Set in whatever state it is in, else the focused side's next Pending Set.
    fileprivate static func supersetCard(
        in sets: [ExerciseSet],
        focused: Exercise,
        activeSetID: ActiveSetID?
    ) -> SetCardSlot? {
        let set: ExerciseSet? =
            if let activeSetID {
                sets.first { $0.index == activeSetID.setIndex }
            } else {
                SupersetState.nextPendingSet(for: focused)
            }
        guard let set else { return nil }
        return SetCardSlot(set, in: sets, mode: .logging, id: "superset-active-\(focused.order)-\(set.index)")
    }

    private init(_ set: ExerciseSet, in sets: [ExerciseSet], mode: Mode, id: String) {
        self.set = set
        ordinal = (sets.firstIndex { $0 === set } ?? set.index) + 1
        count = sets.count
        self.mode = mode
        self.id = id
    }
}

@MainActor
extension SessionQueue {
    fileprivate init(
        items: [StageItem],
        onStage: StageItem?,
        snapshot: SessionFocusSnapshot,
        pairingMode: PairingMode,
        liveEdge: LiveEdgeContext
    ) {
        rows = items.map { item in
            item.row(
                isOnStage: item.id == onStage?.id,
                pairable: snapshot.pairableExerciseOrders,
                pairingMode: pairingMode
            )
        }
        let onStageIndex = items.firstIndex { $0.id == onStage?.id }
        position = QueuePosition(number: onStageIndex.map { $0 + 1 } ?? items.count, count: items.count)
        self.pairingMode = pairingMode
        showsMoveOn = liveEdge.showsMoveOn
        openExercises = liveEdge.openExercises
    }
}

/// One stage item: a single Exercise, or a live Superset fused at its lower-ordered side.
@MainActor
private struct StageItem {
    enum Kind {
        case exercise(Exercise)
        /// The Superset's Exercises in the order they were paired.
        case superset([Exercise])
    }

    let kind: Kind

    static func items(in session: Session, supersets: [[Exercise]]) -> [StageItem] {
        session.exercises
            .sorted { $0.order < $1.order }
            .compactMap { exercise in
                guard let superset = supersets.first(where: { $0.contains { $0.order == exercise.order } }) else {
                    return StageItem(kind: .exercise(exercise))
                }
                return exercise.order == superset.map(\.order).min() ? StageItem(kind: .superset(superset)) : nil
            }
    }

    /// The item holding focus, else the first incomplete one; nil once the Session is complete.
    static func onStage(in items: [StageItem], focusID: ActiveSetID?) -> StageItem? {
        items.first { $0.contains(focusID) } ?? items.first { !$0.isComplete }
    }

    /// The next incomplete item after `onStage`, wrapping around to earlier ones; never `onStage`.
    static func upNext(after onStage: StageItem, in items: [StageItem]) -> UpNext? {
        let next: StageItem?
        if let index = items.firstIndex(where: { $0.id == onStage.id }),
            let after = items[items.index(after: index)...].first(where: { !$0.isComplete }) {
            next = after
        } else {
            next = items.first { !$0.isComplete && $0.id != onStage.id }
        }
        return next.map { UpNext(title: $0.title, target: $0.nextPendingSet) }
    }

    func focus(
        snapshot: SessionFocusSnapshot,
        savedLoggedSetID: ActiveSetID?,
        lookup: LastPerformedLookupSnapshot
    ) -> SessionStage.Focus {
        switch kind {
        case .exercise(let exercise):
            .exercise(ExerciseStage(exercise, snapshot: snapshot, savedLoggedSetID: savedLoggedSetID, lookup: lookup))
        case .superset(let exercises):
            .superset(SupersetStage(exercises, snapshot: snapshot, lookup: lookup))
        }
    }

    var exercises: [Exercise] {
        switch kind {
        case .exercise(let exercise): [exercise]
        case .superset(let exercises): exercises
        }
    }

    var id: String {
        switch kind {
        case .exercise(let exercise): "exercise-\(exercise.order)"
        case .superset(let exercises): "superset-\(exercises.map(\.order).min() ?? Int.min)"
        }
    }

    var title: String {
        exercises.map(\.baseName).joined(separator: " + ")
    }

    var isComplete: Bool { exercises.allSetsComplete }

    var nextPendingSet: ExerciseSet? { SessionSetOrder.firstPendingSet(in: exercises)?.set }

    func contains(_ setID: ActiveSetID?) -> Bool {
        guard let setID else { return false }
        return exercises.contains { $0.order == setID.exerciseOrder }
    }

    func row(isOnStage: Bool, pairable: Set<Int>, pairingMode: PairingMode) -> SessionQueue.Row {
        let exercise = exercises[0]
        return SessionQueue.Row(
            id: id,
            title: title,
            sets: SessionSetOrder.orderedSets(in: exercises).map(\.set),
            isComplete: isComplete,
            isOnStage: isOnStage,
            exercise: exercise,
            jumpTarget: nextPendingSet,
            canBeginPairing: exercises.count == 1 && pairable.contains(exercise.order),
            pairingRole: pairingRole(mode: pairingMode, pairable: pairable)
        )
    }

    private func pairingRole(mode: PairingMode, pairable: Set<Int>) -> QueuePairingRole {
        switch mode {
        case .inactive:
            .none
        case .selecting(let sourceOrder):
            pairingRole(sourceOrder: sourceOrder, confirmingOrder: nil, pairable: pairable)
        case .confirming(let sourceOrder, let targetOrder):
            pairingRole(sourceOrder: sourceOrder, confirmingOrder: targetOrder, pairable: pairable)
        }
    }

    private func pairingRole(sourceOrder: Int, confirmingOrder: Int?, pairable: Set<Int>) -> QueuePairingRole {
        guard case .exercise(let exercise) = kind else { return .ineligibleTarget }
        if exercise.order == confirmingOrder { return .confirmingTarget }
        if exercise.order == sourceOrder { return .source }
        return pairable.contains(exercise.order) ? .eligibleTarget : .ineligibleTarget
    }
}

@MainActor
extension Exercise {
    fileprivate var sortedSets: [ExerciseSet] {
        sets.sorted { $0.index < $1.index }
    }
}

@MainActor
extension [ExerciseSet] {
    fileprivate func first(matching id: ActiveSetID?) -> ExerciseSet? {
        guard let id else { return nil }
        return first { ActiveSetFocusManager.id(for: $0) == id }
    }
}

extension ActiveSetID? {
    /// The id when it names a Set of one of `exercises`.
    fileprivate func scoped(to exercises: [Exercise]) -> ActiveSetID? {
        flatMap { id in exercises.contains { $0.order == id.exerciseOrder } ? id : nil }
    }
}
