import Foundation
import SnapshotTesting
import SwiftUI
import Testing

@testable import WorkoutTracker

@MainActor
@Suite(.snapshots(record: .never))
struct GlassBearingViewsVisualTests {
    @Test func sessionTileMatchesVisualBaseline() {
        // The tile is wordless now — glass is retired; fill + stroke alone say state.
        // Baseline recapture for the Block grid lands with the Greenhouse visual gate (slice 8).
        assertGlassBaseline {
            SessionTile(state: .current, fillQuarters: 0)
                .frame(width: 160)
        }
    }

    @Test func restPillViewMatchesVisualBaseline() {
        let now = Date(timeIntervalSinceReferenceDate: 1_000)
        let clock = VisualRestClock(now: now)
        let timer = RestTimer(clock: clock)
        timer.start(duration: 150, origin: ActiveSetID(exerciseOrder: 0, setIndex: 1), kind: .standard)

        assertGlassBaseline {
            RestPillView(restTimer: timer, visualBaselineDate: now)
                .frame(width: 320, height: 84)
        }
    }

    @Test func smartValuePillsMatchesVisualBaseline() {
        let set = makeExercise(setStates: [.pending]).sets[0]

        assertGlassBaseline(precision: WorkoutVisualBaseline.labelAntialiasingPrecision) {
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

        assertGlassBaseline {
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

        assertGlassBaseline {
            SessionProgressHeader(
                session: session,
                activeSetID: ActiveSetID(exerciseOrder: 0, setIndex: 2),
                block: block,
                currentSession: session,
                sessionSettingsOverpullState: .pinned
            )
            .padding(14)
            .frame(width: 360)
            .background(Theme.palette(for: .day).activeCardFill, in: .rect(cornerRadius: Theme.cardCornerRadius))
            .glassEffect(.regular, in: .rect(cornerRadius: Theme.cardCornerRadius))
        }
    }

    @Test func moveOnCelebrationViewMatchesVisualBaseline() {
        let session = makeSession(
            weekNumber: 4,
            dayNumber: 4,
            setStates: [.logged, .logged, .logged],
            exerciseName: "Deadlift"
        )

        // The ceremony animates the stem growing and the songbird landing on the
        // wing ease, so an early frame is not pixel-stable across test ordering.
        // Tolerate that small drift while still catching a gross layout regression.
        // Wholesale Day/Night re-capture lands with the Greenhouse visual gate (slice 8).
        assertFullScreenBaseline(precision: 0.99, perceptualPrecision: 0.9) {
            MoveOnCelebrationView(
                session: session,
                quoteText: "You're fucking amazing.",
                onDismiss: {}
            )
        }
    }

    @Test func emptyStateViewMatchesVisualBaseline() {
        assertGlassBaseline {
            EmptyStateView(onSettings: {})
                .frame(width: 320)
        }
    }

    @Test func onboardingViewCardMatchesVisualBaseline() throws {
        let settings = SettingsStore(defaults: try makeVisualDefaults())

        assertGlassBaseline {
            OnboardingView()
                .environment(settings)
                .frame(width: 360, height: 260)
        }
    }

    @Test func settingsViewMatchesVisualBaseline() throws {
        let scenario = try WorkoutScenarios.freshConfiguredApp()
        GlassVisualFixtureRetainer.retain(scenario)
        let sync = SyncCoordinator(client: GlassVisualNoopSheetsClient(), context: scenario.context)

        assertFullScreenBaseline {
            SettingsView()
                .environment(scenario.settings)
                .environment(sync)
                .environment(scenario.store)
        }
    }

    @Test func developerToolsViewMatchesVisualBaseline() throws {
        let scenario = try WorkoutScenarios.freshConfiguredApp()
        GlassVisualFixtureRetainer.retain(scenario)
        let sync = SyncCoordinator(client: GlassVisualNoopSheetsClient(), context: scenario.context)

        assertFullScreenBaseline {
            NavigationStack {
                DeveloperToolsView()
            }
            .environment(scenario.settings)
            .environment(sync)
            .environment(scenario.store)
        }
    }

    private func assertGlassBaseline<Content: View>(
        testName: String = #function,
        precision: Float = WorkoutVisualBaseline.precision,
        @ViewBuilder content: () -> Content
    ) {
        let view = VisualBaselineHost {
            content()
        }

        assertSnapshot(
            of: view,
            as: .image(
                precision: precision,
                layout: .device(config: .workoutVisualBaseline)
            ),
            testName: testName
        )
    }

    private func assertFullScreenBaseline<Content: View>(
        testName: String = #function,
        precision: Float = WorkoutVisualBaseline.precision,
        perceptualPrecision: Float = 1,
        @ViewBuilder content: () -> Content
    ) {
        let view = content()
            .environment(\.themePalette, Theme.palette(for: .day))
            .environment(\.locale, Locale(identifier: WorkoutVisualBaseline.localeIdentifier))
            .environment(\.dynamicTypeSize, WorkoutVisualBaseline.dynamicTypeSize)
            .preferredColorScheme(.light)

        assertSnapshot(
            of: view,
            as: .image(
                precision: precision,
                perceptualPrecision: perceptualPrecision,
                layout: .device(config: .workoutVisualBaseline)
            ),
            testName: testName
        )
    }
}

private struct VisualBaselineHost<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        ZStack {
            Theme.palette(for: .day).paperBackground
                .ignoresSafeArea()

            content
                .padding()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .environment(\.themePalette, Theme.palette(for: .day))
        .environment(\.locale, Locale(identifier: WorkoutVisualBaseline.localeIdentifier))
        .environment(\.dynamicTypeSize, WorkoutVisualBaseline.dynamicTypeSize)
        .preferredColorScheme(.light)
    }
}

@MainActor
private final class VisualRestClock: RestClock {
    let now: Date

    init(now: Date) {
        self.now = now
    }
}

@MainActor
private enum GlassVisualFixtureRetainer {
    private static var retainedScenarios: [ConfiguredAppScenario] = []

    static func retain(_ scenario: ConfiguredAppScenario) {
        retainedScenarios.append(scenario)
    }
}

private actor GlassVisualNoopSheetsClient: SheetsClient {
    func listTabTitles(spreadsheetId: String) async throws -> [String] {
        []
    }

    func fetchTabSnapshot(spreadsheetId: String, tabName: String) async throws -> SheetSnapshot {
        SheetSnapshot(values: [], rowVisibility: [:])
    }

    func updateCells(spreadsheetId: String, range: String, values: [[String]]) async throws {}
}

private func makeVisualDefaults() throws -> UserDefaults {
    let suiteName = "visual.\(UUID())"
    let defaults = try #require(UserDefaults(suiteName: suiteName))
    defaults.removePersistentDomain(forName: suiteName)
    return defaults
}
