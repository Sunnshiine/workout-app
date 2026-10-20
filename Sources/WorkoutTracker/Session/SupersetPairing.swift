import Foundation
import Observation

enum PairingMode: Equatable, Sendable {
    case inactive
    case selecting(sourceOrder: Int)
    case confirming(sourceOrder: Int, targetOrder: Int)

    var sourceOrder: Int? {
        switch self {
        case .inactive: nil
        case .selecting(let sourceOrder), .confirming(let sourceOrder, _): sourceOrder
        }
    }
}

enum PairingTapResult: Equatable, Sendable {
    case ignored
    case cancelled
    case unavailable
    case confirming
}

/// The queue sheet's Superset pairing: pick a source Exercise, tap its partner, and after a short
/// confirmation the two fuse into one Superset.
@MainActor
@Observable
final class SupersetPairing {
    private(set) var mode: PairingMode = .inactive

    @ObservationIgnored private let focusManager: ActiveSetFocusManager
    @ObservationIgnored private let clock: any SessionTransitionClock
    @ObservationIgnored private var confirmationTask: Task<Void, Never>?

    init(focusManager: ActiveSetFocusManager, clock: any SessionTransitionClock) {
        self.focusManager = focusManager
        self.clock = clock
    }

    deinit {
        confirmationTask?.cancel()
    }

    func begin(from exercise: Exercise, in session: Session) -> Bool {
        guard focusManager.canPair(exercise, in: session) else { return false }
        confirmationTask?.cancel()
        confirmationTask = nil
        mode = .selecting(sourceOrder: exercise.order)
        return true
    }

    func cancel() {
        confirmationTask?.cancel()
        confirmationTask = nil
        guard mode != .inactive else { return }
        mode = .inactive
    }

    func handleTap(on exercise: Exercise, in session: Session) -> PairingTapResult {
        guard let sourceOrder = mode.sourceOrder else {
            return .ignored
        }
        guard exercise.order != sourceOrder else {
            cancel()
            return .cancelled
        }
        guard focusManager.canPair(exercise, in: session) else {
            return .unavailable
        }
        guard case .selecting = mode else {
            return .ignored
        }
        mode = .confirming(sourceOrder: sourceOrder, targetOrder: exercise.order)
        confirm(sourceOrder: sourceOrder, targetOrder: exercise.order, in: session)
        return .confirming
    }

    private func confirm(sourceOrder: Int, targetOrder: Int, in session: Session) {
        confirmationTask?.cancel()
        let expectedMode = PairingMode.confirming(sourceOrder: sourceOrder, targetOrder: targetOrder)
        let clock = clock
        let duration = Self.confirmationDuration()

        confirmationTask = Task { @MainActor [weak self] in
            await clock.sleep(for: duration)
            guard
                !Task.isCancelled,
                let self,
                self.mode == expectedMode
            else { return }

            guard
                let source = session.exercises.first(where: { $0.order == sourceOrder }),
                let target = session.exercises.first(where: { $0.order == targetOrder })
            else {
                self.cancel()
                return
            }

            _ = self.focusManager.createSuperset(from: source, to: target, in: session)
            self.mode = .inactive
            self.confirmationTask = nil
        }
    }

    private static func confirmationDuration() -> Duration {
        .nanoseconds(Int64((Theme.pairingConfirmationDuration * 1_000_000_000).rounded()))
    }
}
