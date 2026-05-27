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

struct SessionExerciseRenderItem {
    let exercise: Exercise
    let activeSetID: ActiveSetID?
    let activeSetTransition: ActiveSetTransition?
    let isCollapsed: Bool
    let showsPairingGrip: Bool
    let pairingAvailability: ExercisePairingAvailability
    let isPairingConfirmation: Bool
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

    @ObservationIgnored private let focusManager: ActiveSetFocusManager
    @ObservationIgnored private var loggingAdapter: any SessionLoggingAdapter
    @ObservationIgnored private var syncAdapter: any SessionSyncAdapter
    @ObservationIgnored private let transitionClock: any SessionTransitionClock
    @ObservationIgnored private var retirementTask: Task<Void, Never>?
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

    func exerciseRenderItems(
        pairingSourceOrder: Int? = nil,
        pairingConfirmationOrder: Int? = nil
    ) -> [SessionExerciseRenderItem] {
        guard let session else { return [] }
        return exerciseRenderItems(
            in: session,
            pairingSourceOrder: pairingSourceOrder,
            pairingConfirmationOrder: pairingConfirmationOrder
        )
    }

    func exerciseRenderItems(
        in session: Session,
        pairingSourceOrder: Int? = nil,
        pairingConfirmationOrder: Int? = nil
    ) -> [SessionExerciseRenderItem] {
        _ = renderRevision
        let activeSupersetExerciseOrders = Set(
            supersetSections(in: session).flatMap { section in
                section.exercises.map(\.order)
            }
        )

        return session.exercises
            .sorted { $0.order < $1.order }
            .filter { !activeSupersetExerciseOrders.contains($0.order) }
            .map { exercise in
                SessionExerciseRenderItem(
                    exercise: exercise,
                    activeSetID: activeSetID,
                    activeSetTransition: activeSetTransition,
                    isCollapsed: focusManager.isCollapsed(exercise),
                    showsPairingGrip: pairingSourceOrder != nil,
                    pairingAvailability: pairingAvailability(
                        for: exercise,
                        in: session,
                        pairingSourceOrder: pairingSourceOrder
                    ),
                    isPairingConfirmation: pairingConfirmationOrder == exercise.order
                )
            }
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
