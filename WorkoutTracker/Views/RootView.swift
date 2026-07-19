import SwiftUI

struct RootView: View {
    @Environment(SettingsStore.self) private var settings
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.scenePhase) private var scenePhase
    @State private var liveActivityAdapter = LiveActivityProductionAdapter()

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
        .background(palette.paperBackground.ignoresSafeArea())
        .preferredColorScheme(Theme.colorSchemeOverride(for: settings.appearance))
        .task(id: settings.isConfigured) {
            requestRestNotificationAuthorizationIfNeeded()
        }
        .onChange(of: scenePhase) { _, newPhase in
            guard newPhase == .active else { return }
            liveActivityAdapter.endIfReadyCapExpired()
        }
        .onChange(of: settings.spreadsheetId) { oldValue, newValue in
            guard oldValue != newValue, LiveActivityInvalidationPolicy.shouldEnd(for: .sheetSwitch) else { return }
            liveActivityAdapter.end()
        }
        .onChange(of: settings.isSignedIn) { _, isSignedIn in
            guard !isSignedIn, LiveActivityInvalidationPolicy.shouldEnd(for: .signOut) else { return }
            liveActivityAdapter.end()
        }
    }

    private var palette: Theme.Palette {
        Theme.palette(for: settings.appearance, colorScheme: colorScheme)
    }

    private var sessionDestination: some View {
        NavigationStack {
            SessionView(liveActivityAdapter: liveActivityAdapter)
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
