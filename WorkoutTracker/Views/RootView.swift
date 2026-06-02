import SwiftUI

struct RootView: View {
    @Environment(SettingsStore.self) private var settings
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Group {
            #if DEBUG
                if UITestFixture.isEnabled, UITestFixture.startsInDeveloperTools {
                    NavigationStack {
                        DeveloperToolsView()
                    }
                } else if UITestFixture.isEnabled, UITestFixture.startsInSettings {
                    NavigationStack {
                        SettingsView()
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
        .environment(\.themePalette, palette)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(palette.gradient.ignoresSafeArea())
        .preferredColorScheme(Theme.colorSchemeOverride(for: settings.appearance))
        .task(id: settings.isConfigured) {
            requestRestNotificationAuthorizationIfNeeded()
        }
    }

    private var palette: Theme.Palette {
        Theme.palette(for: settings.appearance, colorScheme: colorScheme)
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

    private func requestRestNotificationAuthorizationIfNeeded() {
        guard settings.isConfigured else { return }
        #if DEBUG
            if UITestFixture.isEnabled { return }
        #endif
        #if canImport(UserNotifications)
            RestNotificationCenterScheduler.shared.requestAuthorizationIfNeeded()
        #endif
    }
}
