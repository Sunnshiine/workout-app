import Foundation
import SnapshotTesting
import SwiftUI
import Testing

@testable import WorkoutTracker

/// Wholesale Day/Night Visual Baselines for the redesigned Greenhouse screens (PRD #458 slice 8,
/// ADR-0007). Liquid Glass is retired (ADR-0014): the harness composites glass as transparent and no
/// redesigned screen bears a glass primitive any longer, so `sunbirdColophonMatchesVisualBaseline`
/// below is the **only** glass-bearing baseline left — the app's one surviving glass disc
/// (DESIGN.md §6). Every other capture here is flat Greenhouse paper, re-lit for Night.
@MainActor
@Suite(.snapshots(record: .never))
struct GlassBearingViewsVisualTests {
    // MARK: - The one surviving glass element

    @Test func sunbirdColophonMatchesVisualBaseline() {
        // The complete Sunbird mark (DESIGN.md §6): its icon greens hold across both appearances
        // (The Mark Stays Whole), so it is captured against the Day and Night paper it sits on. This
        // is the single glass-bearing baseline in the entire Visual suite.
        assertGreenhouseBaselines { _ in
            SunbirdColophon(diameter: 40)
        }
    }

    // MARK: - Block grid (flagged Night surface)

    @Test func sessionTileMatchesVisualBaseline() {
        // The Block grid is the second surface never re-prototyped at Night; its Night baseline is
        // validated on the pinned iPhone 17 Pro against the Room Re-lights Rule before it locks
        // (PRD #458 slice 8, DESIGN.md §2 / §5.5). The tile is wordless — fill + stroke alone say
        // state; `Tests/Component/ThemeTests.swift` (`nightBlockGridObeysTheRoomRelightsRule`) is the
        // programmatic half of that sign-off.
        assertGreenhouseBaselines { _ in
            SessionTile(state: .current, fillQuarters: 0)
                .frame(width: 160)
        }
    }

    // MARK: - The living stage & input block

    @Test func smartValuePillsMatchesVisualBaseline() {
        let set = makeExercise(setStates: [.pending]).sets[0]

        assertGreenhouseBaselines(precision: WorkoutVisualBaseline.labelAntialiasingPrecision) { _ in
            SmartValuePills(
                set: set,
                previousSetWeight: 275,
                trainingMax: 405,
                onLog: { _ in },
                onSkip: {},
                onDelete: {}
            )
            .frame(width: 360)
        }
    }

    @Test func smartValuePillsWithVisibleWeightSteppersMatchesVisualBaseline() {
        let set = ExerciseSet(
            index: 0,
            prescribedReps: "5",
            prescribedLoad: "70%1RM",
            percentOneRM: "70%",
            state: .pending
        )

        assertGreenhouseBaselines { _ in
            SmartValuePills(
                set: set,
                previousSetWeight: nil,
                trainingMax: 405,
                onLog: { _ in },
                onSkip: {},
                onDelete: {}
            )
            .frame(width: 360)
        }
    }

    @Test func sessionProgressHeaderMatchesVisualBaseline() {
        let session = makeSession(
            weekNumber: 3,
            dayNumber: 2,
            setStates: [.logged, .logged, .pending, .pending],
            exerciseName: "Bench Press"
        )
        let block = makeBlock(sessions: [session])

        // No glass: the header carries its own flat card fill now (ADR-0014). Only the colophon
        // renders through the glass primitive anywhere in the suite.
        assertGreenhouseBaselines { appearance in
            SessionProgressHeader(
                session: session,
                activeSetID: ActiveSetID(exerciseOrder: 0, setIndex: 2),
                block: block,
                currentSession: session,
                sessionSettingsOverpullState: .pinned
            )
            .padding(14)
            .frame(width: 360)
            .background(Theme.palette(for: appearance).activeCardFill, in: .rect(cornerRadius: Theme.cardCornerRadius))
        }
    }

    @Test func restPillViewMatchesVisualBaseline() {
        let now = Date(timeIntervalSinceReferenceDate: 1_000)
        let clock = VisualRestClock(now: now)
        let timer = RestTimer(clock: clock)
        timer.start(duration: 150, origin: ActiveSetID(exerciseOrder: 0, setIndex: 1), kind: .standard)

        assertGreenhouseBaselines { _ in
            RestPillView(restTimer: timer, visualBaselineDate: now)
                .frame(width: 320, height: 84)
        }
    }

    // MARK: - Move On ceremony

    @Test func moveOnCelebrationViewMatchesVisualBaseline() {
        let session = makeSession(
            weekNumber: 4,
            dayNumber: 4,
            setStates: [.logged, .logged, .logged],
            exerciseName: "Deadlift"
        )

        // The ceremony animates the stem growing and the songbird landing on the wing ease, so an
        // early frame is not pixel-stable across test ordering. Tolerate that small drift while still
        // catching a gross layout regression, in both appearances.
        assertGreenhouseBaselines(hosted: false, precision: 0.99, perceptualPrecision: 0.9) { _ in
            MoveOnCelebrationView(
                session: session,
                quoteText: "You're fucking amazing.",
                onDismiss: {}
            )
        }
    }

    // MARK: - Empty, onboarding & utility surfaces

    @Test func emptyStateViewMatchesVisualBaseline() {
        assertGreenhouseBaselines { _ in
            EmptyStateView(onSettings: {})
                .frame(width: 320)
        }
    }

    @Test func onboardingViewCardMatchesVisualBaseline() throws {
        let settings = SettingsStore(defaults: try makeVisualDefaults())

        assertGreenhouseBaselines { _ in
            OnboardingView()
                .environment(settings)
                .frame(width: 360, height: 260)
        }
    }

    @Test func settingsViewMatchesVisualBaseline() throws {
        let scenario = try WorkoutScenarios.freshConfiguredApp()
        VisualBaselineFixtureRetainer.retain(scenario)
        let sync = SyncCoordinator(client: VisualBaselineNoopSheetsClient(), context: scenario.context)

        assertGreenhouseBaselines(hosted: false) { _ in
            SettingsView()
                .environment(scenario.settings)
                .environment(sync)
                .environment(scenario.store)
        }
    }

    @Test func developerToolsViewMatchesVisualBaseline() throws {
        let scenario = try WorkoutScenarios.freshConfiguredApp()
        VisualBaselineFixtureRetainer.retain(scenario)
        let sync = SyncCoordinator(client: VisualBaselineNoopSheetsClient(), context: scenario.context)

        assertGreenhouseBaselines(hosted: false) { _ in
            NavigationStack {
                DeveloperToolsView()
            }
            .environment(scenario.settings)
            .environment(sync)
            .environment(scenario.store)
        }
    }
}

@MainActor
private final class VisualRestClock: RestClock {
    let now: Date

    init(now: Date) {
        self.now = now
    }
}

private func makeVisualDefaults() throws -> UserDefaults {
    let suiteName = "visual.\(UUID())"
    let defaults = try #require(UserDefaults(suiteName: suiteName))
    defaults.removePersistentDomain(forName: suiteName)
    return defaults
}
