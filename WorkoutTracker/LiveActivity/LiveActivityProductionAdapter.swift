import Foundation

@MainActor
final class LiveActivityProductionAdapter: SessionLiveActivityAdapter {
    private let controller: LiveActivityController

    init(controller: LiveActivityController = LiveActivityController()) {
        self.controller = controller
    }

    func startOrUpdate(restContent: LiveActivityRestContent, sessionLabel: String) {
        let state = WorkoutActivityAttributes.ContentState(restContent: restContent)

        Task { @MainActor [controller] in
            controller.refreshAuthorizationStatus()
            if controller.isActive {
                await controller.update(state: state)
                if controller.isActive { return }
            }

            await controller.start(state: state, sessionLabel: sessionLabel)
        }
    }
}
