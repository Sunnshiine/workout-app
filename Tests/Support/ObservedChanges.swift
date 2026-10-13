import Observation

@MainActor
final class ObservedChanges {
    private(set) var fired = 0

    func watch(_ read: @escaping @MainActor () -> Void) {
        withObservationTracking {
            read()
        } onChange: {
            MainActor.assumeIsolated { self.fired += 1 }
        }
    }
}
