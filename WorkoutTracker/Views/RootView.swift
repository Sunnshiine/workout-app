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
}
