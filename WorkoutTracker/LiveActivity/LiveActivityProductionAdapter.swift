import Foundation

@MainActor
final class LiveActivityProductionAdapter: SessionLiveActivityAdapter {
    private let controller: LiveActivityController
    private var currentRestContent: LiveActivityRestContent?
    private var readyUpdateTask: Task<Void, Never>?
    private var capEndTask: Task<Void, Never>?

    init(controller: LiveActivityController = LiveActivityController()) {
        self.controller = controller
    }

    func startOrUpdate(restContent: LiveActivityRestContent, sessionLabel: String) {
        currentRestContent = restContent
        scheduleLifecycleTasks(for: restContent)
        let state = WorkoutActivityAttributes.ContentState(restContent: restContent)
        let staleDate = LiveActivityInvalidationPolicy.postRestCapEndDate(for: restContent)

        Task { @MainActor [controller] in
            controller.refreshAuthorizationStatus()
            if controller.isActive {
                await controller.update(state: state, staleDate: staleDate)
                if controller.isActive { return }
            }

            await controller.start(state: state, sessionLabel: sessionLabel, staleDate: staleDate)
        }
    }

    func end() {
        clearLifecycleTasks()
        currentRestContent = nil
        Task { @MainActor [controller] in
            await controller.end()
        }
    }

    func endIfInvalidated(displayedSession: Session?, currentSession: Session?) {
        guard let currentRestContent else { return }
        guard
            !LiveActivityInvalidationPolicy.shouldEnd(
                currentRestContent,
                displayedSession: displayedSession,
                currentSession: currentSession
            )
        else {
            end()
            return
        }
    }

    private func scheduleLifecycleTasks(for content: LiveActivityRestContent) {
        clearLifecycleTasks()
        readyUpdateTask = Task { @MainActor [weak self] in
            await Self.sleep(until: content.restEndDate)
            guard !Task.isCancelled, self?.currentRestContent == content else { return }
            await self?.controller.update(
                state: WorkoutActivityAttributes.ContentState(restContent: content),
                staleDate: LiveActivityInvalidationPolicy.postRestCapEndDate(for: content)
            )
        }
        capEndTask = Task { @MainActor [weak self] in
            await Self.sleep(until: LiveActivityInvalidationPolicy.postRestCapEndDate(for: content))
            guard !Task.isCancelled, self?.currentRestContent == content else { return }
            self?.end()
        }
    }

    private func clearLifecycleTasks() {
        readyUpdateTask?.cancel()
        readyUpdateTask = nil
        capEndTask?.cancel()
        capEndTask = nil
    }

    private static func sleep(until date: Date) async {
        let seconds = max(date.timeIntervalSinceNow, 0)
        try? await Task.sleep(for: .seconds(seconds))
    }
}
