import SnapshotTesting
import SwiftUI
import Testing

@testable import WorkoutTracker

/// The Set Flag sheet and the card's head as each flag stands, in both appearances.
@MainActor
@Suite(.snapshots(record: .never))
struct SetFlagVisualTests {
    private struct Scene {
        let block: Block
        let set: ExerciseSet
    }

    private func loggedSet(flags: [(SetFlag?, SetFlagStanding)]) -> Scene {
        let exercise = Exercise(name: "Competition Bench Press", coachNote: nil, order: 0)
        let set = ExerciseSet(index: 1, prescribedReps: "5", prescribedLoad: "RPE 8", percentOneRM: nil, state: .logged)
        set.setLog = SetLog(weight: .pounds(185), reps: 5, rpe: .eight)
        exercise.sets = [set]
        let session = Session(dayNumber: 1, date: nil)
        session.exercises = [exercise]
        let week = Week(number: 1)
        week.sessions = [session]
        let block = Block(tabName: "Block 27")
        block.weeks = [week]
        for case (let flag?, let standing) in flags {
            set.record(flag, standing: standing)
        }
        return Scene(block: block, set: set)
    }

    private func sheetSnapshot(
        _ scene: Scene,
        draft: SetFlagDraft,
        appearance: Theme.Appearance,
        colorScheme: ColorScheme,
        testName: String = #function
    ) throws {
        let presentation = SetFlagSheetPresentation(id: try SetCoordinates(of: scene.set).id, set: scene.set)
        assertScene(appearance: appearance, colorScheme: colorScheme, testName: testName) {
            SetFlagSheet(presentation: presentation, draft: draft, onRaise: { _ in })
                .background(Theme.palette(for: appearance).paperBackground)
        }
        withExtendedLifetime(scene.block) {}
    }

    private func cardSnapshot(
        _ scene: Scene,
        mode: SetCardSlot.Mode,
        appearance: Theme.Appearance,
        colorScheme: ColorScheme,
        testName: String = #function
    ) throws {
        let store = try WorkoutScenarios.freshConfiguredApp()
        VisualFixtureRetainer.retain(store)
        let history = LastPerformedLookupStore(context: store.context)
        assertScene(appearance: appearance, colorScheme: colorScheme, testName: testName) {
            VStack {
                Spacer(minLength: 0)
                ActiveSetCard(
                    set: scene.set,
                    setOrdinal: 2,
                    setCount: 5,
                    mode: mode,
                    onLog: { _ in },
                    onSkip: {},
                    onDelete: {},
                    onFlag: {},
                    onTouchWhileHeld: {},
                    onClearMenuOpened: {},
                    onClearMenuClosed: {}
                )
                .padding(.horizontal, 16)
                Spacer(minLength: 0)
            }
            .background(Theme.palette(for: appearance).paperBackground)
            .environment(history)
            .environment(\.showsLoadBasis, true)
        }
        withExtendedLifetime(scene.block) {}
    }

    private func assertScene(
        appearance: Theme.Appearance,
        colorScheme: ColorScheme,
        testName: String,
        @ViewBuilder _ content: () -> some View
    ) {
        let view = content()
            .environment(\.themePalette, Theme.palette(for: appearance))
            .environment(\.locale, Locale(identifier: WorkoutVisualBaseline.localeIdentifier))
            .environment(\.dynamicTypeSize, WorkoutVisualBaseline.dynamicTypeSize)
            .preferredColorScheme(colorScheme)
        assertSnapshot(
            of: view,
            as: .image(
                precision: WorkoutVisualBaseline.labelAntialiasingPrecision,
                layout: .device(config: .workoutVisualBaseline)
            ),
            testName: testName
        )
    }

    private var aChosenDraft: SetFlagDraft {
        var draft = SetFlagDraft()
        draft.kind = .pain
        draft.words = "left hip pinch on the way up"
        return draft
    }

    private var everyStanding: [(SetFlag?, SetFlagStanding)] {
        [
            (SetFlag(kind: .pain, text: "left hip pinch on the way up"), .landed),
            (SetFlag(kind: .technique, text: nil), .unsynced),
            (SetFlag(kind: .swapped, text: "belt squat, the rack was taken"), .refused)
        ]
    }

    @Test func aFreshSheetMatchesVisualBaseline() throws {
        try sheetSnapshot(loggedSet(flags: []), draft: SetFlagDraft(), appearance: .day, colorScheme: .light)
    }

    @Test func aFreshSheetMatchesNightVisualBaseline() throws {
        try sheetSnapshot(loggedSet(flags: []), draft: SetFlagDraft(), appearance: .night, colorScheme: .dark)
    }

    @Test func aChosenKindWithWordsMatchesVisualBaseline() throws {
        try sheetSnapshot(loggedSet(flags: []), draft: aChosenDraft, appearance: .day, colorScheme: .light)
    }

    @Test func aChosenKindWithWordsMatchesNightVisualBaseline() throws {
        try sheetSnapshot(loggedSet(flags: []), draft: aChosenDraft, appearance: .night, colorScheme: .dark)
    }

    @Test func raisedFlagsInEveryStandingMatchVisualBaseline() throws {
        try sheetSnapshot(loggedSet(flags: everyStanding), draft: SetFlagDraft(), appearance: .day, colorScheme: .light)
    }

    @Test func raisedFlagsInEveryStandingMatchNightVisualBaseline() throws {
        try sheetSnapshot(loggedSet(flags: everyStanding), draft: SetFlagDraft(), appearance: .night, colorScheme: .dark)
    }

    @Test func aReviewOffersTheFlagMatchingVisualBaseline() throws {
        try cardSnapshot(
            loggedSet(flags: []),
            mode: .reviewingLogged(showsSavedConfirmation: false),
            appearance: .day,
            colorScheme: .light
        )
    }

    @Test func aReviewOffersTheFlagMatchingNightVisualBaseline() throws {
        try cardSnapshot(
            loggedSet(flags: []),
            mode: .reviewingLogged(showsSavedConfirmation: false),
            appearance: .night,
            colorScheme: .dark
        )
    }

    @Test func aReviewWithAnUnsyncedFlagMatchesVisualBaseline() throws {
        try cardSnapshot(
            loggedSet(flags: [(SetFlag(kind: .pain, text: nil), .unsynced)]),
            mode: .reviewingLogged(showsSavedConfirmation: false),
            appearance: .day,
            colorScheme: .light
        )
    }

    @Test func aReviewWithALandedFlagMatchesNightVisualBaseline() throws {
        try cardSnapshot(
            loggedSet(flags: [(SetFlag(kind: .pain, text: nil), .landed)]),
            mode: .reviewingLogged(showsSavedConfirmation: false),
            appearance: .night,
            colorScheme: .dark
        )
    }

    @Test func aJustSavedReviewWithAFlagMatchesVisualBaseline() throws {
        try cardSnapshot(
            loggedSet(flags: [(SetFlag(kind: .pain, text: nil), .unsynced)]),
            mode: .reviewingLogged(showsSavedConfirmation: true),
            appearance: .day,
            colorScheme: .light
        )
    }

    @Test func aRefusedFlagMatchesVisualBaseline() throws {
        try cardSnapshot(
            loggedSet(flags: [(SetFlag(kind: .pain, text: nil), .refused)]),
            mode: .reviewingLogged(showsSavedConfirmation: false),
            appearance: .day,
            colorScheme: .light
        )
    }
}
