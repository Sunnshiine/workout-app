import SwiftUI

struct RootView: View {
    var transcriber: (any SetTranscriber)?
    @Environment(SettingsStore.self) private var settings
    @Environment(WorkoutStore.self) private var workout
    @Environment(SyncCoordinator.self) private var sync
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var liveActivityAdapter = LiveActivityProductionAdapter()

    var body: some View {
        Group {
            #if DEBUG
                if UITestFixture.isEnabled, UITestFixture.launch.startsInDeveloperTools {
                    NavigationStack {
                        DeveloperToolsView()
                    }
                } else if UITestFixture.isEnabled, UITestFixture.launch.startsInSettings {
                    NavigationStack {
                        SettingsView()
                    }
                } else if settings.isConfigured {
                    sessionDestination
                } else {
                    onboardingDestination
                }
            #else
                if settings.isConfigured {
                    sessionDestination
                } else {
                    onboardingDestination
                }
            #endif
        }
        .environment(\.themePalette, palette)
        .environment(\.showsLoadBasis, settings.showsLoadBasis)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(palette.gradient.ignoresSafeArea())
        .preferredColorScheme(Theme.colorSchemeOverride(for: settings.appearance))
        .task(id: settings.isConfigured) {
            requestRestNotificationAuthorizationIfNeeded()
        }
        .onChange(of: scenePhase) { _, newPhase in
            guard newPhase == .active else { return }
            liveActivityAdapter.endIfReadyCapExpired()
        }
        .onChange(of: settings.spreadsheetId) { oldValue, newValue in
            guard oldValue != newValue else { return }
            liveActivityAdapter.end()
        }
        .onChange(of: settings.isSignedIn) { _, isSignedIn in
            guard !isSignedIn else { return }
            liveActivityAdapter.end()
        }
    }

    private var palette: Theme.Palette {
        Theme.palette(for: settings.appearance, colorScheme: colorScheme)
    }

    private var sessionDestination: some View {
        NavigationStack {
            SessionView(
                wiring: .live(
                    workout: workout,
                    sync: sync,
                    settings: settings,
                    platform: SessionPlatform(
                        liveActivity: liveActivityAdapter,
                        motion: SwiftUISessionMotion(),
                        restNotifications: RestNotificationCenterScheduler.shared
                    )
                ),
                transcriber: transcriber
            )
        }
        .transition(handoff)
    }

    private var onboardingDestination: some View {
        OnboardingView(isSignedIn: settings.isSignedIn)
            .transition(handoff)
    }

    // On the transitions, not an .animation(_:value:) on the Group, which would animate every
    // change under the Group in that transaction, not only the branch swap.
    private var handoff: AnyTransition {
        .opacity.animation(reduceMotion ? .easeInOut(duration: 0.2) : .smooth(duration: 0.35))
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
