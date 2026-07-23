import Foundation
import SnapshotTesting
import SwiftUI
import Testing

@testable import WorkoutTracker

@MainActor
@Suite(.snapshots(record: .never))
struct GlassBearingViewsVisualTests {
    // `SessionTile` is rebuilt as a wordless, glass-free Block-grid tile (DESIGN.md §5.5) — it no
    // longer bears glass, so it leaves this suite. Its replacement coverage is the full focus-week
    // grid in `BlockGridVisualTests`, which renders every tile state in both appearances.

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
            .background(Theme.palette(for: .day).surface, in: .rect(cornerRadius: Theme.Radius.card))
        }
    }

    @Test func emptyStateViewMatchesVisualBaseline() {
        assertGlassBaseline {
            EmptyStateView(onSettings: {})
                .frame(width: 320)
        }
    }

    // The Move On ceremony and the Sheet-connect screen are redesigned as
    // full-screen Sunbird moments (PRD #497 slice 7) and covered in both
    // appearances by `SunbirdMomentsVisualTests`.

    // Settings is rebuilt as native, glass-free `Form` rows (DESIGN.md §5.9, PRD #497 slice 8) — it no
    // longer bears glass, so it leaves this suite. Its replacement coverage is `SettingsViewVisualTests`,
    // which renders native Settings in both appearances.

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
            Theme.palette(for: .day).gradient
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
