import SwiftUI

struct RootView: View {
    @Environment(SettingsStore.self) private var settings

    var body: some View {
        if settings.isConfigured {
            SessionView()
        } else {
            OnboardingView()
        }
    }
}
