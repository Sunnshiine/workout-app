import SwiftUI

struct RootView: View {
    @Environment(SettingsStore.self) private var settings

    var body: some View {
        Group {
            if destination == .session {
                NavigationStack {
                    SessionView()
                }
            } else {
                OnboardingView()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.gradient.ignoresSafeArea())
        .preferredColorScheme(.dark)
    }

    private var destination: AppEntryDestination {
        AppEntryDestination(
            isSignedIn: settings.isSignedIn,
            hasSpreadsheet: settings.spreadsheetId != nil,
            showsURLFallback: false
        )
    }
}
