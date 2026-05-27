import Foundation
import Observation

@MainActor
protocol SessionLoggingAdapter {
    func log(_ set: ExerciseSet, as log: SetLog) throws
    func skip(_ set: ExerciseSet) throws
    func deleteLog(for set: ExerciseSet) throws
}

@MainActor
protocol SessionSyncAdapter {
    func reportLocalWriteFailure(_ error: any Error)
    func requestPendingWriteFlush()
}

@MainActor
protocol SessionTransitionClock {
    func sleep(for duration: Duration) async
}

enum SessionCoordinatorError: Error {
    case missingSession
    case missingLoggingAdapter
}

enum PairingMode: Equatable, Sendable {
    case inactive
    case selecting(sourceOrder: Int)
    case confirming(sourceOrder: Int, targetOrder: Int)
}

enum PairingTapResult: Equatable, Sendable {
    case ignored
    case cancelled
    case unavailable
    case confirming
}

extension WorkoutStore: SessionLoggingAdapter {}

struct SessionPendingWriteSyncAdapter: SessionSyncAdapter {
    let sync: SyncCoordinator
    let settings: SettingsStore

    func reportLocalWriteFailure(_ error: any Error) {
        sync.reportLocalWriteFailure(error)
    }

    func requestPendingWriteFlush() {
        guard let id = settings.spreadsheetId else { return }
        Task { await sync.flushPending(spreadsheetId: id) }
    }
}

private struct MissingSessionLoggingAdapter: SessionLoggingAdapter {
    func log(_ set: ExerciseSet, as log: SetLog) throws {
        throw SessionCoordinatorError.missingLoggingAdapter
    }

    func skip(_ set: ExerciseSet) throws {
        throw SessionCoordinatorError.missingLoggingAdapter
    }

    func deleteLog(for set: ExerciseSet) throws {
        throw SessionCoordinatorError.missingLoggingAdapter
    }
}

private struct NoopSessionSyncAdapter: SessionSyncAdapter {
    func reportLocalWriteFailure(_ error: any Error) {}
    func requestPendingWriteFlush() {}
}

private struct TaskSessionTransitionClock: SessionTransitionClock {
    func sleep(for duration: Duration) async {
        try? await Task.sleep(for: duration)
    }
}

enum ExercisePairingAvailability: Equatable, Sendable {
    case inactive
    case available
    case unavailable
}

struct SessionExerciseRenderConfig {
    let exercise: Exercise
    let activeSetID: ActiveSetID?
    let activeSetTransition: ActiveSetTransition?
    let retiringTransition: ActiveSetTransition?
    let isCollapsed: Bool
    let showsPairingGrip: Bool
    let pairingAvailability: ExercisePairingAvailability
    let isPairingConfirmation: Bool
    let lastPerformedPresentation: LastPerformedCardPresentation?
}

typealias SessionExerciseRenderItem = SessionExerciseRenderConfig

struct SessionSupersetRenderConfig {
    let presentation: ActiveSupersetPresentation
    let exercises: [Exercise]
    let activeSetTransition: ActiveSetTransition?
    let retiringTransition: ActiveSetTransition?
    let lastPerformedPresentation: LastPerformedCardPresentation?
}

struct SessionHiddenPairedExerciseRenderConfig {
    let exercise: Exercise
    let containerExerciseOrder: Int
}

private struct SessionRenderContext {
    let supersetByContainerOrder: [Int: SupersetSectionState]
    let containerOrderByPairedExerciseOrder: [Int: Int]
    let pairingSourceOrder: Int?
    let pairingConfirmationOrder: Int?
    let lastPerformedIndex: LastPerformedIndex?
}

enum SessionRenderItem {
    case exercise(SessionExerciseRenderConfig)
    case superset(SessionSupersetRenderConfig)
    case hiddenPairedExercise(SessionHiddenPairedExerciseRenderConfig)

    var id: String {
        switch self {
        case .exercise(let config):
            "exercise-\(config.exercise.order)"
        case .superset(let config):
            "superset-\(config.presentation.containerExerciseOrder ?? Int.min)"
        case .hiddenPairedExercise(let config):
            "hidden-paired-exercise-\(config.exercise.order)"
        }
    }

    var exerciseConfig: SessionExerciseRenderConfig? {
        guard case .exercise(let config) = self else { return nil }
        return config
    }
}

typealias SessionFocusAnimation = (() -> Void) -> Void

@MainActor
@Observable
final class SessionCoordinator {
    private(set) var session: Session?
    private(set) var activeSetID: ActiveSetID?
    private(set) var activeSetTransition: ActiveSetTransition?
    private(set) var retiringTransition: ActiveSetTransition?
    private(set) var scrollTargetID: ActiveSetID?
    private(set) var supersetScrollTargetOrder: Int?
    private(set) var pairingMode: PairingMode = .inactive

    @ObservationIgnored private let focusManager: ActiveSetFocusManager
    @ObservationIgnored private var loggingAdapter: any SessionLoggingAdapter
    @ObservationIgnored private var syncAdapter: any SessionSyncAdapter
    @ObservationIgnored private let transitionClock: any SessionTransitionClock
    @ObservationIgnored private var retirementTask: Task<Void, Never>?
    @ObservationIgnored private var pairingConfirmationTask: Task<Void, Never>?
    private var renderRevision = 0

    init(
        session: Session? = nil,
        logging: any SessionLoggingAdapter = MissingSessionLoggingAdapter(),
        sync: any SessionSyncAdapter = NoopSessionSyncAdapter(),
        transitionClock: any SessionTransitionClock = TaskSessionTransitionClock()
    ) {
        self.session = session
        self.focusManager = ActiveSetFocusManager(session: session)
        self.loggingAdapter = logging
        self.syncAdapter = sync
        self.transitionClock = transitionClock
        syncFocusState()
    }

    deinit {
        retirementTask?.cancel()
        pairingConfirmationTask?.cancel()
    }

    func configure(
        logging: any SessionLoggingAdapter,
        sync: any SessionSyncAdapter
    ) {
        loggingAdapter = logging
        syncAdapter = sync
    }

    func bind(to session: Session?) {
        self.session = session
        cancelPairing()
        clearRetiringTransition()
        focusManager.reset(to: session)
        syncFocusState()
        invalidateRenderItems()
    }

    func bind(
        to session: Session?,
        logging: any SessionLoggingAdapter,
        sync: any SessionSyncAdapter
    ) {
        configure(logging: logging, sync: sync)
        bind(to: session)
    }

    func advanceAfterLog(_ set: ExerciseSet, in session: Session) {
        focusManager.advanceAfterLog(set, in: session)
        syncFocusState()
        invalidateRenderItems()
    }

    func advanceAfterSkip(_ set: ExerciseSet, in session: Session) {
        focusManager.advanceAfterSkip(set, in: session)
        syncFocusState()
        invalidateRenderItems()
    }

    func focus(on set: ExerciseSet) {
        focusManager.focus(on: set)
        syncFocusState()
        invalidateRenderItems()
    }

    func log(_ set: ExerciseSet, as log: SetLog, animateFocus: SessionFocusAnimation? = nil) {
        do {
            let session = try actionSession(for: set)
            try loggingAdapter.log(set, as: log)
            performFocusUpdate(animateFocus) {
                advanceAfterLog(set, in: session)
            }
            retireActiveSetTransition()
            syncAdapter.requestPendingWriteFlush()
        } catch {
            syncAdapter.reportLocalWriteFailure(error)
        }
    }

    func skip(_ set: ExerciseSet, animateFocus: SessionFocusAnimation? = nil) {
        do {
            let session = try actionSession(for: set)
            try loggingAdapter.skip(set)
            performFocusUpdate(animateFocus) {
                advanceAfterSkip(set, in: session)
            }
            retireActiveSetTransition()
            syncAdapter.requestPendingWriteFlush()
        } catch {
            syncAdapter.reportLocalWriteFailure(error)
        }
    }

    func deleteLog(for set: ExerciseSet) {
        do {
            _ = try actionSession(for: set)
            try loggingAdapter.deleteLog(for: set)
            focus(on: set)
            clearRetiringTransition()
            syncAdapter.requestPendingWriteFlush()
        } catch {
            syncAdapter.reportLocalWriteFailure(error)
        }
    }

    func canPair(_ exercise: Exercise, in session: Session) -> Bool {
        focusManager.canPair(exercise, in: session)
    }

    @discardableResult
    func createSuperset(from source: Exercise, to target: Exercise, in session: Session) -> Bool {
        let created = focusManager.createSuperset(from: source, to: target, in: session)
        syncFocusState()
        invalidateRenderItems()
        return created
    }

    func dismissSuperset(containing exercise: Exercise, in session: Session) {
        cancelPairing()
        focusManager.dismissSuperset(containing: exercise, in: session)
        syncFocusState()
        invalidateRenderItems()
    }

    func supersetSections(in session: Session) -> [SupersetSectionState] {
        _ = renderRevision
        return focusManager.supersetSections(in: session)
    }

    @discardableResult
    func focusNextSupersetSet(for exercise: Exercise, in session: Session) -> Bool {
        let focused = focusManager.focusNextSupersetSet(for: exercise, in: session)
        syncFocusState()
        invalidateRenderItems()
        return focused
    }

    func clearTransition(_ transition: ActiveSetTransition) {
        focusManager.clearTransition(transition)
        syncFocusState()
        invalidateRenderItems()
    }

    func reexpand(_ exercise: Exercise) {
        focusManager.reexpand(exercise)
        invalidateRenderItems()
    }

    static func activeSetID(for set: ExerciseSet) -> ActiveSetID? {
        ActiveSetFocusManager.id(for: set)
    }

    private func syncFocusState() {
        activeSetID = focusManager.activeSetID
        activeSetTransition = focusManager.activeSetTransition
        scrollTargetID = focusManager.scrollTargetID
        supersetScrollTargetOrder = focusManager.supersetScrollTargetOrder
    }

    private func invalidateRenderItems() {
        renderRevision += 1
    }

    private func performFocusUpdate(
        _ animation: SessionFocusAnimation?,
        update: () -> Void
    ) {
        if let animation {
            animation(update)
        } else {
            update()
        }
    }

    private func actionSession(for set: ExerciseSet) throws -> Session {
        guard let session = set.exercise?.session else {
            throw SessionCoordinatorError.missingSession
        }

        if self.session !== session {
            bind(to: session)
        }

        return session
    }

    private func retireActiveSetTransition() {
        guard let transition = activeSetTransition else { return }

        retirementTask?.cancel()
        retiringTransition = transition
        let duration = transitionClearDuration(for: transition)
        let clock = transitionClock

        retirementTask = Task { @MainActor [weak self] in
            await clock.sleep(for: duration)
            guard
                !Task.isCancelled,
                let self,
                self.retiringTransition == transition
            else { return }

            self.retiringTransition = nil
            self.clearTransition(transition)
            self.retirementTask = nil
        }
    }

    private func clearRetiringTransition() {
        retirementTask?.cancel()
        retirementTask = nil
        retiringTransition = nil
    }

    private func transitionClearDuration(for transition: ActiveSetTransition) -> Duration {
        let seconds =
            switch transition.kind {
            case .momentumFlow:
                Theme.momentumFlowTotalDuration
            case .softFadeUp:
                Theme.skipFadeUpDuration
            case .collapseAndRise:
                Theme.momentumDropDuration
                    + Theme.exerciseCompletionBeatDuration
                    + Theme.momentumRiseDuration
            }
        return .nanoseconds(Int64((seconds * 1_000_000_000).rounded()))
    }
}

extension SessionCoordinator {
    func exerciseRenderItems() -> [SessionExerciseRenderItem] {
        guard let session else { return [] }
        return exerciseRenderItems(in: session)
    }

    func exerciseRenderItems(in session: Session) -> [SessionExerciseRenderItem] {
        renderItems(in: session).compactMap(\.exerciseConfig)
    }

    func renderItems(
        lastPerformedIndex: LastPerformedIndex? = nil
    ) -> [SessionRenderItem] {
        guard let session else { return [] }
        return renderItems(in: session, lastPerformedIndex: lastPerformedIndex)
    }

    func renderItems(
        in session: Session,
        lastPerformedIndex: LastPerformedIndex? = nil
    ) -> [SessionRenderItem] {
        let supersetSections = self.supersetSections(in: session)
        let context = SessionRenderContext(
            supersetByContainerOrder: Dictionary(
                uniqueKeysWithValues: supersetSections.compactMap { section in
                    section.presentation.containerExerciseOrder.map { ($0, section) }
                }
            ),
            containerOrderByPairedExerciseOrder: Dictionary(
                uniqueKeysWithValues: supersetSections.flatMap { section in
                    let containerOrder = section.presentation.containerExerciseOrder ?? Int.min
                    return section.exercises
                        .map(\.order)
                        .filter { $0 != containerOrder }
                        .map { ($0, containerOrder) }
                }
            ),
            pairingSourceOrder: pairingSourceOrder,
            pairingConfirmationOrder: pairingConfirmationOrder,
            lastPerformedIndex: lastPerformedIndex
        )

        return session.exercises
            .sorted { $0.order < $1.order }
            .map { exercise in
                renderItem(for: exercise, in: session, context: context)
            }
    }

    private func renderItem(
        for exercise: Exercise,
        in session: Session,
        context: SessionRenderContext
    ) -> SessionRenderItem {
        if let supersetSection = context.supersetByContainerOrder[exercise.order] {
            return .superset(
                supersetRenderConfig(
                    for: supersetSection,
                    lastPerformedIndex: context.lastPerformedIndex
                )
            )
        }

        if let containerExerciseOrder = context.containerOrderByPairedExerciseOrder[exercise.order] {
            return .hiddenPairedExercise(
                SessionHiddenPairedExerciseRenderConfig(
                    exercise: exercise,
                    containerExerciseOrder: containerExerciseOrder
                )
            )
        }

        return .exercise(exerciseRenderConfig(for: exercise, in: session, context: context))
    }

    private func supersetRenderConfig(
        for section: SupersetSectionState,
        lastPerformedIndex: LastPerformedIndex?
    ) -> SessionSupersetRenderConfig {
        let exerciseOrders = Set(section.exercises.map(\.order))
        let activeExercise = section.exercises.first {
            $0.order == section.presentation.activeExerciseOrder
        }

        return SessionSupersetRenderConfig(
            presentation: section.presentation,
            exercises: section.exercises,
            activeSetTransition: transition(activeSetTransition, scopedTo: exerciseOrders),
            retiringTransition: transition(retiringTransition, scopedTo: exerciseOrders),
            lastPerformedPresentation: lastPerformedPresentation(
                for: activeExercise,
                index: lastPerformedIndex
            )
        )
    }

    private func exerciseRenderConfig(
        for exercise: Exercise,
        in session: Session,
        context: SessionRenderContext
    ) -> SessionExerciseRenderConfig {
        SessionExerciseRenderConfig(
            exercise: exercise,
            activeSetID: activeSetID(scopedTo: exercise),
            activeSetTransition: transition(activeSetTransition, scopedTo: [exercise.order]),
            retiringTransition: transition(retiringTransition, scopedTo: [exercise.order]),
            isCollapsed: focusManager.isCollapsed(exercise),
            showsPairingGrip: context.pairingSourceOrder != nil,
            pairingAvailability: pairingAvailability(
                for: exercise,
                in: session,
                pairingSourceOrder: context.pairingSourceOrder
            ),
            isPairingConfirmation: context.pairingConfirmationOrder == exercise.order,
            lastPerformedPresentation: lastPerformedPresentation(
                for: exercise,
                index: context.lastPerformedIndex
            )
        )
    }

    private func pairingAvailability(
        for exercise: Exercise,
        in session: Session,
        pairingSourceOrder: Int?
    ) -> ExercisePairingAvailability {
        guard let pairingSourceOrder else { return .inactive }
        if exercise.order == pairingSourceOrder || canPair(exercise, in: session) {
            return .available
        }
        return .unavailable
    }

    private func activeSetID(scopedTo exercise: Exercise) -> ActiveSetID? {
        guard activeSetID?.exerciseOrder == exercise.order else { return nil }
        return activeSetID
    }

    private func transition(
        _ transition: ActiveSetTransition?,
        scopedTo exerciseOrders: Set<Int>
    ) -> ActiveSetTransition? {
        guard let transition else { return nil }
        if exerciseOrders.contains(transition.outgoingSetID.exerciseOrder) {
            return transition
        }
        if transition.incomingSetID.map({ exerciseOrders.contains($0.exerciseOrder) }) == true {
            return transition
        }
        if transition.completedExerciseOrder.map(exerciseOrders.contains) == true {
            return transition
        }
        return nil
    }

    private func lastPerformedPresentation(
        for exercise: Exercise?,
        index: LastPerformedIndex?
    ) -> LastPerformedCardPresentation? {
        guard let exercise, let index else { return nil }
        return LastPerformedCardPresentation(exercise: exercise, index: index)
    }
}

extension SessionCoordinator {
    @discardableResult
    func beginPairing(from exercise: Exercise, in session: Session) -> Bool {
        guard canPair(exercise, in: session) else { return false }
        pairingConfirmationTask?.cancel()
        pairingConfirmationTask = nil
        pairingMode = .selecting(sourceOrder: exercise.order)
        invalidateRenderItems()
        return true
    }

    func cancelPairing() {
        pairingConfirmationTask?.cancel()
        pairingConfirmationTask = nil
        guard pairingMode != .inactive else { return }
        pairingMode = .inactive
        invalidateRenderItems()
    }

    @discardableResult
    func handlePairingTap(on exercise: Exercise, in session: Session) -> PairingTapResult {
        guard let sourceOrder = pairingSourceOrder else {
            return .ignored
        }
        guard exercise.order != sourceOrder else {
            cancelPairing()
            return .cancelled
        }
        guard canPair(exercise, in: session) else {
            return .unavailable
        }
        guard case .selecting = pairingMode else {
            return .ignored
        }
        pairingMode = .confirming(sourceOrder: sourceOrder, targetOrder: exercise.order)
        invalidateRenderItems()
        confirmPairing(sourceOrder: sourceOrder, targetOrder: exercise.order, in: session)
        return .confirming
    }

    private var pairingSourceOrder: Int? {
        switch pairingMode {
        case .inactive:
            nil
        case .selecting(let sourceOrder), .confirming(let sourceOrder, _):
            sourceOrder
        }
    }

    private var pairingConfirmationOrder: Int? {
        switch pairingMode {
        case .inactive, .selecting:
            nil
        case .confirming(_, let targetOrder):
            targetOrder
        }
    }

    private func confirmPairing(sourceOrder: Int, targetOrder: Int, in session: Session) {
        pairingConfirmationTask?.cancel()
        let expectedMode = PairingMode.confirming(sourceOrder: sourceOrder, targetOrder: targetOrder)
        let clock = transitionClock
        let duration = pairingConfirmationDuration()

        pairingConfirmationTask = Task { @MainActor [weak self] in
            await clock.sleep(for: duration)
            guard
                !Task.isCancelled,
                let self,
                self.pairingMode == expectedMode
            else { return }

            guard
                let source = session.exercises.first(where: { $0.order == sourceOrder }),
                let target = session.exercises.first(where: { $0.order == targetOrder })
            else {
                self.cancelPairing()
                return
            }

            _ = self.createSuperset(from: source, to: target, in: session)
            self.pairingMode = .inactive
            self.pairingConfirmationTask = nil
            self.invalidateRenderItems()
        }
    }

    private func pairingConfirmationDuration() -> Duration {
        .nanoseconds(Int64((Theme.pairingConfirmationDuration * 1_000_000_000).rounded()))
    }
}
