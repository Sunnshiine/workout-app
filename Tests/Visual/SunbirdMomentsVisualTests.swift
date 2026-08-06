import SnapshotTesting
import SwiftUI
import Testing

@testable import WorkoutTracker

/// The Sunbird moments (PRD #497 slice 7, DESIGN.md §5.7 / §5.8 / §6, picks
/// sunbird-moments-a/-c/-d/-e): the Move On ceremony, the Sheet-connect screen,
/// and the glass colophon standalone — each rendered full-screen in both
/// appearances. The ceremony fixture freezes end states (reduced motion) so the
/// baseline shows the grown branch + perched bird and stays byte-stable across
/// repeat runs, retiring the #482 animation-frame flake at its source.
@MainActor
@Suite(.snapshots(record: .never))
struct SunbirdMomentsVisualTests {
    @Test func moveOnCeremonyMatchesVisualBaseline() {
        assertCeremonySnapshot(appearance: .day, colorScheme: .light)
    }

    @Test func moveOnCeremonyMatchesNightVisualBaseline() {
        assertCeremonySnapshot(appearance: .night, colorScheme: .dark)
    }

    @Test func connectScreenMatchesVisualBaseline() throws {
        try assertConnectSnapshot(appearance: .day, colorScheme: .light)
    }

    @Test func connectScreenMatchesNightVisualBaseline() throws {
        try assertConnectSnapshot(appearance: .night, colorScheme: .dark)
    }

    @Test func sunbirdColophonMatchesVisualBaseline() {
        assertColophonSnapshot(appearance: .day, colorScheme: .light)
    }

    @Test func sunbirdColophonMatchesNightVisualBaseline() {
        assertColophonSnapshot(appearance: .night, colorScheme: .dark)
    }

    // MARK: - Ceremony

    private func assertCeremonySnapshot(
        appearance: Theme.Appearance,
        colorScheme: ColorScheme,
        testName: String = #function
    ) {
        let session = makeCeremonySession()
        let view = MoveOnCelebrationView(
            session: session,
            quoteText: "Bench 92.5×5 @8 topped last week's 90.",
            onDismiss: {}
        )
        .environment(\.themePalette, Theme.palette(for: appearance))
        .environment(\.locale, Locale(identifier: WorkoutVisualBaseline.localeIdentifier))
        .environment(\.dynamicTypeSize, WorkoutVisualBaseline.dynamicTypeSize)
        // The redesigned ceremony draws its grown branch + perched bird as a
        // static end state (the animated timing nucleus is retired), so the
        // baseline is byte-stable without capturing any animation frame (#482).
        .preferredColorScheme(colorScheme)

        assertSnapshot(
            of: view,
            as: .image(precision: WorkoutVisualBaseline.precision, layout: .device(config: .workoutVisualBaseline)),
            testName: testName
        )
    }

    private func makeCeremonySession() -> Session {
        let session = Session(dayNumber: 2, date: nil)
        session.exercises = [
            makeExercise(name: "Bench Press", order: 0, setStates: Array(repeating: .logged, count: 4)),
            makeExercise(name: "Incline Press", order: 1, setStates: Array(repeating: .logged, count: 4)),
            makeExercise(name: "Cable Fly", order: 2, setStates: Array(repeating: .logged, count: 3)),
            makeExercise(name: "Triceps Pushdown", order: 3, setStates: Array(repeating: .logged, count: 3))
        ]
        let week = Week(number: 2)
        week.sessions = [session]
        let block = Block(tabName: "Block 27", squatTM: nil, benchTM: nil, deadliftTM: nil)
        block.weeks = [week]
        return session
    }

    // MARK: - Connect

    private func assertConnectSnapshot(
        appearance: Theme.Appearance,
        colorScheme: ColorScheme,
        testName: String = #function
    ) throws {
        let settings = SettingsStore(defaults: try makeConnectDefaults())
        // iOS 27 resolves OnboardingView's environment lookups during offscreen
        // render, so inject everything it observes even in the sign-in state.
        let scenario = try WorkoutScenarios.freshConfiguredApp()
        SunbirdFixtureRetainer.retain(scenario)
        let sync = SyncCoordinator(client: SunbirdNoopSheetsClient(), context: scenario.context)

        let view = OnboardingView()
            .environment(settings)
            .environment(sync)
            .environment(scenario.store)
            .environment(\.themePalette, Theme.palette(for: appearance))
            .environment(\.locale, Locale(identifier: WorkoutVisualBaseline.localeIdentifier))
            .environment(\.dynamicTypeSize, WorkoutVisualBaseline.dynamicTypeSize)
            .preferredColorScheme(colorScheme)

        assertSnapshot(
            of: view,
            as: .image(precision: WorkoutVisualBaseline.precision, layout: .device(config: .workoutVisualBaseline)),
            testName: testName
        )
    }

    // MARK: - Colophon

    private func assertColophonSnapshot(
        appearance: Theme.Appearance,
        colorScheme: ColorScheme,
        testName: String = #function
    ) {
        let palette = Theme.palette(for: appearance)
        let view = ZStack {
            palette.paperBackground
                .ignoresSafeArea()
            SunbirdColophon(diameter: 160)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .environment(\.themePalette, palette)
        .environment(\.locale, Locale(identifier: WorkoutVisualBaseline.localeIdentifier))
        .environment(\.dynamicTypeSize, WorkoutVisualBaseline.dynamicTypeSize)
        .preferredColorScheme(colorScheme)

        assertSnapshot(
            of: view,
            as: .image(precision: WorkoutVisualBaseline.precision, layout: .device(config: .workoutVisualBaseline)),
            testName: testName
        )
    }
}

@MainActor
private enum SunbirdFixtureRetainer {
    private static var retainedScenarios: [ConfiguredAppScenario] = []

    static func retain(_ scenario: ConfiguredAppScenario) {
        retainedScenarios.append(scenario)
    }
}

private actor SunbirdNoopSheetsClient: SheetsClient {
    func listTabTitles(spreadsheetId: String) async throws -> [String] { [] }

    func fetchTabSnapshot(spreadsheetId: String, tabName: String) async throws -> SheetSnapshot {
        SheetSnapshot(values: [], rowVisibility: [:])
    }

    func updateCells(spreadsheetId: String, range: String, values: [[String]]) async throws {}
}

private func makeConnectDefaults() throws -> UserDefaults {
    let suiteName = "sunbird.\(UUID())"
    let defaults = try #require(UserDefaults(suiteName: suiteName))
    defaults.removePersistentDomain(forName: suiteName)
    return defaults
}
