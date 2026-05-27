import Foundation
import Observation

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

@MainActor
@Observable
final class SessionCoordinator {
    private(set) var session: Session?
    private(set) var activeSetID: ActiveSetID?
    private(set) var activeSetTransition: ActiveSetTransition?
    private(set) var scrollTargetID: ActiveSetID?
    private(set) var supersetScrollTargetOrder: Int?

    @ObservationIgnored private let focusManager: ActiveSetFocusManager
    private var renderRevision = 0

    init(session: Session? = nil) {
        self.session = session
        self.focusManager = ActiveSetFocusManager(session: session)
        syncFocusState()
    }

    func bind(to session: Session?) {
        self.session = session
        focusManager.reset(to: session)
        syncFocusState()
        invalidateRenderItems()
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
}
