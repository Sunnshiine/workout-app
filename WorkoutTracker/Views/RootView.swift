import SwiftUI

struct RootView: View {
    @Environment(SettingsStore.self) private var settings

    var body: some View {
        Group {
            #if DEBUG
                if UITestFixture.isEnabled, UITestFixture.startsInDeveloperTools {
                    NavigationStack {
                        DeveloperToolsView()
                    }
                } else if destination == .session {
                    sessionDestination
                } else {
                    OnboardingView()
                }
            #else
                if destination == .session {
                    sessionDestination
                } else {
                    OnboardingView()
                }
            #endif
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.gradient.ignoresSafeArea())
        .preferredColorScheme(.dark)
    }

    private var sessionDestination: some View {
        NavigationStack {
            SessionView()
        }
    }

    private var destination: AppEntryDestination {
        AppEntryDestination(
            isSignedIn: settings.isSignedIn,
            hasSpreadsheet: settings.spreadsheetId != nil,
            showsURLFallback: false
        )
    }
}
