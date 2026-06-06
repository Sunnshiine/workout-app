import Foundation
import SnapshotTesting
import SwiftUI
import Testing

@testable import WorkoutTracker

@MainActor
@Suite(.snapshots(record: .never))
struct GlassBearingViewsVisualTests {
    @Test func exerciseSectionMatchesVisualBaseline() {
        let exercise = makeExercise(
            name: "2-3:1:0 Competition Squat",
            setStates: [.logged, .pending, .pending, .skipped]
        )
        exercise.baseName = "Competition Squat"
        exercise.coachNote = "Work up smoothly, then hold the final rep."
        let activeSetID = ActiveSetID(exerciseOrder: exercise.order, setIndex: 1)
        let config = SessionExerciseRenderConfig(
            exercise: exercise,
            visualFocusOwner: .activeSet(activeSetID),
            activeSetID: activeSetID,
            expandedLoggedSetID: nil,
            savedLoggedSetID: nil,
            activeSetTransition: nil,
            retiringTransition: nil,
            isCollapsed: false,
            showsPairingGrip: true,
            pairingAvailability: .available,
            isPairingConfirmation: false,
            lastPerformedPresentation: LastPerformedCardPresentation(
                entry: LastPerformedEntry(
                    fullName: "2-3:1:0 Competition Squat",
                    baseName: "Competition Squat",
                    resultText: "315x5@8",
                    performedOn: Date(timeIntervalSinceReferenceDate: 0),
                    source: "Block 39 W4D2"
                )
            )
        )

        assertGlassBaseline {
            ExerciseSection(
                config: config,
                onFocus: { _ in },
                onReexpand: {},
                onLog: { _, _ in },
                onUpdateLoggedSet: { _, _ in },
                onSkip: { _ in },
                onDelete: { _ in }
            )
            .frame(width: 360)
        }
    }

    @Test func sessionTileMatchesVisualBaseline() {
        assertGlassBaseline {
            SessionTile(weekNumber: 2, dayNumber: 3, state: .current)
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

        assertGlassBaseline {
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

    @Test func loggedSetReviewCardMatchesVisualBaseline() {
        let set = makeExercise(setStates: [.logged]).sets[0]

        assertGlassBaseline {
            LoggedSetReviewCard(
                set: set,
                setOrdinal: 1,
                setCount: 4,
                showsSavedConfirmation: true,
                onCommit: { _ in },
                onCollapse: {}
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
            .background(Theme.palette(for: .sageLight).activeCardFill, in: .rect(cornerRadius: Theme.cardCornerRadius))
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

        assertFullScreenBaseline {
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
        @ViewBuilder content: () -> Content
    ) {
        let view = VisualBaselineHost {
            content()
        }

        assertSnapshot(
            of: view,
            as: .image(
                precision: WorkoutVisualBaseline.precision,
                layout: .device(config: .workoutVisualBaseline)
            ),
            testName: testName
        )
    }

    private func assertFullScreenBaseline<Content: View>(
        testName: String = #function,
        @ViewBuilder content: () -> Content
    ) {
        let view = content()
            .environment(\.themePalette, Theme.palette(for: .sageLight))
            .environment(\.locale, Locale(identifier: WorkoutVisualBaseline.localeIdentifier))
            .environment(\.dynamicTypeSize, WorkoutVisualBaseline.dynamicTypeSize)
            .preferredColorScheme(.light)

        assertSnapshot(
            of: view,
            as: .image(
                precision: WorkoutVisualBaseline.precision,
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
            Theme.palette(for: .sageLight).gradient
                .ignoresSafeArea()

            content
                .padding()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .environment(\.themePalette, Theme.palette(for: .sageLight))
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
