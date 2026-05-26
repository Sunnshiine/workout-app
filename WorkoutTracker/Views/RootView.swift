import SwiftUI

struct RootView: View {
    @Environment(SettingsStore.self) private var settings

    var body: some View {
        Group {
            if settings.isConfigured {
                SessionView()
            } else {
                OnboardingView()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.gradient.ignoresSafeArea())
        .preferredColorScheme(.dark)
    }
}
