import SwiftUI

struct RootView: View {
    let dictation: SetDictation?
    let focus: ActiveSetFocusManager
    let restTimer: RestTimer
    let countdown: EffortCountdown
    let liveActivityAdapter: LiveActivityProductionAdapter
    @Environment(SettingsStore.self) private var settings
    @Environment(WorkoutStore.self) private var workout
    @Environment(SyncCoordinator.self) private var sync
    @Environment(LastPerformedLookupStore.self) private var lastPerformed
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.scenePhase) private var scenePhase
    @Environment(AppEntryInbox.self) private var entry
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

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
        .onChange(of: scenePhase) { _, newPhase in
            guard newPhase == .background else { return }
            entry.discard()
        }
        .onChange(of: settings.needsOnboarding, initial: true) { _, needsOnboarding in
            entry.reportOnboarding(isShown: needsOnboarding)
        }
        .onChange(of: settings.spreadsheetId) { oldValue, newValue in
            guard oldValue != newValue else { return }
            liveActivityAdapter.end()
        }
        .onChange(of: settings.isSignedIn) { _, isSignedIn in
            guard !isSignedIn else { return }
            liveActivityAdapter.end()
        }
        // The athlete's hands are on the machine, so the screen stays lit while an Effort
        // Countdown runs. The root watches it, because a Session screen that goes away mid-count
        // ends the countdown as it leaves and would miss the end.
        .onChange(of: countdown.run != nil) { _, isCounting in
            UIApplication.shared.isIdleTimerDisabled = isCounting
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
                    lastPerformed: lastPerformed,
                    entry: entry,
                    platform: SessionPlatform(
                        liveActivity: liveActivityAdapter,
                        motion: SwiftUISessionMotion(),
                        restTimer: restTimer,
                        countdown: countdown
                    )
                ),
                dictation: dictation,
                focus: focus
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
